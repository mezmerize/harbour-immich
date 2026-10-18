#include "backgroundtasks.h"
#include "backupmanager.h"
#include "backupdatabase.h"
#include "authmanager.h"
#include "settingsmanager.h"
#include "immichapi.h"
#include "clientcertmanager.h"
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkConfiguration>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QHttpMultiPart>
#include <QHttpPart>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QDirIterator>
#include <QDateTime>
#include <QThreadPool>
#include <QDebug>

static const int STARTUP_DELAY_MS = 30 * 1000; // 30 seconds before first scan
static const int PROCESS_DELAY_MS = 2000; // 2 seconds between uploads
static const int UPLOAD_WAIT_RETRY_MS = 30 * 60 * 1000; // fallback re-check of upload conditions
static const int SETTINGS_CHANGE_DEBOUNCE_MS = 30 * 1000; // rescan 30s after last backup settings change
static const int DIR_CHANGE_DEBOUNCE_MS = 3000; // 3 seconds debounce for dir changes
static const int AUTO_SCAN_MERGE_MS = 5 * 60 * 1000; // collapse schedulers around the interval
static const int MAX_WATCHED_SUBDIRS = 50; // limit watches
static const QString SYNC_CHECK_TOKEN = QStringLiteral("backup-sync"); // token for our bulkUploadCheck requests

BackupManager::BackupManager(AuthManager *authManager, SettingsManager *settingsManager, ImmichApi *immichApi, QObject *parent)
    : QObject(parent)
    , m_authManager(authManager)
    , m_settingsManager(settingsManager)
    , m_immichApi(immichApi)
    , m_database(new BackupDatabase(this))
    , m_networkManager(new TlsNetworkAccessManager(this))
    , m_netConfigManager(new QNetworkConfigurationManager(this))
    , m_fileWatcher(new QFileSystemWatcher(this))
    , m_processTimer(new QTimer(this))
    , m_dirChangeDebounce(new QTimer(this))
    , m_retryWaitTimer(new QTimer(this))
    , m_settingsChangeDebounce(new QTimer(this))
    , m_running(false)
    , m_uploading(false)
    , m_syncing(false)
    , m_scanInProgress(false)
    , m_scanQueued(false)
    , m_changeCheckQueued(false)
    , m_scanIsFull(false)
    , m_scanToken(0)
    , m_hashToken(0)
    , m_lastAutoScanMs(0)
    , m_syncBatchesPending(0)
    , m_syncMatched(0)
    , m_syncPending(0)
    , m_currentProgress(0)
    , m_currentUploadReply(nullptr)
    , m_onWifi(false)
    , m_cachedPending(0)
    , m_cachedBackedUp(0)
    , m_cachedFailed(0)
    , m_cachedTotal(0)
    , m_statsDirty(true)
    , m_mediaTypesFetched(false)
    , m_pendingStartAfterMediaTypes(false)
    , m_cancelRequested(false)
    , m_backupCycleActive(false)
    , m_retryOnly(false)
{
    connect(m_settingsManager, &SettingsManager::backupScanIntervalChanged, this, [this]() {
        int minutes = m_settingsManager->backupScanInterval();
        qInfo() << "BackupManager: Backup interval changed to" << (minutes > 0 ? QString::number(minutes) + " minutes" : "manual only");
    });

    connect(m_settingsManager, &SettingsManager::backupFoldersChanged, this, [this]() {
        if(m_running) {
            qInfo() << "BackupManager: Watched folders changed, scheduling re-check";
            watchDirectories();
            m_settingsChangeDebounce->start();
        }
    });

    connect(m_settingsManager, &SettingsManager::backupFromDateChanged, this, [this]() {
        if (m_running) {
            qInfo() << "BackupManager: Backup from date changed, scheduling re-check";
            m_settingsChangeDebounce->start();
        }
    });

    connect(m_settingsManager, &SettingsManager::backupPhotosOnCellularChanged, this, &BackupManager::scheduleProcessQueue);
    connect(m_settingsManager, &SettingsManager::backupVideosOnCellularChanged, this, &BackupManager::scheduleProcessQueue);
    connect(m_settingsManager, &SettingsManager::backupOnlyWhileChargingChanged, this, &BackupManager::scheduleProcessQueue);

    m_processTimer->setInterval(PROCESS_DELAY_MS);
    m_processTimer->setSingleShot(true);
    connect(m_processTimer, &QTimer::timeout, this, &BackupManager::processQueue);

    m_dirChangeDebounce->setInterval(DIR_CHANGE_DEBOUNCE_MS);
    m_dirChangeDebounce->setSingleShot(true);
    connect(m_dirChangeDebounce, &QTimer::timeout, this, &BackupManager::onDebouncedDirectoryChange);

    m_retryWaitTimer->setInterval(UPLOAD_WAIT_RETRY_MS);
    m_retryWaitTimer->setSingleShot(true);
    connect(m_retryWaitTimer, &QTimer::timeout, this, &BackupManager::scheduleProcessQueue);

    m_settingsChangeDebounce->setInterval(SETTINGS_CHANGE_DEBOUNCE_MS);
    m_settingsChangeDebounce->setSingleShot(true);
    connect(m_settingsChangeDebounce, &QTimer::timeout, this, &BackupManager::checkForChanges);

    connect(m_fileWatcher, &QFileSystemWatcher::directoryChanged, this, &BackupManager::onDirectoryChanged);

    connect(m_netConfigManager, &QNetworkConfigurationManager::onlineStateChanged, this, &BackupManager::onNetworkStateChanged);
    connect(m_netConfigManager, &QNetworkConfigurationManager::configurationChanged, this, [this](const QNetworkConfiguration &) {
        updateWifiState();
    });
    updateWifiState();
}

BackupManager::~BackupManager()
{
    stopBackup();
}

