#ifndef BACKUPMANAGER_H
#define BACKUPMANAGER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkConfigurationManager>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QSet>
#include <QMap>
#include <QJsonArray>

class AuthManager;
class SettingsManager;
class BackupDatabase;
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
    Q_PROPERTY(bool autoDisableAfterBackup READ autoDisableAfterBackup WRITE setAutoDisableAfterBackup NOTIFY autoDisableAfterBackupChanged)
    Q_PROPERTY(bool mediaTypesReady READ mediaTypesReady NOTIFY mediaTypesReadyChanged)

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

    bool autoDisableAfterBackup() const;
    void setAutoDisableAfterBackup(bool enabled);

    bool mediaTypesReady() const;

    Q_INVOKABLE void startBackup();
    Q_INVOKABLE void stopBackup();
    Q_INVOKABLE void scanNow();
    Q_INVOKABLE void cancelBackup();
    Q_INVOKABLE void retryFailed();
    Q_INVOKABLE bool isAssetBackedUp(const QString &remoteAssetId) const;
    Q_INVOKABLE void registerManualUpload(const QString &filePath, const QString &remoteAssetId);
    Q_INVOKABLE void handleServerDeletion(const QString &remoteAssetId);
    Q_INVOKABLE void clearDatabase();

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
    void autoDisableAfterBackupChanged();
    void mediaTypesReadyChanged();
    void mediaTypesFetchFailed();
    void fileBackedUp(const QString &filePath, const QString &remoteAssetId);
    void fileBackupFailed(const QString &filePath, const QString &error);

private slots:
    void onDirectoryChanged(const QString &path);
    void onNetworkStateChanged(bool isOnline);
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
    QTimer *m_scanTimer;
    QTimer *m_processTimer;
    QTimer *m_dirChangeDebounce;
    QSet<QString> m_pendingDirChanges;

    bool m_running;
    bool m_uploading;
    bool m_syncing;

    // Server sync state
    QMap<QString, QString> m_syncDeviceAssetToPath;
    QSet<QString> m_syncMatchedIds;
    int m_syncBatchesPending;
    int m_syncMatched;
    int m_syncPending;
    QString m_currentFile;
    double m_currentProgress;
    QNetworkReply *m_currentUploadReply;

    // Cached stats
    mutable int m_cachedPending;
    mutable int m_cachedBackedUp;
    mutable int m_cachedFailed;
    mutable int m_cachedTotal;
    mutable bool m_statsDirty;

    // Cached backed-up remote asset IDs for fast lookup
    QSet<QString> m_backedUpAssetIds;

    void watchDirectories();
    void uploadFile(const QString &filePath);
    void onUploadFinished(QNetworkReply *reply, const QString &filePath);
    void onBulkUploadCheckCompleted(const QJsonArray &results);
    void verifyNewFiles(const QStringList &newFilePaths);
    void checkForChanges();
    void refreshStats();
    void refreshBackedUpCache();
    void invalidateStats(bool includeBackupStatus = false);
    void scheduleProcessQueue();

    bool canUploadNow(const QString &filePath) const;
    bool isOnWifi() const;
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
    bool m_mediaTypesFetched;
    bool m_pendingStartAfterMediaTypes;
    bool m_cancelRequested;
    bool m_backupCycleActive;
};

#endif
