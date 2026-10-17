#ifndef SYNCENGINE_H
#define SYNCENGINE_H

#include <QObject>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkReply>
#include <QTimer>
#include <QThread>
#include <QSet>
#include <QMap>
#include <QAtomicInt>
#include <QElapsedTimer>
#include <functional>

class QSqlQuery;

class AuthManager;
class AssetDatabase;
class TlsNetworkAccessManager;
class SyncWorker;

class SyncEngine : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool syncing READ syncing NOTIFY syncingChanged)
    Q_PROPERTY(QString lastSyncTime READ lastSyncTime NOTIFY syncFinished)

public:
    SyncEngine(AuthManager *authManager, AssetDatabase *db, QObject *parent = nullptr);
    ~SyncEngine() override;

    Q_INVOKABLE void sync();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void resyncCatalog();

    bool syncing() const { return m_syncing; }
    QString lastSyncTime() const;
    qint64 syncStartedAtMs() const {
        return m_syncStartedAtMs;
    }

signals:
    void syncingChanged();
    void syncFinished(bool ok);
    void remoteAssetsDeleted(const QStringList &assetIds);

private slots:
    void onWorkerFinished(bool ok);

private:
    void startSync(bool fullReset);

    AuthManager *m_auth;
    AssetDatabase *m_db;

    QThread m_workerThread;
    SyncWorker *m_worker = nullptr;
    QAtomicInt m_cancelled;
    bool m_syncing = false;
    qint64 m_syncStartedAtMs = 0;
    bool m_syncQueued = false;
    bool m_queuedFullReset = false;
};

class SyncWorker : public QObject
{
    Q_OBJECT
public:
    SyncWorker(AssetDatabase *db, QAtomicInt *cancelFlag);

    Q_INVOKABLE void start(const QString &serverUrl, const QString &accessToken, const QString &userId, const QString &session, bool fullReset);
    Q_INVOKABLE void cancel();

signals:
    void finished(bool ok);
    void catalogChanged(int mask);
    void remoteAssetsDeleted(const QStringList &assetIds);

private slots:
    void onReadyRead();
    void onStreamFinished();

private:
    QNetworkRequest authenticatedRequest(const QUrl &url) const;
    TlsNetworkAccessManager *nam();
    void beginSync();
    void stampIdentity();
    void startStream();
    void parseLine(const QByteArray &line);
    void flushGroup();
    void queueAck(const QString &ack);
    void sendPendingAcks();
    void deleteAcks();
    void scheduleRetry();
    void maybeFinish();
    void finish(bool ok);
    int maskForType(const QString &type) const;
    void emitProgress(int mask);

    void batchExec(const QString &sql, const QList<QJsonObject> &records, const std::function<void(QSqlQuery &, const QJsonObject &)> &bind);

    void handleBatch(const QString &type, const QList<QJsonObject> &records);
    void upsertRemoteAssets(const QList<QJsonObject> &records, bool skipSeen);
    void deleteRemoteAssets(const QList<QJsonObject> &records);
    void upsertAssetExifs(const QList<QJsonObject> &records, bool skipSeen);
    void upsertStacks(const QList<QJsonObject> &records);
    void deleteStacks(const QList<QJsonObject> &records);
    void upsertUsers(const QList<QJsonObject> &records);
    void deleteUsers(const QList<QJsonObject> &records);
    void upsertAuthUsers(const QList<QJsonObject> &records);
    void upsertPartners(const QList<QJsonObject> &records);
    void deletePartners(const QList<QJsonObject> &records);
    void upsertAlbums(const QList<QJsonObject> &records);
    void deleteAlbums(const QList<QJsonObject> &records);
    void upsertAlbumUsers(const QList<QJsonObject> &records);
    void deleteAlbumUsers(const QList<QJsonObject> &records);
    void insertAlbumToAssets(const QList<QJsonObject> &records);
    void deleteAlbumToAssets(const QList<QJsonObject> &records);
    void upsertMemories(const QList<QJsonObject> &records);
    void deleteMemories(const QList<QJsonObject> &records);
    void insertMemoryAssets(const QList<QJsonObject> &records);
    void deleteMemoryAssets(const QList<QJsonObject> &records);
    void upsertPersons(const QList<QJsonObject> &records);
    void deletePersons(const QList<QJsonObject> &records);
    void upsertAssetFaces(const QList<QJsonObject> &records);
    void deleteAssetFaces(const QList<QJsonObject> &records);
    void upsertAssetEdits(const QList<QJsonObject> &records);
    void deleteAssetEdits(const QList<QJsonObject> &records);
    void upsertAssetMetadata(const QList<QJsonObject> &records);
    void deleteAssetMetadata(const QList<QJsonObject> &records);
    void upsertAssetOcr(const QList<QJsonObject> &records);
    void deleteAssetOcr(const QList<QJsonObject> &records);
    void upsertUserMetadata(const QList<QJsonObject> &records);
    void deleteUserMetadata(const QList<QJsonObject> &records);

    AssetDatabase *m_db;
    QAtomicInt *m_cancelFlag;
    TlsNetworkAccessManager *m_nam = nullptr;
    QTimer *m_retryTimer = nullptr;

    QString m_serverUrl;
    QString m_accessToken;
    QString m_userId;
    QString m_session;

    QNetworkReply *m_reply = nullptr;
    QNetworkReply *m_ackReply = nullptr;
    QByteArray m_buffer;

    QString m_groupType;
    QList<QJsonObject> m_group;
    QString m_groupLastAck;

    QMap<QString, QString> m_pendingAcks;

    QSet<QString> m_loggedUnknownTypes;
    QElapsedTimer m_progressTimer;
    bool m_progressTimerValid = false;
    bool m_emittedAssets = false;
    int m_pendingMask = 0;
    int m_retryCount = 0;
    int m_eventsThisSync = 0;
    bool m_fullReset = false;
    bool m_streamEnded = false;
    bool m_completed = false;
    QSet<QString> m_assetIdsWritten;
    QSet<QString> m_exifIdsWritten;
    bool m_resetRequested = false;
    bool m_resetRestarted = false;
    bool m_finishing = false;
};

#endif // SYNCENGINE_H