bool BackupManager::initialize()
{
    if (!m_database->initialize()) {
        qWarning() << "BackupManager: Failed to initialize database";
        return false;
    }

    int stuck = m_database->resetStuckUploads();
    if (stuck > 0) {
        qInfo() << "BackupManager: Requeued" << stuck << "interrupted uploads";
    }

    refreshBackedUpCache();
    refreshStats();

    // Auto-start if enabled and authenticated
    if (m_settingsManager->backupEnabled() && m_authManager->isAuthenticated()) {
        startBackup();
    }

    connect(m_authManager, &AuthManager::isAuthenticatedChanged, this, [this]() {
        if (m_authManager->isAuthenticated()) {
            // Check if we logged in to a different server
            QString currentServer = m_authManager->serverUrl();
            QString storedServer = m_settingsManager->backupServerUrl();
            if (!storedServer.isEmpty() && currentServer != storedServer) {
                qInfo() << "BackupManager: Server changed on login - clearing backup database";
                m_database->clearAll();
                m_backedUpAssetIds.clear();
                m_deviceStatusOverrides.clear();
                m_deviceFolderCheckFingerprints.clear();
                invalidateStats(true);
                emit databaseCleared();
            }
            m_settingsManager->setBackupServerUrl(currentServer);

            if (m_settingsManager->backupEnabled()) {
                startBackup();
            }
            scheduleProcessQueue();
        } else {
            stopBackup();
        }
    });

    connect(m_immichApi, &ImmichApi::bulkUploadCheckCompleted, this, &BackupManager::onBulkUploadCheckCompleted);
    connect(m_immichApi, &ImmichApi::bulkUploadCheckFailed, this, &BackupManager::onBulkUploadCheckFailed);

    qInfo() << "BackupManager: Initialized";
    return true;
}

bool BackupManager::enabled() const
{
    return m_settingsManager->backupEnabled();
}

void BackupManager::setEnabled(bool enabled)
{
    if (m_settingsManager->backupEnabled() != enabled) {
        m_settingsManager->setBackupEnabled(enabled);
        emit enabledChanged();
        if (enabled && m_authManager->isAuthenticated()) {
            startBackup();
        } else if (!enabled) {
            stopBackup();
        }
    }
}

bool BackupManager::running() const
{
    return m_running;
}

int BackupManager::pendingCount() const
{
    if (m_statsDirty) {
        const_cast<BackupManager*>(this)->refreshStats();
    }
    return m_cachedPending;
}

int BackupManager::backedUpCount() const
{
    if (m_statsDirty) {
        const_cast<BackupManager*>(this)->refreshStats();
    }
    return m_cachedBackedUp;
}

int BackupManager::failedCount() const
{
    if (m_statsDirty) {
        const_cast<BackupManager*>(this)->refreshStats();
    }
    return m_cachedFailed;
}

int BackupManager::totalCount() const
{
    if (m_statsDirty) {
        const_cast<BackupManager*>(this)->refreshStats();
    }
    return m_cachedTotal;
}

QString BackupManager::currentFile() const
{
    return m_currentFile;
}

double BackupManager::currentProgress() const
{
    return m_currentProgress;
}

bool BackupManager::syncing() const
{
    return m_syncing;
}

bool BackupManager::backgroundActive() const
{
    return m_backupCycleActive;
}

BackupDatabase* BackupManager::database() const
{
    return m_database;
}

void BackupManager::startBackup()
{
    if (m_running)
        return;
    if (!m_authManager->isAuthenticated()) {
        qInfo() << "BackupManager: Cannot start - not authenticated";
        return;
    }

    qInfo() << "BackupManager: Starting backup service";
    m_running = true;
    emit runningChanged();

    // Fetch supported media types from server
    if (!m_mediaTypesFetched) {
        m_pendingStartAfterMediaTypes = true;
        fetchMediaTypes();
        return;
    }

    startScanningAfterMediaTypes();
}

void BackupManager::startScanningAfterMediaTypes()
{
    watchDirectories();

    // Delay first scan to avoid battery drain at startup
    QTimer *delayTimer = new QTimer(this);
    delayTimer->setSingleShot(true);
    delayTimer->setInterval(STARTUP_DELAY_MS);
    connect(delayTimer, &QTimer::timeout, this, [this, delayTimer]() {
        delayTimer->deleteLater();
        if (m_running) {
            if (m_settingsManager->backupScanInterval() > 0) {
                scanNowIfDue();
            } else {
                checkForChanges();
            }
        }
    });
    delayTimer->start();
}

void BackupManager::stopBackup()
{
    if (!m_running) return;

    qInfo() << "BackupManager: Stopping backup service";
    m_running = false;
    m_backupCycleActive = false;
    m_retryOnly = false;
    m_retryQueue.clear();
    m_processTimer->stop();
    m_dirChangeDebounce->stop();
    m_retryWaitTimer->stop();
    m_settingsChangeDebounce->stop();
    m_scanQueued = false;
    m_changeCheckQueued = false;
    ++m_scanToken;
    m_scanInProgress = false;

    if (m_currentUploadReply && !m_currentUploadReply->isFinished()) {
        m_currentUploadReply->abort();
    }
    m_uploading = false;

    if (m_syncing) {
        m_syncing = false;
        m_syncBatchesPending = 0;
        m_syncDeviceAssetToPath.clear();
        m_syncMatchedIds.clear();
        emit syncingChanged();
    }

    // Clear file watcher
    QStringList dirs = m_fileWatcher->directories();
    if (!dirs.isEmpty()) {
        m_fileWatcher->removePaths(dirs);
    }

    m_currentFile.clear();
    m_currentProgress = 0;
    emit currentFileChanged();
    emit currentProgressChanged();
    emit backgroundActiveChanged();
    emit runningChanged();
}

void BackupManager::scanNow()
{
    if (!m_running)
        return;
    m_cancelRequested = false;

    if (m_syncing || m_scanInProgress || m_retryOnly) {
        qInfo() << "BackupManager: Scan postponed - busy";
        m_scanQueued = true;
        return;
    }

    m_retryOnly = false;
    m_retryQueue.clear();

    if (!m_backupCycleActive) {
        m_backupCycleActive = true;
        emit backgroundActiveChanged();
    }

    m_lastAutoScanMs = QDateTime::currentMSecsSinceEpoch();
    startMediaScan(true);
}

