#include "backupmanager.h"
#include "backupdatabase.h"
#include "authmanager.h"
#include "settingsmanager.h"
#include "immichapi.h"
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
#include <QMimeDatabase>
#include <QDateTime>
#include <QCryptographicHash>
#include <QDebug>

static const int STARTUP_DELAY_MS = 30 * 1000;      // 30 seconds before first scan
static const int PROCESS_DELAY_MS = 2000;           // 2 seconds between uploads
static const int DIR_CHANGE_DEBOUNCE_MS = 3000;     // 3 seconds debounce for dir changes
static const int MAX_WATCHED_SUBDIRS = 50;          // limit inotify watches

BackupManager::BackupManager(AuthManager *authManager, SettingsManager *settingsManager, ImmichApi *immichApi, QObject *parent)
    : QObject(parent)
    , m_authManager(authManager)
    , m_settingsManager(settingsManager)
    , m_immichApi(immichApi)
    , m_database(new BackupDatabase(this))
    , m_networkManager(new QNetworkAccessManager(this))
    , m_netConfigManager(new QNetworkConfigurationManager(this))
    , m_fileWatcher(new QFileSystemWatcher(this))
    , m_scanTimer(new QTimer(this))
    , m_processTimer(new QTimer(this))
    , m_dirChangeDebounce(new QTimer(this))
    , m_running(false)
    , m_uploading(false)
    , m_syncing(false)
    , m_syncBatchesPending(0)
    , m_syncMatched(0)
    , m_syncPending(0)
    , m_currentProgress(0)
    , m_currentUploadReply(nullptr)
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
    int intervalMinutes = m_settingsManager->backupScanInterval();
    if (intervalMinutes > 0) {
        m_scanTimer->setInterval(intervalMinutes * 60 * 1000);
    }
    m_scanTimer->setSingleShot(false);
    connect(m_scanTimer, &QTimer::timeout, this, &BackupManager::scanNow);

    connect(m_settingsManager, &SettingsManager::backupScanIntervalChanged, this, [this]() {
        int minutes = m_settingsManager->backupScanInterval();
        if (minutes > 0) {
            m_scanTimer->setInterval(minutes * 60 * 1000);
            if (m_running && !m_scanTimer->isActive()) {
                m_scanTimer->start();
            }
        } else {
            m_scanTimer->stop();
        }
        qInfo() << "BackupManager: Backup interval changed to" << (minutes > 0 ? QString::number(minutes) + " minutes" : "manual only");
    });

    connect(m_settingsManager, &SettingsManager::backupFoldersChanged, this, [this]() {
        if(m_running) {
            qInfo() << "BackupManager: Watched folders changed, checking for changes";
            watchDirectories();
            checkForChanges();
        }
    });

    connect(m_settingsManager, &SettingsManager::backupFromDateChanged, this, [this]() {
        if (m_running) {
            qInfo() << "BackupManager: Backup from date changed, checking for changes";
            checkForChanges();
        }
    });

    m_processTimer->setInterval(PROCESS_DELAY_MS);
    m_processTimer->setSingleShot(true);
    connect(m_processTimer, &QTimer::timeout, this, &BackupManager::processQueue);

    m_dirChangeDebounce->setInterval(DIR_CHANGE_DEBOUNCE_MS);
    m_dirChangeDebounce->setSingleShot(true);
    connect(m_dirChangeDebounce, &QTimer::timeout, this, &BackupManager::onDebouncedDirectoryChange);

    connect(m_fileWatcher, &QFileSystemWatcher::directoryChanged, this, &BackupManager::onDirectoryChanged);

    connect(m_netConfigManager, &QNetworkConfigurationManager::onlineStateChanged, this, &BackupManager::onNetworkStateChanged);
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
                invalidateStats(true);
                emit databaseCleared();
            }
            m_settingsManager->setBackupServerUrl(currentServer);

            if (m_settingsManager->backupEnabled()) {
                startBackup();
            }
        } else {
            stopBackup();
        }
    });

    connect(m_immichApi, &ImmichApi::bulkUploadCheckCompleted, this, &BackupManager::onBulkUploadCheckCompleted);

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
    if (m_running) return;
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
                scanNow();
                m_scanTimer->start();
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
    m_scanTimer->stop();
    m_processTimer->stop();
    m_dirChangeDebounce->stop();
    m_pendingDirChanges.clear();

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
    if (!m_running) return;
    m_cancelRequested = false;
    m_retryOnly = false;
    m_retryQueue.clear();

    if (!m_backupCycleActive) {
        m_backupCycleActive = true;
        emit backgroundActiveChanged();
    }

    if (m_syncing) {
        qInfo() << "BackupManager: Scan skipped - verification in progress";
        return;
    }

    QStringList folders = m_settingsManager->backupFolders();
    qint64 fromDateMs = m_settingsManager->backupFromDateMs();
    bool skipVerification = m_settingsManager->backupSkipVerification();
    qInfo().noquote() << "BackupManager: Scanning" << folders.size() << "folders" << (fromDateMs > 0 ? QString("(from %1)").arg(m_settingsManager->backupFromDate()) : "(no date filter)") << (skipVerification ? "(skip verification)" : "(with verification)");

    int changedFiles = 0;
    QStringList newFilePaths;

    for (const QString &folder : folders) {
        QDir dir(folder);
        if (!dir.exists()) continue;

        QDirIterator it(folder, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            QFileInfo fi = it.fileInfo();
            QString suffix = fi.suffix().toLower();

            if (!isMediaFile(suffix)) continue;

            QString filePath = fi.absoluteFilePath();
            qint64 fileSize = fi.size();
            qint64 fileMod = fi.lastModified().toMSecsSinceEpoch();

            // Skip files older than the configured starting date
            if (fromDateMs > 0 && fileMod < fromDateMs) continue;

            if (m_database->hasFile(filePath)) {
                // Check if file was modified since last tracking
                if (m_database->hasFileChanged(filePath, fileSize, fileMod)) {
                    // File changed - reset to pending
                    m_database->resetFile(filePath);
                    changedFiles++;
                }
            } else {
                newFilePaths.append(filePath);
            }
        }
    }

    auto isInWatchedFolder = [&folders](const QString &path) {
        for (const QString &folder : folders) {
            if (path.startsWith(folder)) return true;
        }
        return false;
    };
    auto isValidTrackedFile = [&isInWatchedFolder, fromDateMs](const QString &path) {
        if (!isInWatchedFolder(path)) return false;
        if (!QFile::exists(path)) return false;
        if (fromDateMs > 0) {
            qint64 fileMod = QFileInfo(path).lastModified().toMSecsSinceEpoch();
            if (fileMod < fromDateMs) return false;
        }
        return true;
    };

    // Prune all tracked files that are no longer valid
    int removed = 0;
    QStringList pendingToVerify;
    QStringList pendingPaths = m_database->pendingFiles(100000);
    for (const QString &path : pendingPaths) {
        if (!isValidTrackedFile(path)) {
            m_database->removeFile(path);
            removed++;
        } else {
            pendingToVerify.append(path);
        }
    }
    QStringList failedPaths = m_database->failedFiles();
    for (const QString &path : failedPaths) {
        if (!isValidTrackedFile(path)) {
            m_database->removeFile(path);
            removed++;
        } else {
            m_database->resetFile(path);
            pendingToVerify.append(path);
        }
    }
    QStringList backedUpPaths = m_database->backedUpFiles();
    for (const QString &path : backedUpPaths) {
        if (!isValidTrackedFile(path)) {
            m_database->removeFile(path);
            removed++;
        }
    }
    if (removed > 0) {
        qInfo() << "BackupManager: Pruned" << removed << "files (deleted, outside folders, or outside date range)";
        m_statsDirty = true;
        refreshBackedUpCache();
        emit statsChanged();
        emit backupStatusChanged();
    }

    if (changedFiles > 0) {
        qInfo() << "BackupManager: Found" << changedFiles << "changed files";
        invalidateStats();
    }

    bool hasNewFiles = !newFilePaths.isEmpty();
    bool hasPendingFiles = !pendingToVerify.isEmpty();

    if (!hasNewFiles && !hasPendingFiles) {
        qInfo() << "BackupManager: No new or pending files to process";
        scheduleProcessQueue();
        return;
    }

    if (skipVerification || !m_authManager->isAuthenticated()) {
        // Add all new files directly as pending
        int added = 0;
        for (const QString &filePath : newFilePaths) {
            QFileInfo fi(filePath);
            if (fi.exists() && m_database->addFile(filePath, fi.size(), fi.lastModified().toMSecsSinceEpoch())) {
                added++;
            }
        }
        if (added > 0) {
            qInfo() << "BackupManager: Added" << added << "new files as pending (no verification)";
            invalidateStats();
        }
        scheduleProcessQueue();
    } else {
        // Verify new + existing pending files against server before adding to DB
        QStringList allToVerify = newFilePaths + pendingToVerify;
        qInfo().noquote() << "BackupManager: Verifying" << allToVerify.size() << "files against server" << QString("(%1 new, %2 pending)").arg(newFilePaths.size()).arg(pendingToVerify.size());
        verifyNewFiles(allToVerify);
    }
}

