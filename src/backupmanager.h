#ifndef BACKUPMANAGER_H
#define BACKUPMANAGER_H

#include "backupdatabase.h"
#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkConfigurationManager>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QSet>
#include <QMap>
#include <QHash>
#include <QVariantMap>
#include <QJsonArray>

class AuthManager;
class SettingsManager;
class ImmichApi;

class BackupManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY statsChanged)
    Q_PROPERTY(int backedUpCount READ backedUpCount NOTIFY statsChanged)
    Q_PROPERTY(int failedCount READ failedCount NOTIFY statsChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY statsChanged)
    Q_PROPERTY(QString currentFile READ currentFile NOTIFY currentFileChanged)
    Q_PROPERTY(double currentProgress READ currentProgress NOTIFY currentProgressChanged)
    Q_PROPERTY(bool syncing READ syncing NOTIFY syncingChanged)
    Q_PROPERTY(bool backgroundActive READ backgroundActive NOTIFY backgroundActiveChanged)
    Q_PROPERTY(bool mediaTypesReady READ mediaTypesReady NOTIFY mediaTypesReadyChanged)
    Q_PROPERTY(bool wifiConnected READ isOnWifi NOTIFY wifiConnectedChanged)

public:
    explicit BackupManager(AuthManager *authManager, SettingsManager *settingsManager, ImmichApi *immichApi, QObject *parent = nullptr);
    ~BackupManager();

    bool initialize();

    bool enabled() const;
    void setEnabled(bool enabled);
    bool running() const;
    int pendingCount() const;
    int backedUpCount() const;
    int failedCount() const;
    int totalCount() const;
    QString currentFile() const;
    double currentProgress() const;

    bool syncing() const;
    bool backgroundActive() const;

    bool mediaTypesReady() const;

    bool isOnWifi() const;

    Q_INVOKABLE void scanNow();
    Q_INVOKABLE void scanNowIfDue();
    Q_INVOKABLE void cancelBackup();
    Q_INVOKABLE void retryFailed();
    Q_INVOKABLE bool isAssetBackedUp(const QString &remoteAssetId) const;
    Q_INVOKABLE void clearDatabase();

    void startBackup();
    void stopBackup();
    void registerManualUpload(const QString &filePath, const QString &remoteAssetId);
    void handleServerDeletions(const QStringList &remoteAssetIds);
    void reconcileWithServer(const QSet<QString> &existingIds, qint64 olderThanMs);

    // On this device folders
    Q_INVOKABLE void requestMediaCount(const QString &path);
    Q_INVOKABLE void ensureMediaTypesFetched();
    Q_INVOKABLE QVariantMap deviceFileInfo(const QString &filePath) const;

    QSet<QString> mediaExtensions() const;
    bool isVideoFilePath(const QString &filePath) const;
    bool isDeviceFileBackedUp(const QString &filePath, qint64 fileSize, qint64 fileModified) const;
    void markDeviceFileBackedUp(const QString &filePath, const QString &remoteAssetId);
    void handleLocalFileDeletion(const QString &filePath);
    void pruneDeletedFilesInFolder(const QString &folderPath);

    int deviceFileStatusOverride(const QString &filePath) const;
    void setDeviceFileStatusOverride(const QString &filePath, int status);

    QString deviceFolderCheckFingerprint(const QString &folderPath) const;
    void setDeviceFolderCheckFingerprint(const QString &folderPath, const QString &fingerprint);

    BackupDatabase* database() const;

signals:
    void enabledChanged();
    void runningChanged();
    void statsChanged();
    void currentFileChanged();
    void currentProgressChanged();
    void backupStatusChanged();
    void syncingChanged();
    void databaseCleared();
    void serverSyncComplete(int matched, int pending);
    void backgroundActiveChanged();
    void mediaTypesReadyChanged();
    void mediaCountReady(const QString &path, int count);
    void mediaTypesFetchFailed();
    void fileBackedUp(const QString &filePath, const QString &remoteAssetId);
    void localMediaChanged();
    void wifiConnectedChanged();