void BackupManager::scanNowIfDue()
{
    if (!m_running) return;

    const qint64 intervalMs = static_cast<qint64>(m_settingsManager->backupScanInterval()) * 60 * 1000;
    const qint64 earliest = qMax(static_cast<qint64>(AUTO_SCAN_MERGE_MS), intervalMs - AUTO_SCAN_MERGE_MS);
    const qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - m_lastAutoScanMs;
    if (m_lastAutoScanMs > 0 && elapsed < earliest) {
        qDebug() << "BackupManager: Scheduled scan skipped";
        return;
    }
    scanNow();
}

void BackupManager::startMediaScan(bool fullScan)
{
    QStringList folders = m_settingsManager->backupFolders();
    qint64 fromDateMs = m_settingsManager->backupFromDateMs();
    qInfo().noquote() << "BackupManager:" << (fullScan ? "Scanning" : "Checking for changes in") << folders.size() << "folders" << (fromDateMs > 0 ? QString("(from %1)").arg(m_settingsManager->backupFromDate()) : "(no date filter)");

    QSet<QString> extensions = QSet<QString>::fromList(m_photoExtensions) + QSet<QString>::fromList(m_videoExtensions);

    m_scanInProgress = true;
    m_scanIsFull = fullScan;
    ++m_scanToken;
    MediaScanTask *task = new MediaScanTask(folders, extensions, fromDateMs, m_scanToken);
    connect(task, &MediaScanTask::completed, this, &BackupManager::onMediaScanDone);
    QThreadPool::globalInstance()->start(task);
}

void BackupManager::onMediaScanDone(quint64 token, const QVariantList &files)
{
    if (token != m_scanToken)
        return;
    m_scanInProgress = false;

    if (m_running && !m_syncing && !m_cancelRequested) {
        applyScanResults(files, m_scanIsFull);
    } else if (m_running && m_syncing && !m_cancelRequested) {
        if (m_scanIsFull) {
            m_scanQueued = true;
        } else {
            m_changeCheckQueued = true;
        }
    }
    if (m_scanQueued && !m_syncing && !m_cancelRequested && !m_retryOnly) {
        m_scanQueued = false;
        scanNow();
    } else if (m_changeCheckQueued && !m_syncing && !m_cancelRequested) {
        m_changeCheckQueued = false;
        checkForChanges();
    }
}

bool BackupManager::isInWatchedFolder(const QString &path, const QStringList &folders) const
{
    for (const QString &folder : folders) {
        if (SettingsManager::isPathWithin(path, folder))
            return true;
    }
    return false;
}

bool BackupManager::isValidTrackedFile(const QString &path, const QStringList &folders, qint64 fromDateMs) const
{
    if (!isInWatchedFolder(path, folders))
        return false;
    if (!QFile::exists(path))
        return false;
    if (fromDateMs > 0) {
        qint64 fileMod = QFileInfo(path).lastModified().toMSecsSinceEpoch();
        if (fileMod < fromDateMs) return false;
    }
    return true;
}

int BackupManager::pruneInvalidFiles(const QHash<QString, BackupDatabase::FileRecord> &records, const QStringList &folders, qint64 fromDateMs, QStringList *pendingToVerify)
{
    int removed = 0;
    for (auto it = records.constBegin(); it != records.constEnd(); ++it) {
        const QString &path = it.key();
        const int status = it->status;
        if (status != BackupDatabase::Pending && status != BackupDatabase::Failed && status != BackupDatabase::BackedUp) {
            continue;
        }
        if (!isValidTrackedFile(path, folders, fromDateMs)) {
            m_database->removeFile(path);
            removed++;
            continue;
        }
        if (pendingToVerify) {
            if (status == BackupDatabase::Pending) {
                pendingToVerify->append(path);
            } else if (status == BackupDatabase::Failed) {
                m_database->resetFile(path);
                pendingToVerify->append(path);
            }
        }
    }
    return removed;
}

void BackupManager::applyScanResults(const QVariantList &files, bool fullScan)
{
    QStringList folders = m_settingsManager->backupFolders();
    qint64 fromDateMs = m_settingsManager->backupFromDateMs();
    bool skipVerification = m_settingsManager->backupSkipVerification();

    // Single bulk query instead of per-file lookups
    const QHash<QString, BackupDatabase::FileRecord> records = m_database->allRecords();

    int changedFiles = 0;
    int added = 0;
    QStringList newFilePaths;
    QStringList changedPaths;

    for (const QVariant &v : files) {
        const QVariantMap f = v.toMap();
        const QString filePath = f[QStringLiteral("path")].toString();
        const qint64 fileSize = f[QStringLiteral("size")].toLongLong();
        const qint64 fileMod = f[QStringLiteral("modified")].toLongLong();

        auto it = records.constFind(filePath);
        if (it != records.constEnd()) {
            if (it->size != fileSize || it->modified != fileMod) {
                // File changed since tracking - reset to pending and re-verify against the server like the pending ones
                m_database->resetFile(filePath);
                changedFiles++;
                if (fullScan) {
                    changedPaths.append(filePath);
                }
            }
        } else if (fullScan) {
            newFilePaths.append(filePath);
        } else if (m_database->addFile(filePath, fileSize, fileMod)) {
            added++;
        }
    }

    // Prune tracked files that are no longer valid
    QStringList pendingToVerify;
    int removed = pruneInvalidFiles(records, folders, fromDateMs, fullScan ? &pendingToVerify : nullptr);

    if (removed > 0) {
        qInfo() << "BackupManager: Pruned" << removed << "files (deleted, outside folders, or outside date range)";
        if (fullScan) {
            refreshBackedUpCache();
        }
    }
    if (changedFiles > 0) {
        qInfo() << "BackupManager: Found" << changedFiles << "changed files";
        invalidateStats();
    }
    if (added > 0) {
        qInfo() << "BackupManager: Added" << added << "new files as pending";
    }
    if (added > 0 || removed > 0 || changedFiles > 0) {
        invalidateStats(removed > 0);
        emit localMediaChanged();
    }

    if (!fullScan) {
        return;
    }

    if (newFilePaths.isEmpty() && pendingToVerify.isEmpty() && changedPaths.isEmpty()) {
        qInfo() << "BackupManager: No new or pending files to process";
        scheduleProcessQueue();
        return;
    }

    if (skipVerification || !m_authManager->isAuthenticated()) {
        // Add all new files directly as pending
        int verified = 0;
        for (const QString &filePath : newFilePaths) {
            QFileInfo fi(filePath);
            if (fi.exists() && m_database->addFile(filePath, fi.size(), fi.lastModified().toMSecsSinceEpoch())) {
                verified++;
            }
        }
        if (verified > 0) {
            qInfo() << "BackupManager: Added" << verified << "new files as pending (no verification)";
            invalidateStats();
        }
        scheduleProcessQueue();
    } else {
        // Verify new + existing pending files against server before adding to DB
        QStringList allToVerify = newFilePaths + pendingToVerify + changedPaths;
        qInfo().noquote() << "BackupManager: Verifying" << allToVerify.size() << "files against server" << QString("(%1 new, %2 pending)").arg(newFilePaths.size()).arg(pendingToVerify.size() + changedPaths.size());
        verifyNewFiles(allToVerify);
    }
}