void BackupManager::retryFailed()
{
    QStringList failedPaths = m_database->failedFiles();
    if (failedPaths.isEmpty()) return;

    QStringList folders = m_settingsManager->backupFolders();
    qint64 fromDateMs = m_settingsManager->backupFromDateMs();
    bool skipVerification = m_settingsManager->backupSkipVerification();

    auto isInWatchedFolder = [&folders](const QString &path) {
        for (const QString &folder : folders) {
            if (path.startsWith(folder)) return true;
        }
        return false;
    };

    // Validate failed files against current settings
    QStringList validPaths;
    int pruned = 0;
    for (const QString &path : failedPaths) {
        if (!QFile::exists(path) || !isInWatchedFolder(path)) {
            m_database->removeFile(path);
            pruned++;
            continue;
        }
        if (fromDateMs > 0) {
            qint64 fileMod = QFileInfo(path).lastModified().toMSecsSinceEpoch();
            if (fileMod < fromDateMs) {
                m_database->removeFile(path);
                pruned++;
                continue;
            }
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
        if (filePath.startsWith(folder)) {
            inWatchedFolder = true;
            break;
        }
    }

    if (inWatchedFolder) {
        QFileInfo fi(filePath);
        if (fi.exists()) {
            m_database->registerManualUpload(filePath, fi.size(), fi.lastModified().toMSecsSinceEpoch(), remoteAssetId);
            m_backedUpAssetIds.insert(remoteAssetId);
            invalidateStats(true);
            qInfo() << "BackupManager: Registered manual upload:" << filePath;
        }
    }
}

void BackupManager::handleServerDeletion(const QString &remoteAssetId)
{
    if (m_database->isRemoteAssetFromBackup(remoteAssetId)) {
        m_database->markDeletedOnServer(remoteAssetId);
        m_backedUpAssetIds.remove(remoteAssetId);
        invalidateStats(true);
        qInfo() << "BackupManager: Marked as deleted on server:" << remoteAssetId;
    }
}

void BackupManager::clearDatabase()
{
    // Stop any in-progress backup first
    bool wasRunning = m_running;
    if (wasRunning) {
        stopBackup();
    }

    m_database->clearAll();
    m_backedUpAssetIds.clear();
    invalidateStats(true);
    emit databaseCleared();
    qInfo() << "BackupManager: Database cleared by user";

    // Restart if it was running
    if (wasRunning && m_settingsManager->backupEnabled() && m_authManager->isAuthenticated()) {
        startBackup();
    }
}

void BackupManager::cancelBackup()
{
    if (!m_backupCycleActive) return;

    qInfo() << "Cancelling backup operation";

    m_processTimer->stop();
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
    m_backupCycleActive = false;
    emit backgroundActiveChanged();
}

void BackupManager::checkForChanges()
{
    if (!m_running) return;
    if (!m_mediaTypesFetched) return;
    if (m_syncing) {
        qInfo() << "BackupManager: Check for changes postponed - verification in progress";
        return;
    }

    QStringList folders = m_settingsManager->backupFolders();
    qint64 fromDateMs = m_settingsManager->backupFromDateMs();

    qInfo() << "BackupManager: Checking for file changes";

    int added = 0;
    for (const QString &folder : folders) {
        QDir dir(folder);
        if (!dir.exists()) continue;

        QDirIterator it(folder, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            QFileInfo fi = it.fileInfo();
            QString suffix = fi.suffix().toLower();

            if (!isMediaFile(suffix)) continue;

            QString filePath = fi.absoluteFilePath();
            qint64 fileMod = fi.lastModified().toMSecsSinceEpoch();

            // Skip files older than the configured date
            if (fromDateMs > 0 && fileMod < fromDateMs) continue;

            if (!m_database->hasFile(filePath)) {
                if (m_database->addFile(filePath, fi.size(), fileMod)) {
                    added++;
                }
            }
        }
    }

    // Prune all tracked files that are no longer valid
    auto isInWatchedFolder = [&folders](const QString &path) {
        for (const QString &folder : folders) {
            if (path.startsWith(folder)) return true;
        }
        return false;
    };
    auto isValidTrackedFile = [&isInWatchedFolder, fromDateMs](const QString &path) {
        if (!isInWatchedFolder(path)) return false;
        if (!QFile::exists(path)) return false;
        if (fromDateMs > 0) {
            qint64 fileMod = QFileInfo(path).lastModified().toMSecsSinceEpoch();
            if (fileMod < fromDateMs) return false;
        }
        return true;
    };

    int removed = 0;
    QStringList pendingPaths = m_database->pendingFiles(100000);
    for (const QString &path : pendingPaths) {
        if (!isValidTrackedFile(path)) {
            m_database->removeFile(path);
            removed++;
        }
    }
    QStringList failedPaths = m_database->failedFiles();
    for (const QString &path : failedPaths) {
        if (!isValidTrackedFile(path)) {
            m_database->removeFile(path);
            removed++;
        }
    }
    QStringList backedUpPaths = m_database->backedUpFiles();
    for (const QString &path : backedUpPaths) {
        if (!isValidTrackedFile(path)) {
            m_database->removeFile(path);
            removed++;
        }
    }

    if (removed > 0) {
        qInfo() << "BackupManager: Pruned" << removed << "files (deleted, outside folders, or outside date range)";
    }
    if (added > 0) {
        qInfo() << "BackupManager: Added" << added << "new files as pending";
    }
    if (added > 0 || removed > 0) {
        invalidateStats(removed > 0);
    }
}

void BackupManager::verifyNewFiles(const QStringList &newFilePaths)
{
    m_syncing = true;
    m_syncMatched = 0;
    m_syncPending = 0;
    m_syncDeviceAssetToPath.clear();
    m_syncMatchedIds.clear();
    emit syncingChanged();

    QJsonArray allAssets;

    for (const QString &filePath : newFilePaths) {
        QFileInfo fi(filePath);
        if (!fi.exists()) continue;

        // Compute checksums
        QFile file(filePath);
        if (!file.open(QIODevice::ReadOnly)) continue;
        QCryptographicHash hash(QCryptographicHash::Sha1);
        hash.addData(&file);
        file.close();
        QString checksum = hash.result().toHex();

        qint64 fileMod = fi.lastModified().toMSecsSinceEpoch();
        QString deviceAssetId = BackupDatabase::makeDeviceAssetId(fi.fileName(), fileMod);
        m_syncDeviceAssetToPath.insert(deviceAssetId, filePath);

        QJsonObject asset;
        asset["id"] = deviceAssetId;
        asset["checksum"] = checksum;
        allAssets.append(asset);
    }

    if (allAssets.isEmpty()) {
        qInfo() << "BackupManager: No files to verify against server";
        m_syncing = false;
        emit syncingChanged();
        return;
    }

    // Send in batches of 500
    static const int BATCH_SIZE = 500;
    m_syncBatchesPending = 0;
    for (int i = 0; i < allAssets.size(); i += BATCH_SIZE) {
        QJsonArray batch;
        for (int j = i; j < qMin(i + BATCH_SIZE, allAssets.size()); j++) {
            batch.append(allAssets[j]);
        }
        m_syncBatchesPending++;
        m_immichApi->bulkUploadCheck(batch);
    }
}

void BackupManager::onBulkUploadCheckCompleted(const QJsonArray &results)
{
    if (!m_syncing) return;

    // Process results: action "reject" means asset exists on server (duplicate by checksum)
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

        m_syncing = false;
        m_syncDeviceAssetToPath.clear();
        m_syncMatchedIds.clear();
        m_statsDirty = true;
        refreshBackedUpCache();
        emit syncingChanged();
        emit statsChanged();
        emit backupStatusChanged();
        emit serverSyncComplete(m_syncMatched, m_syncPending);

        // Start processing new pending files if backup is running
        scheduleProcessQueue();
    }
}