private slots:
    void onDirectoryChanged();
    void onNetworkStateChanged();
    void onDebouncedDirectoryChange();
    void processQueue();

private:
    AuthManager *m_authManager;
    SettingsManager *m_settingsManager;
    ImmichApi *m_immichApi;
    BackupDatabase *m_database;
    QNetworkAccessManager *m_networkManager;
    QNetworkConfigurationManager *m_netConfigManager;
    QFileSystemWatcher *m_fileWatcher;
    QTimer *m_processTimer;
    QTimer *m_dirChangeDebounce;
    QTimer *m_retryWaitTimer;
    QTimer *m_settingsChangeDebounce;

    bool m_running;
    bool m_uploading;
    bool m_syncing;
    bool m_scanInProgress;
    bool m_scanQueued;
    bool m_changeCheckQueued;
    bool m_scanIsFull;
    quint64 m_scanToken;
    quint64 m_hashToken;
    qint64 m_lastAutoScanMs;

    // Server sync state
    QMap<QString, QString> m_syncDeviceAssetToPath;
    QSet<QString> m_syncMatchedIds;
    int m_syncBatchesPending;
    int m_syncMatched;
    int m_syncPending;
    QString m_currentFile;
    double m_currentProgress;
    QNetworkReply *m_currentUploadReply;
    bool m_onWifi;

    // Cached stats
    mutable int m_cachedPending;
    mutable int m_cachedBackedUp;
    mutable int m_cachedFailed;
    mutable int m_cachedTotal;
    mutable bool m_statsDirty;

    QSet<QString> m_backedUpAssetIds;
    QHash<QString, int> m_deviceStatusOverrides;
    QHash<QString, QString> m_deviceFolderCheckFingerprints;

    void watchDirectories();
    void uploadFile(const QString &filePath);
    void onUploadFinished(QNetworkReply *reply, const QString &filePath);
    void onBulkUploadCheckCompleted(const QJsonArray &results, const QString &token);
    void onBulkUploadCheckFailed(const QString &token);
    void finishSync();
    void verifyNewFiles(const QStringList &newFilePaths);
    void onChecksumsDone(quint64 token, const QVariantList &entries);
    void checkForChanges();
    void startMediaScan(bool fullScan);
    void onMediaScanDone(quint64 token, const QVariantList &files);
    void applyScanResults(const QVariantList &files, bool fullScan);
    void refreshStats();
    void refreshBackedUpCache();
    void backupRecordsDropped(int removedCount);
    void invalidateStats(bool includeBackupStatus = false);
    void scheduleProcessQueue();
    void waitForUploadConditions();

    bool canUploadNow(const QString &filePath) const;
    bool isInWatchedFolder(const QString &path, const QStringList &folders) const;
    bool isValidTrackedFile(const QString &path, const QStringList &folders, qint64 fromDateMs) const;
    int pruneInvalidFiles(const QHash<QString, BackupDatabase::FileRecord> &records, const QStringList &folders, qint64 fromDateMs, QStringList *pendingToVerify);
    void updateWifiState();
    bool isCharging() const;

    bool isPhotoFile(const QString &suffix) const;
    bool isVideoFile(const QString &suffix) const;
    bool isMediaFile(const QString &suffix) const;
    const QStringList photoExtensions() const;
    const QStringList videoExtensions() const;

    void fetchMediaTypes();
    void onMediaTypesFetched(QNetworkReply *reply);
    void startScanningAfterMediaTypes();

    QStringList m_photoExtensions;
    QStringList m_videoExtensions;
    QStringList m_retryQueue;
    bool m_mediaTypesFetched;
    bool m_pendingStartAfterMediaTypes;
    bool m_cancelRequested;
    bool m_backupCycleActive;
    bool m_retryOnly;
};

#endif