void BackupManager::retryFailed()
{
    QStringList failedPaths = m_database->failedFiles();
    if (failedPaths.isEmpty())
        return;

    QStringList folders = m_settingsManager->backupFolders();
    qint64 fromDateMs = m_settingsManager->backupFromDateMs();
    bool skipVerification = m_settingsManager->backupSkipVerification();

    // Validate failed files against current settings
    QStringList validPaths;
    int pruned = 0;
    for (const QString &path : failedPaths) {
        if (!isValidTrackedFile(path, folders, fromDateMs)) {
            m_database->removeFile(path);
            pruned++;
            continue;
        }
        validPaths.append(path);
    }

    if (pruned > 0) {
        qInfo() << "BackupManager: Pruned" << pruned << "invalid failed files";
    }

    if (validPaths.isEmpty()) {
        invalidateStats(pruned > 0);
        return;
    }

    // Reset only the valid failed files to pending
    for (const QString &path : validPaths) {
        m_database->resetFile(path);
    }
    invalidateStats();

    qInfo() << "Retrying" << validPaths.size() << "failed files";

    // Switch to retry only so process queue uploads only the subset of pending
    m_retryOnly = true;
    m_retryQueue = validPaths;

    if (!m_backupCycleActive) {
        m_backupCycleActive = true;
        m_cancelRequested = false;
        emit backgroundActiveChanged();
    }

    if (!skipVerification && m_authManager->isAuthenticated()) {
        verifyNewFiles(validPaths);
    } else {
        scheduleProcessQueue();
    }
}

bool BackupManager::isAssetBackedUp(const QString &remoteAssetId) const
{
    return m_backedUpAssetIds.contains(remoteAssetId);
}

void BackupManager::registerManualUpload(const QString &filePath, const QString &remoteAssetId)
{
    // Check if this file is in a watched folder
    QStringList folders = m_settingsManager->backupFolders();
    bool inWatchedFolder = false;
    for (const QString &folder : folders) {
        if (SettingsManager::isPathWithin(filePath, folder)) {
            inWatchedFolder = true;
            break;
        }
    }

    if (inWatchedFolder) {
        QFileInfo fi(filePath);
        if (fi.exists()) {
            m_database->registerManualUpload(filePath, fi.size(), fi.lastModified().toMSecsSinceEpoch(), remoteAssetId);
            m_backedUpAssetIds.insert(remoteAssetId);
            invalidateStats();
            emit fileBackedUp(filePath, remoteAssetId);
            qInfo() << "BackupManager: Registered manual upload:" << filePath;
        }
    }
}

void BackupManager::backupRecordsDropped(int removedCount)
{
    if (removedCount <= 0) {
        return;
    }
    emit localMediaChanged();
}

void BackupManager::handleServerDeletions(const QStringList &remoteAssetIds)
{
    if (remoteAssetIds.isEmpty()) {
        return;
    }
    const bool removed = m_database->removeByRemoteAssetIds(remoteAssetIds);
    for (const QString &id : remoteAssetIds) {
        m_backedUpAssetIds.remove(id);
    }
    invalidateStats(true);
    if (!removed) {
        return;
    }
    qInfo() << "BackupManager: Removed backup records for" << remoteAssetIds.size() << "assets deleted on server";
    backupRecordsDropped(1);
}

void BackupManager::reconcileWithServer(const QSet<QString> &existingIds, qint64 olderThanMs)
{
    if (existingIds.isEmpty()) {
        return;
    }
    const int removed = m_database->removeMissingRemoteAssets(existingIds, olderThanMs);
    if (removed > 0) {
        qInfo() << "BackupManager: Removed" << removed << "backup records for assets missing on server";
        refreshBackedUpCache();
        invalidateStats(true);
    }
    backupRecordsDropped(removed);
}

void BackupManager::clearDatabase()
{
    bool wasRunning = m_running;
    if (wasRunning) {
        stopBackup();
    }

    m_database->clearAll();
    m_backedUpAssetIds.clear();
    m_deviceStatusOverrides.clear();
    m_deviceFolderCheckFingerprints.clear();
    invalidateStats(true);
    emit databaseCleared();
    qInfo() << "BackupManager: Database cleared by user";

    if (wasRunning && m_settingsManager->backupEnabled() && m_authManager->isAuthenticated()) {
        startBackup();
    }
}

void BackupManager::cancelBackup()
{
    if (!m_backupCycleActive)
        return;

    qInfo() << "Cancelling backup operation";

    m_processTimer->stop();
    m_retryWaitTimer->stop();
    m_cancelRequested = true;

    // Cancel verification if in progress
    if (m_syncing) {
        m_syncing = false;
        m_syncBatchesPending = 0;
        m_syncDeviceAssetToPath.clear();
        m_syncMatchedIds.clear();
        emit syncingChanged();
    }

    // Cancel upload if in progress
    if (m_uploading && m_currentUploadReply && !m_currentUploadReply->isFinished()) {
        m_currentUploadReply->abort();
    }

    m_retryOnly = false;
    m_retryQueue.clear();
    m_scanQueued = false;
    m_changeCheckQueued = false;
    m_backupCycleActive = false;
    emit backgroundActiveChanged();
}