void BackupManager::onDirectoryChanged(const QString &path)
{
    // Collect changed paths and debounce - avoids scanning on every rapid change
    m_pendingDirChanges.insert(path);
    m_dirChangeDebounce->start(); // restarts the 3s timer
}

void BackupManager::onDebouncedDirectoryChange()
{
    m_pendingDirChanges.clear();
    checkForChanges();
}

void BackupManager::onNetworkStateChanged(bool isOnline)
{
    Q_UNUSED(isOnline)
    scheduleProcessQueue();
}

void BackupManager::processQueue()
{
    if (!m_running || m_uploading || m_syncing) return;
    if (!m_authManager->isAuthenticated()) return;

    QString filePath;

    if (m_retryOnly) {
        while (!m_retryQueue.isEmpty()) {
            QString candidate = m_retryQueue.takeFirst();
            if (QFile::exists(candidate) && m_database->fileStatus(candidate) == BackupDatabase::Pending) {
                filePath = candidate;
                break;
            }
        }
        if (filePath.isEmpty()) {
            qDebug() << "BackupManager: Retry queue complete";
            m_retryOnly = false;
            if (m_backupCycleActive) {
                m_backupCycleActive = false;
                emit backgroundActiveChanged();
            }
            return;
        }
    } else {
        QStringList pending = m_database->pendingFiles(1);
        if (pending.isEmpty()) {
            qDebug() << "BackupManager: No pending files";
            if (m_backupCycleActive) {
                m_backupCycleActive = false;
                emit backgroundActiveChanged();
            }
            if (m_settingsManager->backupAutoDisable()) {
                qInfo() << "BackupManager: All files backed up, auto-disabling backup";
                setEnabled(false);
            }
            return;
        }
        filePath = pending.first();
    }

    // Check if file still exists
    QFileInfo fi(filePath);
    if (!fi.exists()) {
        m_database->removeFile(filePath);
        invalidateStats();
        scheduleProcessQueue();
        return;
    }

    // Check if we can upload now (network/charging conditions)
    if (!canUploadNow(filePath)) {
        qDebug() << "BackupManager: Conditions not met for upload, waiting...";
        return;
    }

    uploadFile(filePath);
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
        emit fileBackupFailed(filePath, "Cannot open file");
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
        emit fileBackupFailed(filePath, errorMsg);
    }

    reply->deleteLater();

    m_currentFile.clear();
    m_currentProgress = 0;
    emit currentFileChanged();
    emit currentProgressChanged();
    invalidateStats(true);

    // Process next file
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
        if (!dir.exists()) continue;

        m_fileWatcher->addPath(folder);
        totalWatches++;

        // Watch subdirectories (one level deep for efficiency)
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
    // Check charging requirement
    if (m_settingsManager->backupOnlyWhileCharging() && !isCharging()) {
        return false;
    }

    // Check network requirements
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
    QList<QNetworkConfiguration> configs = m_netConfigManager->allConfigurations(QNetworkConfiguration::Active);
    for (const QNetworkConfiguration &config : configs) {
        if (config.bearerType() == QNetworkConfiguration::BearerWLAN) {
            return true;
        }
    }
    return false;
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

void BackupManager::fetchMediaTypes()
{
    if (!m_authManager->isAuthenticated()) return;

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
            if (ext.startsWith(".")) ext = ext.mid(1);
            if (!ext.isEmpty()) photoExts.append(ext);
        }

        QStringList videoExts;
        QJsonArray videoArr = obj["video"].toArray();
        for (const QJsonValue &val : videoArr) {
            QString ext = val.toString().toLower();
            if (ext.startsWith(".")) ext = ext.mid(1);
            if (!ext.isEmpty()) videoExts.append(ext);
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

QStringList BackupManager::supportedPhotoExtensions() const
{
    return m_photoExtensions;
}

QStringList BackupManager::supportedVideoExtensions() const
{
    return m_videoExtensions;
}

bool BackupManager::autoDisableAfterBackup() const
{
    return m_settingsManager->backupAutoDisable();
}

void BackupManager::setAutoDisableAfterBackup(bool enabled)
{
    m_settingsManager->setBackupAutoDisable(enabled);
    emit autoDisableAfterBackupChanged();
}