void BackupManager::checkForChanges()
{
    if (!m_running)
        return;
    if (!m_mediaTypesFetched)
        return;
    if (m_syncing || m_scanInProgress) {
        qInfo() << "BackupManager: Check for changes postponed - busy";
        m_changeCheckQueued = true;
        return;
    }

    startMediaScan(false);
}

void BackupManager::verifyNewFiles(const QStringList &newFilePaths)
{
    m_syncing = true;
    m_syncMatched = 0;
    m_syncPending = 0;
    m_syncDeviceAssetToPath.clear();
    m_syncMatchedIds.clear();
    emit syncingChanged();

    ++m_hashToken;
    ChecksumTask *task = new ChecksumTask(newFilePaths, m_hashToken);
    connect(task, &ChecksumTask::completed, this, &BackupManager::onChecksumsDone);
    QThreadPool::globalInstance()->start(task);
}

void BackupManager::onChecksumsDone(quint64 token, const QVariantList &entries)
{
    if (token != m_hashToken || !m_syncing)
        return;

    QJsonArray allAssets;
    for (const QVariant &v : entries) {
        const QVariantMap e = v.toMap();
        const QString filePath = e[QStringLiteral("path")].toString();
        const qint64 fileMod = e[QStringLiteral("modified")].toLongLong();
        const QString deviceAssetId = BackupDatabase::makeDeviceAssetId(QFileInfo(filePath).fileName(), fileMod);
        m_syncDeviceAssetToPath.insert(deviceAssetId, filePath);

        QJsonObject asset;
        asset["id"] = deviceAssetId;
        asset["checksum"] = e[QStringLiteral("checksum")].toString();
        allAssets.append(asset);
    }

    if (allAssets.isEmpty()) {
        qInfo() << "BackupManager: No files to verify against server";
        m_syncing = false;
        emit syncingChanged();
        if (m_scanQueued && !m_retryOnly) {
            m_scanQueued = false;
            scanNow();
        } else {
            if (m_changeCheckQueued) {
                m_changeCheckQueued = false;
                checkForChanges();
            }
            scheduleProcessQueue();
        }
        return;
    }

    static const int BATCH_SIZE = 500;
    m_syncBatchesPending = 0;
    for (int i = 0; i < allAssets.size(); i += BATCH_SIZE) {
        QJsonArray batch;
        for (int j = i; j < qMin(i + BATCH_SIZE, allAssets.size()); j++) {
            batch.append(allAssets[j]);
        }
        m_syncBatchesPending++;
        m_immichApi->bulkUploadCheck(batch, SYNC_CHECK_TOKEN);
    }
}

void BackupManager::onBulkUploadCheckCompleted(const QJsonArray &results, const QString &token)
{
    if (token != SYNC_CHECK_TOKEN || !m_syncing)
        return;

    for (const QJsonValue &val : results) {
        QJsonObject result = val.toObject();
        QString deviceAssetId = result["id"].toString();
        QString action = result["action"].toString();
        QString remoteAssetId = result["assetId"].toString();

        if (action == QStringLiteral("reject")) {
            m_syncMatchedIds.insert(deviceAssetId);
            QString filePath = m_syncDeviceAssetToPath.value(deviceAssetId);
            if (!filePath.isEmpty()) {
                QFileInfo fi(filePath);
                if (fi.exists()) {
                    if (m_database->hasFile(filePath)) {
                        // Already tracked - update status to backed up
                        m_database->setStatus(filePath, BackupDatabase::BackedUp, remoteAssetId);
                    } else {
                        // New file - insert as backed up
                        m_database->addFileAsBackedUp(filePath, fi.size(), fi.lastModified().toMSecsSinceEpoch(), remoteAssetId);
                    }
                    if (!remoteAssetId.isEmpty()) {
                        m_backedUpAssetIds.insert(remoteAssetId);
                    }
                    m_syncMatched++;
                }
            }
        }
    }

    m_syncBatchesPending--;
    if (m_syncBatchesPending <= 0) {
        finishSync();
    }
}

void BackupManager::onBulkUploadCheckFailed(const QString &token)
{
    if (token != SYNC_CHECK_TOKEN || !m_syncing)
        return;

    qWarning() << "BackupManager: Bulk upload check batch failed";
    m_syncBatchesPending--;
    if (m_syncBatchesPending <= 0) {
        finishSync();
    }
}

void BackupManager::finishSync()
{
    // All batches processed - add unmatched files as pending
    for (auto it = m_syncDeviceAssetToPath.constBegin(); it != m_syncDeviceAssetToPath.constEnd(); ++it) {
        if (!m_syncMatchedIds.contains(it.key())) {
            QFileInfo fi(it.value());
            if (fi.exists()) {
                if (!m_database->hasFile(it.value())) {
                    m_database->addFile(it.value(), fi.size(), fi.lastModified().toMSecsSinceEpoch());
                }
                m_syncPending++;
            }
        }
    }

    qInfo() << "BackupManager: Server sync complete -" << m_syncMatched << "matched," << m_syncPending << "pending";

    if (m_syncPending > 0 || m_syncMatched > 0) {
        emit localMediaChanged();
    }

    m_syncing = false;
    m_syncDeviceAssetToPath.clear();
    m_syncMatchedIds.clear();
    m_statsDirty = true;
    refreshBackedUpCache();
    emit syncingChanged();
    emit statsChanged();
    if (m_syncMatched > 0) {
        emit backupStatusChanged();
    }
    emit serverSyncComplete(m_syncMatched, m_syncPending);

    // Scan may have been dropped while syncing
    if (m_scanQueued && !m_retryOnly) {
        m_scanQueued = false;
        scanNow();
        return;
    }
    if (m_changeCheckQueued) {
        m_changeCheckQueued = false;
        checkForChanges();
    }

    // Start processing new pending files if backup is running
    scheduleProcessQueue();
}

void BackupManager::onDirectoryChanged()
{
    m_dirChangeDebounce->start();
}

void BackupManager::onDebouncedDirectoryChange()
{
    checkForChanges();
    emit localMediaChanged();
}

void BackupManager::onNetworkStateChanged()
{
    updateWifiState();
    scheduleProcessQueue();
}

void BackupManager::processQueue()
{
    if (!m_backupCycleActive)
        return;
    if (!m_running || m_uploading || m_syncing)
        return;
    if (!m_authManager->isAuthenticated()) {
        if (m_backupCycleActive) {
            m_backupCycleActive = false;
            emit backgroundActiveChanged();
        }
        return;
    }

    QString filePath;

    if (m_retryOnly) {
        for (auto it = m_retryQueue.begin(); it != m_retryQueue.end();) {
            if (!QFile::exists(*it) || m_database->fileStatus(*it) != BackupDatabase::Pending) {
                it = m_retryQueue.erase(it);
                continue;
            }
            if (canUploadNow(*it)) {
                filePath = *it;
                m_retryQueue.erase(it);
                break;
            }
            ++it;
        }
        if (filePath.isEmpty() && !m_retryQueue.isEmpty()) {
            qDebug() << "BackupManager: Conditions not met for retry uploads, waiting";
            waitForUploadConditions();
            return;
        }
        if (filePath.isEmpty()) {
            qDebug() << "BackupManager: Retry queue complete";
            m_retryOnly = false;
            if (m_backupCycleActive) {
                m_backupCycleActive = false;
                emit backgroundActiveChanged();
            }
            if (m_scanQueued && !m_syncing) {
                m_scanQueued = false;
                scanNow();
            } else if (m_changeCheckQueued && !m_syncing) {
                m_changeCheckQueued = false;
                checkForChanges();
            }
            return;
        }
    } else {
        const QStringList pending = m_database->pendingFiles(64);
        if (pending.isEmpty()) {
            qDebug() << "BackupManager: No pending files";
            if (m_backupCycleActive) {
                m_backupCycleActive = false;
                emit backgroundActiveChanged();
            }
            if (m_scanQueued && !m_syncing) {
                m_scanQueued = false;
                scanNow();
                return;
            }
            if (m_changeCheckQueued && !m_syncing) {
                m_changeCheckQueued = false;
                checkForChanges();
                return;
            }
            if (m_settingsManager->backupAutoDisable()) {
                qInfo() << "BackupManager: All files backed up, auto-disabling backup";
                setEnabled(false);
            }
            return;
        }

        int removed = 0;
        for (const QString &candidate : pending) {
            if (!QFile::exists(candidate)) {
                m_database->removeFile(candidate);
                removed++;
                continue;
            }
            if (canUploadNow(candidate)) {
                filePath = candidate;
                break;
            }
        }
        if (removed > 0) {
            invalidateStats();
        }
        if (filePath.isEmpty()) {
            qDebug() << "BackupManager: Conditions not met for upload, waiting";
            if (removed > 0 && pending.size() == removed) {
                scheduleProcessQueue();
            } else {
                waitForUploadConditions();
            }
            return;
        }
    }

    uploadFile(filePath);
}

void BackupManager::waitForUploadConditions()
{
    if (m_running) {
        m_retryWaitTimer->start();
    }
}

void BackupManager::uploadFile(const QString &filePath)
{
    QFileInfo fi(filePath);
    if (!fi.exists()) {
        m_database->setStatus(filePath, BackupDatabase::Failed, QString(), "File not found");
        invalidateStats();
        scheduleProcessQueue();
        return;
    }

    m_uploading = true;
    m_currentFile = fi.fileName();
    m_currentProgress = 0;
    emit currentFileChanged();
    emit currentProgressChanged();

    m_database->setStatus(filePath, BackupDatabase::Uploading);

    QFile *file = new QFile(filePath);
    if (!file->open(QIODevice::ReadOnly)) {
        qWarning() << "BackupManager: Cannot open file:" << filePath;
        m_database->setStatus(filePath, BackupDatabase::Failed, QString(), "Cannot open file");
        delete file;
        m_uploading = false;
        invalidateStats();
        scheduleProcessQueue();
        return;
    }

    QHttpMultiPart *multiPart = ImmichApi::buildUploadMultiPart(file, fi);

    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets"));
    QNetworkRequest request(url);
    request.setRawHeader("Authorization", QString("Bearer %1").arg(m_authManager->getAccessToken()).toUtf8());

    qInfo() << "BackupManager: Uploading" << fi.fileName();

    QNetworkReply *reply = m_networkManager->post(request, multiPart);
    multiPart->setParent(reply);
    m_currentUploadReply = reply;

    connect(reply, &QNetworkReply::uploadProgress, this, [this](qint64 bytesSent, qint64 bytesTotal) {
        if (bytesTotal > 0) {
            m_currentProgress = static_cast<double>(bytesSent) / bytesTotal;
            emit currentProgressChanged();
        }
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply, filePath]() {
        onUploadFinished(reply, filePath);
    });
}

void BackupManager::onUploadFinished(QNetworkReply *reply, const QString &filePath)
{
    m_currentUploadReply = nullptr;
    m_uploading = false;

    if (reply->error() == QNetworkReply::NoError) {
        QByteArray response = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject obj = doc.object();
        QString remoteAssetId = obj["id"].toString();
        QString status = obj["status"].toString();

        // Both "created" and "duplicate" mean it's on the server
        m_database->setStatus(filePath, BackupDatabase::BackedUp, remoteAssetId);
        m_backedUpAssetIds.insert(remoteAssetId);

        qInfo() << "BackupManager: Backed up" << QFileInfo(filePath).fileName() << "status:" << status << "id:" << remoteAssetId;

        // Delete after backup if enabled
        if (m_settingsManager->backupDeleteAfter()) {
            QFile::remove(filePath);
            qInfo() << "BackupManager: Deleted local file after backup:" << filePath;
        }

        emit fileBackedUp(filePath, remoteAssetId);

    } else if (reply->error() == QNetworkReply::OperationCanceledError) {
        // Upload was cancelled (e.g. backup stopped) - reset to pending
        m_database->setStatus(filePath, BackupDatabase::Pending);
        qInfo() << "BackupManager: Upload cancelled, reset to pending:" << filePath;

    } else {
        QString errorMsg = reply->errorString();
        int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

        // Auth error - stop backup
        if (httpStatus == 401) {
            m_database->setStatus(filePath, BackupDatabase::Pending);
            qWarning() << "BackupManager: Auth error, stopping backup";
            reply->deleteLater();
            stopBackup();
            return;
        }

        m_database->setStatus(filePath, BackupDatabase::Failed, QString(), errorMsg);
        qWarning() << "BackupManager: Upload failed:" << errorMsg;
    }

    reply->deleteLater();

    m_currentFile.clear();
    m_currentProgress = 0;
    emit currentFileChanged();
    emit currentProgressChanged();
    invalidateStats();

    scheduleProcessQueue();
}

void BackupManager::watchDirectories()
{
    // Clear existing watches
    QStringList existing = m_fileWatcher->directories();
    if (!existing.isEmpty()) {
        m_fileWatcher->removePaths(existing);
    }

    int totalWatches = 0;
    QStringList folders = m_settingsManager->backupFolders();
    for (const QString &folder : folders) {
        QDir dir(folder);
        if (!dir.exists())
            continue;

        m_fileWatcher->addPath(folder);
        totalWatches++;

        QDirIterator it(folder, QDir::Dirs | QDir::NoDotAndDotDot);
        while (it.hasNext() && totalWatches < MAX_WATCHED_SUBDIRS) {
            it.next();
            m_fileWatcher->addPath(it.filePath());
            totalWatches++;
        }
    }

    qInfo() << "BackupManager: Watching" << totalWatches << "directories";
}

void BackupManager::refreshStats()
{
    m_cachedPending = m_database->countByStatus(BackupDatabase::Pending);
    m_cachedBackedUp = m_database->countByStatus(BackupDatabase::BackedUp);
    m_cachedFailed = m_database->countByStatus(BackupDatabase::Failed);
    m_cachedTotal = m_database->totalTrackedFiles();
    m_statsDirty = false;
}

void BackupManager::refreshBackedUpCache()
{
    m_backedUpAssetIds = m_database->allBackedUpRemoteAssetIds();
    qInfo() << "BackupManager: Cached" << m_backedUpAssetIds.size() << "backed up asset IDs";
}

void BackupManager::invalidateStats(bool includeBackupStatus)
{
    m_statsDirty = true;
    emit statsChanged();
    if (includeBackupStatus)
        emit backupStatusChanged();
}

void BackupManager::scheduleProcessQueue()
{
    if (!m_backupCycleActive)
        return;
    if (m_cancelRequested) {
        m_cancelRequested = false;
        return;
    }
    if (m_running && !m_uploading && !m_syncing && !m_processTimer->isActive()) {
        m_processTimer->start();
    }
}

bool BackupManager::canUploadNow(const QString &filePath) const
{
    // Charging
    if (m_settingsManager->backupOnlyWhileCharging() && !isCharging()) {
        return false;
    }

    // Network
    bool wifi = isOnWifi();
    QString suffix = QFileInfo(filePath).suffix().toLower();

    if (isPhotoFile(suffix)) {
        if (!m_settingsManager->backupPhotosOnCellular() && !wifi) {
            return false;
        }
    } else if (isVideoFile(suffix)) {
        if (!m_settingsManager->backupVideosOnCellular() && !wifi) {
            return false;
        }
    }

    return true;
}

bool BackupManager::isOnWifi() const
{
    return m_onWifi;
}

void BackupManager::updateWifiState()
{
    bool onWifi = false;
    QList<QNetworkConfiguration> configs = m_netConfigManager->allConfigurations(QNetworkConfiguration::Active);
    for (const QNetworkConfiguration &config : configs) {
        if (config.bearerType() == QNetworkConfiguration::BearerWLAN) {
            onWifi = true;
            break;
        }
    }
    if (m_onWifi != onWifi) {
        m_onWifi = onWifi;
        emit wifiConnectedChanged();
    }
}

bool BackupManager::isCharging() const
{
    // Read battery status from sysfs
    QFile statusFile("/sys/class/power_supply/battery/status");
    if (statusFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QString status = QString::fromUtf8(statusFile.readAll()).trimmed();
        statusFile.close();
        return (status == "Charging" || status == "Full");
    }

    // Fallback: try usb power supply
    QFile usbFile("/sys/class/power_supply/usb/online");
    if (usbFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QString online = QString::fromUtf8(usbFile.readAll()).trimmed();
        usbFile.close();
        return (online == "1");
    }

    return false; // Unknown - assume not charging
}

const QStringList BackupManager::photoExtensions() const
{
    return m_photoExtensions;
}

const QStringList BackupManager::videoExtensions() const
{
    return m_videoExtensions;
}

bool BackupManager::mediaTypesReady() const
{
    return m_mediaTypesFetched;
}

bool BackupManager::isPhotoFile(const QString &suffix) const
{
    return photoExtensions().contains(suffix);
}

bool BackupManager::isVideoFile(const QString &suffix) const
{
    return videoExtensions().contains(suffix);
}

bool BackupManager::isMediaFile(const QString &suffix) const
{
    return isPhotoFile(suffix) || isVideoFile(suffix);
}

void BackupManager::requestMediaCount(const QString &path)
{
    auto *task = new MediaScanTask({path}, mediaExtensions(), 0, 0);
    connect(task, &MediaScanTask::completed, task, [this, path](quint64, const QVariantList &files) {
        emit mediaCountReady(path, files.size());
    });
    QThreadPool::globalInstance()->start(task);
}

QSet<QString> BackupManager::mediaExtensions() const
{
    return QSet<QString>::fromList(m_photoExtensions) + QSet<QString>::fromList(m_videoExtensions);
}

bool BackupManager::isVideoFilePath(const QString &filePath) const
{
    return isVideoFile(QFileInfo(filePath).suffix().toLower());
}

bool BackupManager::isDeviceFileBackedUp(const QString &filePath, qint64 fileSize, qint64 fileModified) const
{
    if (!m_database->hasFile(filePath))
        return false;
    if (m_database->fileStatus(filePath) != BackupDatabase::BackedUp)
        return false;
    if (m_database->hasFileChanged(filePath, fileSize, fileModified))
        return false;
    return true;
}

void BackupManager::markDeviceFileBackedUp(const QString &filePath, const QString &remoteAssetId)
{
    QFileInfo fi(filePath);
    if (!fi.exists())
        return;
    m_database->registerManualUpload(filePath, fi.size(), fi.lastModified().toMSecsSinceEpoch(), remoteAssetId);
    if (!remoteAssetId.isEmpty()) {
        m_backedUpAssetIds.insert(remoteAssetId);
    }
    invalidateStats();
    emit fileBackedUp(filePath, remoteAssetId);
}

int BackupManager::deviceFileStatusOverride(const QString &filePath) const
{
    return m_deviceStatusOverrides.value(filePath, 0);
}

void BackupManager::setDeviceFileStatusOverride(const QString &filePath, int status)
{
    if (status == 0) {
        m_deviceStatusOverrides.remove(filePath);
    } else {
        m_deviceStatusOverrides.insert(filePath, status);
    }
}

QString BackupManager::deviceFolderCheckFingerprint(const QString &folderPath) const
{
    return m_deviceFolderCheckFingerprints.value(folderPath);
}

void BackupManager::setDeviceFolderCheckFingerprint(const QString &folderPath, const QString &fingerprint)
{
    if (fingerprint.isEmpty()) {
        m_deviceFolderCheckFingerprints.remove(folderPath);
    } else {
        m_deviceFolderCheckFingerprints.insert(folderPath, fingerprint);
    }
}

void BackupManager::handleLocalFileDeletion(const QString &filePath)
{
    QString rid = m_database->remoteAssetIdForFile(filePath);
    m_database->removeFile(filePath);
    m_deviceStatusOverrides.remove(filePath);
    if (!rid.isEmpty()) {
        m_backedUpAssetIds.remove(rid);
    }
    invalidateStats(true);
}

void BackupManager::pruneDeletedFilesInFolder(const QString &folderPath)
{
    QString prefix = folderPath;
    if (!prefix.endsWith('/'))
        prefix += '/';

    int removed = 0;
    const QStringList all = m_database->allFilePaths();
    for (const QString &path : all) {
        if (!path.startsWith(prefix))
            continue;
        if (!QFile::exists(path)) {
            m_database->removeFile(path);
            m_deviceStatusOverrides.remove(path);
            removed++;
        }
    }
    if (removed > 0) {
        qInfo() << "BackupManager: Pruned" << removed << "missing files from" << folderPath;
        refreshBackedUpCache();
        invalidateStats(true);
    }
}

void BackupManager::ensureMediaTypesFetched()
{
    if (!m_mediaTypesFetched && m_authManager->isAuthenticated()) {
        fetchMediaTypes();
    }
}

QVariantMap BackupManager::deviceFileInfo(const QString &filePath) const
{
    QVariantMap map;
    QFileInfo fi(filePath);
    map["exists"] = fi.exists();
    map["filePath"] = filePath;
    map["fileName"] = fi.fileName();
    map["fileSize"] = fi.exists() ? fi.size() : 0;
    map["lastModified"] = fi.exists() ? fi.lastModified() : QDateTime();
    map["isVideo"] = isVideoFilePath(filePath);
    QString rid;
    if (fi.exists()) {
        rid = m_database->remoteAssetIdForFile(filePath);
    }
    map["remoteAssetId"] = rid;
    map["backedUp"] = fi.exists() && isDeviceFileBackedUp(filePath, fi.size(), fi.lastModified().toMSecsSinceEpoch());
    return map;
}

void BackupManager::fetchMediaTypes()
{
    if (!m_authManager->isAuthenticated())
        return;

    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/server/media-types"));
    QNetworkRequest request(url);
    request.setRawHeader("Authorization", QString("Bearer %1").arg(m_authManager->getAccessToken()).toUtf8());
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QNetworkReply *reply = m_networkManager->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onMediaTypesFetched(reply);
    });
}

void BackupManager::onMediaTypesFetched(QNetworkReply *reply)
{
    if (reply->error() == QNetworkReply::NoError) {
        QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        QJsonObject obj = doc.object();

        QStringList photoExts;
        QJsonArray imageArr = obj["image"].toArray();
        for (const QJsonValue &val : imageArr) {
            QString ext = val.toString().toLower();
            if (ext.startsWith("."))
                ext = ext.mid(1);
            if (!ext.isEmpty())
                photoExts.append(ext);
        }

        QStringList videoExts;
        QJsonArray videoArr = obj["video"].toArray();
        for (const QJsonValue &val : videoArr) {
            QString ext = val.toString().toLower();
            if (ext.startsWith("."))
                ext = ext.mid(1);
            if (!ext.isEmpty())
                videoExts.append(ext);
        }

        if (!photoExts.isEmpty() || !videoExts.isEmpty()) {
            m_photoExtensions = photoExts;
            m_videoExtensions = videoExts;
            m_mediaTypesFetched = true;
            emit mediaTypesReadyChanged();
            qInfo() << "BackupManager: Fetched media types from server -" << photoExts.size() << "image types," << videoExts.size() << "video types";

            // Continue startup if we were waiting for media types
            if (m_pendingStartAfterMediaTypes && m_running) {
                m_pendingStartAfterMediaTypes = false;
                startScanningAfterMediaTypes();
            }
        } else {
            qWarning() << "BackupManager: Server returned empty media types";
            emit mediaTypesFetchFailed();
            if (m_pendingStartAfterMediaTypes) {
                m_pendingStartAfterMediaTypes = false;
                qWarning() << "BackupManager: Cannot start backup - no supported media types from server";
                stopBackup();
            }
        }
    } else {
        qWarning() << "BackupManager: Failed to fetch media types from server:" << reply->errorString();
        emit mediaTypesFetchFailed();
        if (m_pendingStartAfterMediaTypes) {
            m_pendingStartAfterMediaTypes = false;
            qWarning() << "BackupManager: Cannot start backup - failed to fetch media types";
            stopBackup();
        }
    }

    reply->deleteLater();
}

