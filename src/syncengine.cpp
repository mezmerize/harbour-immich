#include "syncengine.h"
#include "authmanager.h"
#include "assetdatabase.h"
#include "clientcertmanager.h"
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonParseError>
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlDatabase>
#include <QDateTime>
#include <QDebug>
#include <QSet>
#include <QBuffer>
#include <QMetaObject>
#include <QCryptographicHash>

namespace {

const int kSyncEventBatchSize = 5000;
const int kMaxRetries = 8;
const qint64 kReadBufferSize = 16 * 1024 * 1024;
const qint64 kProgressIntervalMs = 2000;
const qint64 kBulkProgressIntervalMs = 5000;

QStringList requestTypes()
{
    return {
        QStringLiteral("AuthUsersV1"),
        QStringLiteral("UsersV1"),
        QStringLiteral("AssetsV2"),
        QStringLiteral("AssetExifsV1"),
        QStringLiteral("AssetEditsV1"),
        QStringLiteral("AssetMetadataV1"),
        QStringLiteral("PartnersV1"),
        QStringLiteral("PartnerAssetsV2"),
        QStringLiteral("PartnerAssetExifsV1"),
        QStringLiteral("AlbumsV2"),
        QStringLiteral("AlbumUsersV1"),
        QStringLiteral("AlbumAssetsV2"),
        QStringLiteral("AlbumAssetExifsV1"),
        QStringLiteral("AlbumToAssetsV1"),
        QStringLiteral("MemoriesV1"),
        QStringLiteral("MemoryToAssetsV1"),
        QStringLiteral("StacksV1"),
        QStringLiteral("PartnerStacksV1"),
        QStringLiteral("UserMetadataV1"),
        QStringLiteral("PeopleV1"),
        QStringLiteral("AssetFacesV2"),
        QStringLiteral("AssetOcrV1"),
    };
}

QVariant nullIfMissing(const QJsonObject &o, const char *key)
{
    const QJsonValue v = o.value(QLatin1String(key));
    return (v.isUndefined() || v.isNull()) ? QVariant() : v.toVariant();
}

QVariant textIfMissing(const QJsonObject &o, const char *key, const QString &fallback = QString())
{
    const QJsonValue v = o.value(QLatin1String(key));
    return (v.isUndefined() || v.isNull()) ? fallback : v.toString();
}

int intIfMissing(const QJsonObject &o, const char *key)
{
    const QJsonValue v = o.value(QLatin1String(key));
    return v.isDouble() ? v.toInt() : 0;
}

QString nowIso()
{
    return QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'"));
}

} // namespace

SyncEngine::SyncEngine(AuthManager *authManager, AssetDatabase *db, QObject *parent)
    : QObject(parent)
    , m_auth(authManager)
    , m_db(db)
{
    m_cancelled.store(0);
    m_workerThread.setObjectName(QStringLiteral("sync"));
    m_worker = new SyncWorker(db, &m_cancelled);
    m_worker->moveToThread(&m_workerThread);
    m_workerThread.start();
    connect(m_worker, &SyncWorker::finished, this, &SyncEngine::onWorkerFinished);
    connect(m_worker, &SyncWorker::catalogChanged, m_db, &AssetDatabase::notifyChanged);
    connect(m_worker, &SyncWorker::remoteAssetsDeleted, this, &SyncEngine::remoteAssetsDeleted);
    connect(&m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);
}

SyncEngine::~SyncEngine()
{
    QMetaObject::invokeMethod(m_worker, "cancel", Qt::QueuedConnection);
    m_workerThread.quit();
    m_workerThread.wait();
    m_worker = nullptr;
}

QString SyncEngine::lastSyncTime() const
{
    return m_db->metaValue(QStringLiteral("last_sync_at"));
}

void SyncEngine::sync()
{
    startSync(false);
}

void SyncEngine::resyncCatalog()
{
    startSync(true);
}

void SyncEngine::startSync(bool fullReset)
{
    if (m_syncing) {
        m_syncQueued = true;
        m_queuedFullReset = m_queuedFullReset || fullReset;
        return;
    }
    if (m_auth->getAccessToken().isEmpty() || m_auth->serverUrl().isEmpty()) {
        return;
    }
    if (!m_db->db().isOpen()) {
        qWarning() << "SyncEngine: Catalog database not open, skipping sync";
        return;
    }

    const QString server = m_auth->serverUrl();
    const QString userId = m_auth->userId();
    const QString session = QString::fromLatin1(QCryptographicHash::hash(m_auth->getAccessToken().toUtf8(), QCryptographicHash::Sha1).toHex());
    const QString storedServer = m_db->metaValue(QStringLiteral("catalog_server"));
    const QString storedUser = m_db->metaValue(QStringLiteral("catalog_user"));
    const QString storedSession = m_db->metaValue(QStringLiteral("catalog_session"));
    if (m_db->metaValue(QStringLiteral("last_sync_at")).isEmpty() || storedServer != server || storedSession != session || (!storedUser.isEmpty() && !userId.isEmpty() && storedUser != userId)) {
        fullReset = true;
    }

    if (!userId.isEmpty()) {
        m_db->setMetaValue(QStringLiteral("current_user_id"), userId);
    }

    m_syncing = true;
    m_syncStartedAtMs = QDateTime::currentMSecsSinceEpoch();
    m_cancelled.store(0);
    emit syncingChanged();

    qInfo() << "SyncEngine: Starting catalog sync";
    QMetaObject::invokeMethod(m_worker, "start", Qt::QueuedConnection, Q_ARG(QString, server), Q_ARG(QString, m_auth->getAccessToken()), Q_ARG(QString, userId), Q_ARG(QString, session), Q_ARG(bool, fullReset));
}

void SyncEngine::cancel()
{
    if (!m_syncing) {
        return;
    }
    m_cancelled.store(1);
    QMetaObject::invokeMethod(m_worker, "cancel", Qt::QueuedConnection);
}

void SyncEngine::onWorkerFinished(bool ok)
{
    m_syncing = false;
    m_cancelled.store(0);
    emit syncingChanged();
    emit syncFinished(ok);
    if (m_syncQueued) {
        const bool queuedFull = m_queuedFullReset;
        m_syncQueued = false;
        m_queuedFullReset = false;
        QTimer::singleShot(0, this, [this, queuedFull]() { startSync(queuedFull); });
    }
}

SyncWorker::SyncWorker(AssetDatabase *db, QAtomicInt *cancelFlag)
    : m_db(db)
    , m_cancelFlag(cancelFlag)
{
}

TlsNetworkAccessManager *SyncWorker::nam()
{
    if (!m_nam) {
        m_nam = new TlsNetworkAccessManager(this);
    }
    return m_nam;
}

QNetworkRequest SyncWorker::authenticatedRequest(const QUrl &url) const
{
    QNetworkRequest request(url);
    request.setRawHeader("Authorization", QStringLiteral("Bearer %1").arg(m_accessToken).toUtf8());
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    return request;
}

void SyncWorker::start(const QString &serverUrl, const QString &accessToken, const QString &userId, const QString &session, bool fullReset)
{
    m_serverUrl = serverUrl;
    m_accessToken = accessToken;
    m_userId = userId;
    m_session = session;
    m_fullReset = fullReset;

    m_buffer.clear();
    m_groupType.clear();
    m_group.clear();
    m_groupLastAck.clear();
    m_pendingAcks.clear();
    m_retryCount = 0;
    m_eventsThisSync = 0;
    m_pendingMask = 0;
    m_emittedAssets = false;
    m_progressTimerValid = false;
    m_streamEnded = false;
    m_completed = false;
    m_resetRequested = false;
    m_resetRestarted = false;
    m_finishing = false;
    m_assetIdsWritten.clear();
    m_exifIdsWritten.clear();

    if (!m_retryTimer) {
        m_retryTimer = new QTimer(this);
        m_retryTimer->setSingleShot(true);
        connect(m_retryTimer, &QTimer::timeout, this, &SyncWorker::startStream);
    }

    if (m_cancelFlag->load() != 0) {
        finish(false);
        return;
    }
    beginSync();
}

void SyncWorker::beginSync()
{
    if (!m_fullReset) {
        startStream();
        return;
    }
    deleteAcks();
}

void SyncWorker::deleteAcks()
{
    QUrl url(m_serverUrl + QStringLiteral("/api/sync/ack"));
    QNetworkRequest request = authenticatedRequest(url);
    const QByteArray payload = QJsonDocument(QJsonObject()).toJson(QJsonDocument::Compact);

    auto *buffer = new QBuffer();
    buffer->setData(payload);
    buffer->open(QIODevice::ReadOnly);
    QNetworkReply *reply = nam()->sendCustomRequest(request, "DELETE", buffer);
    buffer->setParent(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (reply->error() != QNetworkReply::NoError) {
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray body = reply->readAll();
            qWarning() << "SyncEngine: Failed deleteSyncAck: HTTP" << status << reply->errorString() << body;
            reply->deleteLater();
            finish(false);
            return;
        }
        reply->deleteLater();
        if (m_cancelFlag->load() != 0) {
            finish(false);
            return;
        }
        qInfo() << "SyncEngine: Clearing synced tables for full resync";
        m_db->clearSyncedData(false);
        m_assetIdsWritten.clear();
        m_exifIdsWritten.clear();
        stampIdentity();
        startStream();
    });
}

void SyncWorker::stampIdentity()
{
    m_db->setMetaValue(QStringLiteral("catalog_server"), m_serverUrl);
    m_db->setMetaValue(QStringLiteral("catalog_session"), m_session);
    if (!m_userId.isEmpty()) {
        m_db->setMetaValue(QStringLiteral("catalog_user"), m_userId);
        m_db->setMetaValue(QStringLiteral("current_user_id"), m_userId);
    }
}

void SyncWorker::startStream()
{
    if (m_reply || m_finishing) {
        return;
    }
    if (m_cancelFlag->load() != 0) {
        finish(false);
        return;
    }

    QUrl url(m_serverUrl + QStringLiteral("/api/sync/stream"));
    QNetworkRequest request = authenticatedRequest(url);
    request.setRawHeader("Accept", "application/jsonlines+json");

    QJsonObject body;
    QJsonArray types;
    for (const QString &t : requestTypes()) {
        types.append(t);
    }
    body[QStringLiteral("types")] = types;

    m_buffer.clear();
    m_streamEnded = false;
    m_completed = false;

    m_reply = nam()->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    m_reply->setReadBufferSize(kReadBufferSize);
    connect(m_reply, &QNetworkReply::readyRead, this, &SyncWorker::onReadyRead);
    connect(m_reply, &QNetworkReply::finished, this, &SyncWorker::onStreamFinished);

    qInfo() << "SyncEngine: Sync stream started";
}

void SyncWorker::onReadyRead()
{
    if (!m_reply) {
        return;
    }

    m_buffer += m_reply->readAll();

    int start = 0;
    int idx;
    while ((idx = m_buffer.indexOf('\n', start)) != -1) {
        parseLine(m_buffer.mid(start, idx - start));
        start = idx + 1;
    }
    if (start > 0) {
        m_buffer.remove(0, start);
    }
}

void SyncWorker::parseLine(const QByteArray &line)
{
    if (line.trimmed().isEmpty()) {
        return;
    }

    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(line, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning() << "SyncEngine: Failed to parse sync line:" << error.errorString();
        return;
    }

    const QJsonObject event = doc.object();
    const QString type = event.value(QStringLiteral("type")).toString();
    if (type.isEmpty()) {
        qWarning().noquote() << "SyncEngine: Line without type:" << line.left(1500);
        return;
    }
    const QString ack = event.value(QStringLiteral("ack")).toString();
    const QJsonValue data = event.value(QStringLiteral("data"));

    if (type == QLatin1String("SyncResetV1")) {
        flushGroup();
        qInfo() << "SyncEngine: SyncResetV1 - wiping synced tables";
        m_db->clearSyncedData(false);
        m_assetIdsWritten.clear();
        m_exifIdsWritten.clear();
        stampIdentity();
        m_resetRequested = true;
        queueAck(ack);
        m_pendingMask |= AssetDatabase::AllTables;
        return;
    }
    if (type == QLatin1String("SyncAckV1")) {
        queueAck(ack);
        return;
    }
    if (type == QLatin1String("SyncCompleteV1")) {
        flushGroup();
        m_completed = true;
        queueAck(ack);
        return;
    }

    QList<QJsonObject> records;
    if (data.isArray()) {
        const QJsonArray arr = data.toArray();
        records.reserve(arr.size());
        for (const QJsonValue &v : arr) {
            if (v.isObject()) {
                records.append(v.toObject());
            }
        }
    } else if (data.isObject()) {
        records.append(data.toObject());
    }

    if (records.isEmpty()) {
        if (!ack.isEmpty()) {
            flushGroup();
            queueAck(ack);
        }
        return;
    }

    if (type != m_groupType) {
        flushGroup();
        m_groupType = type;
    }
    m_group += records;
    m_groupLastAck = ack;
    m_eventsThisSync += records.size();
    if (m_group.size() >= kSyncEventBatchSize) {
        flushGroup();
    }
}

void SyncWorker::flushGroup()
{
    if (m_group.isEmpty()) {
        return;
    }

    const QString type = m_groupType;
    const QList<QJsonObject> records = m_group;
    const QString ack = m_groupLastAck;
    m_group.clear();
    m_groupType.clear();
    m_groupLastAck.clear();

    handleBatch(type, records);
    if (!ack.isEmpty()) {
        queueAck(ack);
    }
    emitProgress(maskForType(type));
}

int SyncWorker::maskForType(const QString &type) const
{
    if (type == QLatin1String("AssetV2")
        || type == QLatin1String("PartnerAssetV2")
        || type == QLatin1String("PartnerAssetBackfillV2")
        || type == QLatin1String("AssetDeleteV1")
        || type == QLatin1String("PartnerAssetDeleteV1")) {
        return AssetDatabase::Assets;
    }
    if (type == QLatin1String("AssetExifV1")
        || type == QLatin1String("PartnerAssetExifV1")
        || type == QLatin1String("PartnerAssetExifBackfillV1")
        || type == QLatin1String("AlbumAssetExifCreateV1")
        || type == QLatin1String("AlbumAssetExifUpdateV1")
        || type == QLatin1String("AlbumAssetExifBackfillV1")) {
        return AssetDatabase::Exif;
    }
    if (type == QLatin1String("AlbumAssetCreateV2")
        || type == QLatin1String("AlbumAssetUpdateV2")
        || type == QLatin1String("AlbumAssetBackfillV2")) {
        return AssetDatabase::Assets | AssetDatabase::AlbumAssets;
    }
    if (type == QLatin1String("AlbumV2")
        || type == QLatin1String("AlbumDeleteV1")
        || type == QLatin1String("AlbumUserV1")
        || type == QLatin1String("AlbumUserBackfillV1")
        || type == QLatin1String("AlbumUserDeleteV1")
        || type == QLatin1String("AlbumToAssetV1")
        || type == QLatin1String("AlbumToAssetBackfillV1")
        || type == QLatin1String("AlbumToAssetDeleteV1")) {
        return AssetDatabase::Albums;
    }
    if (type == QLatin1String("StackV1")
        || type == QLatin1String("StackDeleteV1")
        || type == QLatin1String("PartnerStackV1")
        || type == QLatin1String("PartnerStackBackfillV1")
        || type == QLatin1String("PartnerStackDeleteV1")) {
        return AssetDatabase::Stacks;
    }
    if (type == QLatin1String("PartnerV1")
        || type == QLatin1String("PartnerDeleteV1")) {
        return AssetDatabase::Partners;
    }
    if (type.startsWith(QLatin1String("User"))
        || type.startsWith(QLatin1String("AuthUser"))) {
        return AssetDatabase::Users;
    }
    if (type.startsWith(QLatin1String("Person"))
        || type.startsWith(QLatin1String("AssetFace"))) {
        return AssetDatabase::People;
    }
    if (type.startsWith(QLatin1String("Memory"))) {
        return AssetDatabase::Memories;
    }
    return AssetDatabase::Other;
}

void SyncWorker::emitProgress(int mask)
{
    m_pendingMask |= mask;

    const bool immediate = (mask & AssetDatabase::Assets) && !m_emittedAssets;
    if (!immediate) {
        if (!m_progressTimerValid) {
            m_progressTimer.start();
            m_progressTimerValid = true;
        }
        const qint64 interval = (m_fullReset || m_resetRestarted) ? kBulkProgressIntervalMs : kProgressIntervalMs;
        if (m_progressTimer.elapsed() < interval) {
            return;
        }
    }
    if (mask & AssetDatabase::Assets) {
        m_emittedAssets = true;
    }
    emit catalogChanged(m_pendingMask);
    m_pendingMask = 0;
    m_progressTimer.restart();
    m_progressTimerValid = true;
}

void SyncWorker::queueAck(const QString &ack)
{
    if (ack.isEmpty()) {
        return;
    }
    const int sep = ack.indexOf(QLatin1Char('|'));
    m_pendingAcks[sep < 0 ? ack : ack.left(sep)] = ack;
    sendPendingAcks();
}

void SyncWorker::sendPendingAcks()
{
    if (m_ackReply || m_pendingAcks.isEmpty() || m_cancelFlag->load() != 0 || m_finishing) {
        return;
    }

    QUrl url(m_serverUrl + QStringLiteral("/api/sync/ack"));
    QNetworkRequest request = authenticatedRequest(url);
    QJsonObject body;
    QJsonArray acks;
    const QList<QString> pending = m_pendingAcks.values();
    for (const QString &a : pending) {
        acks.append(a);
    }
    m_pendingAcks.clear();
    body[QStringLiteral("acks")] = acks;

    m_ackReply = nam()->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(m_ackReply, &QNetworkReply::finished, this, [this]() {
        if (!m_ackReply) {
            return;
        }
        QNetworkReply *reply = m_ackReply;
        m_ackReply = nullptr;
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "SyncEngine: Sync ack failed:" << reply->errorString() << "(events will be redelivered on next stream)";
        }
        reply->deleteLater();
        sendPendingAcks();
        maybeFinish();
    });
}

void SyncWorker::onStreamFinished()
{
    if (!m_reply) {
        return;
    }

    QNetworkReply *reply = m_reply;
    const QNetworkReply::NetworkError error = reply->error();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    reply->deleteLater();
    m_reply = nullptr;

    if (!m_buffer.trimmed().isEmpty()) {
        const QByteArray tail = m_buffer;
        m_buffer.clear();
        parseLine(tail);
    } else {
        m_buffer.clear();
    }
    flushGroup();

    if (m_cancelFlag->load() != 0) {
        qInfo() << "SyncEngine: Sync cancelled";
        finish(false);
        return;
    }

    if (error != QNetworkReply::NoError) {
        const bool clientError = status >= 400 && status < 500;
        if (clientError) {
            qWarning() << "SyncEngine: Sync stream failed with HTTP" << status << "-" << error;
            finish(false);
            return;
        }
        qWarning() << "SyncEngine: Sync stream error:" << error << "- will retry";
        scheduleRetry();
        return;
    }

    if (m_resetRequested && !m_resetRestarted) {
        m_resetRestarted = true;
        m_resetRequested = false;
        qInfo() << "SyncEngine: Restarting stream after server-requested reset";
        startStream();
        return;
    }

    if (!m_completed) {
        if (m_eventsThisSync > 0) {
            qInfo() << "SyncEngine: Stream ended without SyncCompleteV1 but" << m_eventsThisSync << "events were processed - treating as complete";
        } else {
            qWarning() << "SyncEngine: Empty stream without SyncCompleteV1 - will retry";
            scheduleRetry();
            return;
        }
    }

    m_streamEnded = true;
    qInfo() << "SyncEngine: Sync stream completed," << m_eventsThisSync << "events";
    maybeFinish();
}

void SyncWorker::maybeFinish()
{
    if (!m_streamEnded || m_ackReply || !m_pendingAcks.isEmpty() || m_finishing) {
        return;
    }
    if (m_db->metaValue(QStringLiteral("catalog_user")).isEmpty() && !m_userId.isEmpty()) {
        m_db->setMetaValue(QStringLiteral("catalog_user"), m_userId);
    }
    m_db->setMetaValue(QStringLiteral("last_sync_at"), nowIso());
    finish(true);
}

void SyncWorker::scheduleRetry()
{
    m_retryCount++;
    if (m_retryCount > kMaxRetries) {
        qWarning() << "SyncEngine: Giving up after" << kMaxRetries << "retries";
        finish(false);
        return;
    }
    static const int delays[] = {
        1000, 2000, 5000, 15000
    };
    const int delay = m_retryCount <= 4 ? delays[m_retryCount - 1] : 60000;
    qInfo() << "SyncEngine: Retrying sync in" << delay << "ms (attempt" << m_retryCount << ")";
    m_retryTimer->start(delay);
}

void SyncWorker::cancel()
{
    if (m_retryTimer) {
        m_retryTimer->stop();
    }
    if (m_ackReply) {
        m_ackReply->abort();
    }
    if (m_reply) {
        m_reply->abort();
    } else {
        finish(false);
    }
}

void SyncWorker::finish(bool ok)
{
    if (m_finishing) {
        return;
    }
    m_finishing = true;
    if (m_retryTimer) {
        m_retryTimer->stop();
    }
    if (m_pendingMask != 0) {
        emit catalogChanged(m_pendingMask);
        m_pendingMask = 0;
    }
    emit finished(ok);
}

void SyncWorker::handleBatch(const QString &type, const QList<QJsonObject> &records)
{
    if (type == QLatin1String("AssetV2")
        || type == QLatin1String("PartnerAssetV2")
        || type == QLatin1String("PartnerAssetBackfillV2")
        || type == QLatin1String("AlbumAssetUpdateV2")) {
        upsertRemoteAssets(records, false);
    } else if (type == QLatin1String("AlbumAssetCreateV2")
        || type == QLatin1String("AlbumAssetBackfillV2")) {
        upsertRemoteAssets(records, true);
    } else if (type == QLatin1String("AssetDeleteV1")
        || type == QLatin1String("PartnerAssetDeleteV1")) {
        deleteRemoteAssets(records);
    } else if (type == QLatin1String("AssetExifV1")
        || type == QLatin1String("PartnerAssetExifV1")
        || type == QLatin1String("PartnerAssetExifBackfillV1")
        || type == QLatin1String("AlbumAssetExifUpdateV1")) {
        upsertAssetExifs(records, false);
    } else if (type == QLatin1String("AlbumAssetExifCreateV1")
        || type == QLatin1String("AlbumAssetExifBackfillV1")) {
        upsertAssetExifs(records, true);
    } else if (type == QLatin1String("StackV1")
        || type == QLatin1String("PartnerStackV1")
        || type == QLatin1String("PartnerStackBackfillV1")) {
        upsertStacks(records);
    } else if (type == QLatin1String("StackDeleteV1")
        || type == QLatin1String("PartnerStackDeleteV1")) {
        deleteStacks(records);
    } else if (type == QLatin1String("UserV1")) {
        upsertUsers(records);
    } else if (type == QLatin1String("UserDeleteV1")) {
        deleteUsers(records);
    } else if (type == QLatin1String("AuthUserV1")
        || type == QLatin1String("AuthUserV2")) {
        upsertAuthUsers(records);
    } else if (type == QLatin1String("PartnerV1")) {
        upsertPartners(records);
    } else if (type == QLatin1String("PartnerDeleteV1")) {
        deletePartners(records);
    } else if (type == QLatin1String("AlbumV2")) {
        upsertAlbums(records);
    } else if (type == QLatin1String("AlbumDeleteV1")) {
        deleteAlbums(records);
    } else if (type == QLatin1String("AlbumUserV1")
        || type == QLatin1String("AlbumUserBackfillV1")) {
        upsertAlbumUsers(records);
    } else if (type == QLatin1String("AlbumUserDeleteV1")) {
        deleteAlbumUsers(records);
    } else if (type == QLatin1String("AlbumToAssetV1")
        || type == QLatin1String("AlbumToAssetBackfillV1")) {
        insertAlbumToAssets(records);
    } else if (type == QLatin1String("AlbumToAssetDeleteV1")) {
        deleteAlbumToAssets(records);
    } else if (type == QLatin1String("MemoryV1")
        || type == QLatin1String("MemoryV2")) {
        upsertMemories(records);
    } else if (type == QLatin1String("MemoryDeleteV1")) {
        deleteMemories(records);
    } else if (type == QLatin1String("MemoryToAssetV1")
        || type == QLatin1String("MemoryToAssetV2")) {
        insertMemoryAssets(records);
    } else if (type == QLatin1String("MemoryToAssetDeleteV1")) {
        deleteMemoryAssets(records);
    } else if (type == QLatin1String("PersonV1")) {
        upsertPersons(records);
    } else if (type == QLatin1String("PersonDeleteV1")) {
        deletePersons(records);
    } else if (type == QLatin1String("AssetFaceV2")
        || type == QLatin1String("AssetFaceV3")) {
        upsertAssetFaces(records);
    } else if (type == QLatin1String("AssetFaceDeleteV1")) {
        deleteAssetFaces(records);
    } else if (type == QLatin1String("AssetEditV1")) {
        upsertAssetEdits(records);
    } else if (type == QLatin1String("AssetEditDeleteV1")) {
        deleteAssetEdits(records);
    } else if (type == QLatin1String("AssetMetadataV1")) {
        upsertAssetMetadata(records);
    } else if (type == QLatin1String("AssetMetadataDeleteV1")) {
        deleteAssetMetadata(records);
    } else if (type == QLatin1String("AssetOcrV1")) {
        upsertAssetOcr(records);
    } else if (type == QLatin1String("AssetOcrDeleteV1")) {
        deleteAssetOcr(records);
    } else if (type == QLatin1String("UserMetadataV1")) {
        upsertUserMetadata(records);
    } else if (type == QLatin1String("UserMetadataDeleteV1")) {
        deleteUserMetadata(records);
    } else if (!m_loggedUnknownTypes.contains(type)) {
        m_loggedUnknownTypes.insert(type);
        qWarning() << "SyncEngine: Unhandled sync entity type" << type;
    }
}

void SyncWorker::upsertRemoteAssets(const QList<QJsonObject> &records, bool skipSeen)
{
    QSqlDatabase db = m_db->db();
    db.transaction();

    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "INSERT OR REPLACE INTO remote_asset ("
        " id, owner_id, name, type, checksum, visibility, is_favorite, is_edited,"
        " width, height, duration_ms, created_at, updated_at, uploaded_at,"
        " local_date_time, deleted_at, thumb_hash, stack_id,"
        " live_photo_video_id, library_id"
        ") VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"));

    for (const QJsonObject &a : records) {
        const QString id = a.value(QStringLiteral("id")).toString();
        if (skipSeen && m_assetIdsWritten.contains(id)) {
            continue;
        }
        q.addBindValue(id);
        q.addBindValue(a.value(QStringLiteral("ownerId")).toString());
        q.addBindValue(textIfMissing(a, "originalFileName"));
        q.addBindValue(textIfMissing(a, "type", QStringLiteral("IMAGE")));
        q.addBindValue(a.value(QStringLiteral("checksum")).toString());
        q.addBindValue(textIfMissing(a, "visibility", QStringLiteral("timeline")));
        q.addBindValue(a.value(QStringLiteral("isFavorite")).toBool() ? 1 : 0);
        q.addBindValue(a.value(QStringLiteral("isEdited")).toBool() ? 1 : 0);
        q.addBindValue(nullIfMissing(a, "width"));
        q.addBindValue(nullIfMissing(a, "height"));
        q.addBindValue(nullIfMissing(a, "duration"));
        const QVariant created = nullIfMissing(a, "fileCreatedAt");
        q.addBindValue(created.isNull() ? nowIso() : created);
        q.addBindValue(nullIfMissing(a, "fileModifiedAt"));
        q.addBindValue(nullIfMissing(a, "createdAt"));
        q.addBindValue(nullIfMissing(a, "localDateTime"));
        q.addBindValue(nullIfMissing(a, "deletedAt"));
        q.addBindValue(nullIfMissing(a, "thumbhash"));
        q.addBindValue(nullIfMissing(a, "stackId"));
        q.addBindValue(nullIfMissing(a, "livePhotoVideoId"));
        q.addBindValue(nullIfMissing(a, "libraryId"));
        if (!q.exec()) {
            qWarning() << "SyncEngine: remote_asset upsert failed:" << q.lastError().text();
        } else {
            m_assetIdsWritten.insert(id);
        }
        q.finish();
    }

    if (!db.commit()) {
        qWarning() << "SyncEngine: Failed remote_asset batch commit:" << db.lastError().text();
        db.rollback();
    }
}

void SyncWorker::deleteRemoteAssets(const QList<QJsonObject> &records)
{
    QSqlDatabase db = m_db->db();
    db.transaction();

    QSqlQuery q(db);
    QStringList deletedIds;
    for (const QJsonObject &r : records) {
        const QString id = r.value(QStringLiteral("assetId")).toString();
        m_assetIdsWritten.remove(id);
        m_exifIdsWritten.remove(id);
        q.prepare(QStringLiteral("DELETE FROM remote_asset WHERE id = ?"));
        q.addBindValue(id);
        q.exec();
        q.finish();
        q.prepare(QStringLiteral("DELETE FROM remote_asset_exif WHERE asset_id = ?"));
        q.addBindValue(id);
        q.exec();
        q.finish();
        if (!id.isEmpty()) {
            deletedIds.append(id);
        }
    }

    if (!db.commit()) {
        qWarning() << "SyncEngine: Failed asset delete commit:" << db.lastError().text();
        db.rollback();
        return;
    }
    if (!deletedIds.isEmpty()) {
        emit remoteAssetsDeleted(deletedIds);
    }
}

void SyncWorker::upsertAssetExifs(const QList<QJsonObject> &records, bool skipSeen)
{
    QSqlDatabase db = m_db->db();
    db.transaction();

    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "INSERT OR REPLACE INTO remote_asset_exif ("
        " asset_id, description, exif_image_width, exif_image_height, file_size,"
        " orientation, date_time_original, modify_date, time_zone,"
        " latitude, longitude, projection_type, city, state, country,"
        " make, model, lens_model, f_number, focal_length, iso, exposure_time,"
        " rating, fps, profile_description"
        ") VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"));

    for (const QJsonObject &e : records) {
        const QString assetId = e.value(QStringLiteral("assetId")).toString();
        if (skipSeen && m_exifIdsWritten.contains(assetId)) {
            continue;
        }
        q.addBindValue(assetId);
        q.addBindValue(nullIfMissing(e, "description"));
        q.addBindValue(nullIfMissing(e, "exifImageWidth"));
        q.addBindValue(nullIfMissing(e, "exifImageHeight"));
        q.addBindValue(nullIfMissing(e, "fileSizeInByte"));
        q.addBindValue(nullIfMissing(e, "orientation"));
        q.addBindValue(nullIfMissing(e, "dateTimeOriginal"));
        q.addBindValue(nullIfMissing(e, "modifyDate"));
        q.addBindValue(nullIfMissing(e, "timeZone"));
        q.addBindValue(nullIfMissing(e, "latitude"));
        q.addBindValue(nullIfMissing(e, "longitude"));
        q.addBindValue(nullIfMissing(e, "projectionType"));
        q.addBindValue(nullIfMissing(e, "city"));
        q.addBindValue(nullIfMissing(e, "state"));
        q.addBindValue(nullIfMissing(e, "country"));
        q.addBindValue(nullIfMissing(e, "make"));
        q.addBindValue(nullIfMissing(e, "model"));
        q.addBindValue(nullIfMissing(e, "lensModel"));
        q.addBindValue(nullIfMissing(e, "fNumber"));
        q.addBindValue(nullIfMissing(e, "focalLength"));
        q.addBindValue(nullIfMissing(e, "iso"));
        q.addBindValue(nullIfMissing(e, "exposureTime"));
        q.addBindValue(nullIfMissing(e, "rating"));
        q.addBindValue(nullIfMissing(e, "fps"));
        q.addBindValue(nullIfMissing(e, "profileDescription"));
        if (!q.exec()) {
            qWarning() << "SyncEngine: Failed exif upsert:" << q.lastError().text();
        } else {
            m_exifIdsWritten.insert(assetId);
        }
        q.finish();
    }

    if (!db.commit()) {
        qWarning() << "SyncEngine: Failed exif batch commit:" << db.lastError().text();
        db.rollback();
    }
}

void SyncWorker::upsertStacks(const QList<QJsonObject> &records)
{
    QSqlDatabase db = m_db->db();
    db.transaction();

    QSqlQuery q(db);
    q.prepare(QStringLiteral("INSERT OR REPLACE INTO stack (id, owner_id, primary_asset_id, created_at, updated_at) VALUES (?,?,?,?,?)"));

    for (const QJsonObject &s : records) {
        q.addBindValue(s.value(QStringLiteral("id")).toString());
        q.addBindValue(s.value(QStringLiteral("ownerId")).toString());
        q.addBindValue(s.value(QStringLiteral("primaryAssetId")).toString());
        q.addBindValue(nullIfMissing(s, "createdAt"));
        q.addBindValue(nullIfMissing(s, "updatedAt"));
        if (!q.exec()) {
            qWarning() << "SyncEngine: Failed stack upsert:" << q.lastError().text();
        }
        q.finish();
    }

    if (!db.commit()) {
        qWarning() << "SyncEngine: Failed stack batch commit:" << db.lastError().text();
        db.rollback();
    }
}

void SyncWorker::deleteStacks(const QList<QJsonObject> &records)
{
    QSqlDatabase db = m_db->db();
    db.transaction();

    QSqlQuery q(db);
    for (const QJsonObject &r : records) {
        const QString stackId = r.value(QStringLiteral("stackId")).toString();
        q.prepare(QStringLiteral("UPDATE remote_asset SET stack_id = NULL WHERE stack_id = ?"));
        q.addBindValue(stackId);
        q.exec();
        q.finish();
        q.prepare(QStringLiteral("DELETE FROM stack WHERE id = ?"));
        q.addBindValue(stackId);
        q.exec();
        q.finish();
    }

    if (!db.commit()) {
        qWarning() << "SyncEngine: Failed stack delete commit:" << db.lastError().text();
        db.rollback();
    }
}

void SyncWorker::upsertUsers(const QList<QJsonObject> &records)
{
    QSqlDatabase db = m_db->db();
    db.transaction();

    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "INSERT OR REPLACE INTO sync_user (id, name, email, avatar_color,"
        " has_profile_image, profile_changed_at, deleted_at)"
        " VALUES (?,?,?,?,?,?,?)"));

    for (const QJsonObject &u : records) {
        q.addBindValue(u.value(QStringLiteral("id")).toString());
        q.addBindValue(u.value(QStringLiteral("name")).toString());
        q.addBindValue(u.value(QStringLiteral("email")).toString());
        q.addBindValue(nullIfMissing(u, "avatarColor"));
        q.addBindValue(u.value(QStringLiteral("hasProfileImage")).toBool() ? 1 : 0);
        q.addBindValue(nullIfMissing(u, "profileChangedAt"));
        q.addBindValue(nullIfMissing(u, "deletedAt"));
        if (!q.exec()) {
            qWarning() << "SyncEngine: Failed user upsert:" << q.lastError().text();
        }
        q.finish();
    }

    db.commit();
}

void SyncWorker::deleteUsers(const QList<QJsonObject> &records)
{
    QSqlDatabase db = m_db->db();
    db.transaction();

    QSqlQuery q(db);
    q.prepare(QStringLiteral("DELETE FROM sync_user WHERE id = ?"));
    for (const QJsonObject &r : records) {
        q.addBindValue(r.value(QStringLiteral("userId")).toString());
        q.exec();
        q.finish();
    }

    db.commit();
}

void SyncWorker::upsertAuthUsers(const QList<QJsonObject> &records)
{
    QSqlDatabase db = m_db->db();
    db.transaction();

    QSqlQuery q(db);
    q.prepare(QStringLiteral(
        "INSERT OR REPLACE INTO auth_user (id, name, email, avatar_color,"
        " has_profile_image, profile_changed_at, is_admin, pin_code, oauth_id,"
        " storage_label, quota_size_in_bytes, quota_usage_in_bytes, deleted_at)"
        " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)"));

    for (const QJsonObject &u : records) {
        const QString id = u.value(QStringLiteral("id")).toString();
        m_db->setMetaValue(QStringLiteral("current_user_id"), id);
        q.addBindValue(id);
        q.addBindValue(u.value(QStringLiteral("name")).toString());
        q.addBindValue(u.value(QStringLiteral("email")).toString());
        q.addBindValue(nullIfMissing(u, "avatarColor"));
        q.addBindValue(u.value(QStringLiteral("hasProfileImage")).toBool() ? 1 : 0);
        q.addBindValue(nullIfMissing(u, "profileChangedAt"));
        q.addBindValue(u.value(QStringLiteral("isAdmin")).toBool() ? 1 : 0);
        q.addBindValue(nullIfMissing(u, "pinCode"));
        q.addBindValue(nullIfMissing(u, "oauthId"));
        q.addBindValue(nullIfMissing(u, "storageLabel"));
        q.addBindValue(nullIfMissing(u, "quotaSizeInBytes"));
        q.addBindValue(nullIfMissing(u, "quotaUsageInBytes"));
        q.addBindValue(nullIfMissing(u, "deletedAt"));
        if (!q.exec()) {
            qWarning() << "SyncEngine: Failed auth_user upsert:" << q.lastError().text();
        }
        q.finish();
    }

    db.commit();
}

void SyncWorker::batchExec(const QString &sql, const QList<QJsonObject> &records, const std::function<void(QSqlQuery &, const QJsonObject &)> &bind)
{
    QSqlDatabase db = m_db->db();
    db.transaction();
    QSqlQuery q(db);
    if (!q.prepare(sql)) {
        qWarning() << "SyncEngine: Failed batch prepare:" << q.lastError().text() << "SQL:" << sql;
        db.rollback();
        return;
    }
    int failures = 0;
    for (const QJsonObject &r : records) {
        bind(q, r);
        if (!q.exec() && failures++ == 0) {
            qWarning() << "SyncEngine: Failed batch exec:" << q.lastError().text() << "SQL:" << sql;
        }
        q.finish();
    }
    if (failures > 1) {
        qWarning() << "SyncEngine:" << failures << "of" << records.size() << "rows failed in batch";
    }
    if (!db.commit()) {
        qWarning() << "SyncEngine: Failed batch commit:" << db.lastError().text();
        db.rollback();
    }
}

void SyncWorker::upsertPartners(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR REPLACE INTO partner (shared_by_id, shared_with_id, in_timeline) VALUES (?,?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("sharedById")).toString());
        q.addBindValue(r.value(QStringLiteral("sharedWithId")).toString());
        q.addBindValue(r.value(QStringLiteral("inTimeline")).toBool() ? 1 : 0);
    });
}

void SyncWorker::deletePartners(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM partner WHERE shared_by_id = ? AND shared_with_id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("sharedById")).toString());
        q.addBindValue(r.value(QStringLiteral("sharedWithId")).toString());
    });
}

void SyncWorker::upsertAlbums(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR REPLACE INTO album (id, name, description, created_at, updated_at, thumbnail_asset_id, is_activity_enabled, asset_order) VALUES (?,?,?,?,?,?,?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("id")).toString());
        q.addBindValue(r.value(QStringLiteral("name")).toString());
        q.addBindValue(r.value(QStringLiteral("description")).toString());
        q.addBindValue(nullIfMissing(r, "createdAt"));
        q.addBindValue(nullIfMissing(r, "updatedAt"));
        q.addBindValue(nullIfMissing(r, "thumbnailAssetId"));
        q.addBindValue(r.value(QStringLiteral("isActivityEnabled")).toBool() ? 1 : 0);
        q.addBindValue(nullIfMissing(r, "order"));
    });
}

void SyncWorker::deleteAlbums(const QList<QJsonObject> &records)
{
    auto bindAlbumId = [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("albumId")).toString());
    };
    batchExec(QStringLiteral("DELETE FROM album_to_asset WHERE album_id = ?"), records, bindAlbumId);
    batchExec(QStringLiteral("DELETE FROM album_user WHERE album_id = ?"), records, bindAlbumId);
    batchExec(QStringLiteral("DELETE FROM album WHERE id = ?"), records, bindAlbumId);
}

void SyncWorker::upsertAlbumUsers(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR REPLACE INTO album_user (album_id, user_id, role) VALUES (?,?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("albumId")).toString());
        q.addBindValue(r.value(QStringLiteral("userId")).toString());
        q.addBindValue(r.value(QStringLiteral("role")).toString());
    });
}

void SyncWorker::deleteAlbumUsers(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM album_user WHERE album_id = ? AND user_id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("albumId")).toString());
        q.addBindValue(r.value(QStringLiteral("userId")).toString());
    });
}

void SyncWorker::insertAlbumToAssets(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR IGNORE INTO album_to_asset (album_id, asset_id) VALUES (?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("albumId")).toString());
        q.addBindValue(r.value(QStringLiteral("assetId")).toString());
    });
}

void SyncWorker::deleteAlbumToAssets(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM album_to_asset WHERE album_id = ? AND asset_id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("albumId")).toString());
        q.addBindValue(r.value(QStringLiteral("assetId")).toString());
    });
}

void SyncWorker::upsertMemories(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR REPLACE INTO memory (id, created_at, updated_at, deleted_at, owner_id, type, data, is_saved, memory_at, seen_at, show_at, hide_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("id")).toString());
        q.addBindValue(nullIfMissing(r, "createdAt"));
        q.addBindValue(nullIfMissing(r, "updatedAt"));
        q.addBindValue(nullIfMissing(r, "deletedAt"));
        q.addBindValue(r.value(QStringLiteral("ownerId")).toString());
        q.addBindValue(r.value(QStringLiteral("type")).toString());
        const QJsonValue data = r.value(QStringLiteral("data"));
        q.addBindValue(data.isObject() ? QString::fromUtf8(QJsonDocument(data.toObject()).toJson(QJsonDocument::Compact)) : QVariant());
        q.addBindValue(r.value(QStringLiteral("isSaved")).toBool() ? 1 : 0);
        q.addBindValue(nullIfMissing(r, "memoryAt"));
        q.addBindValue(nullIfMissing(r, "seenAt"));
        q.addBindValue(nullIfMissing(r, "showAt"));
        q.addBindValue(nullIfMissing(r, "hideAt"));
    });
}

void SyncWorker::deleteMemories(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM memory WHERE id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("memoryId")).toString());
    });
    batchExec(QStringLiteral("DELETE FROM memory_to_asset WHERE memory_id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("memoryId")).toString());
    });
}

void SyncWorker::insertMemoryAssets(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR IGNORE INTO memory_to_asset (memory_id, asset_id) VALUES (?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("memoryId")).toString());
        q.addBindValue(r.value(QStringLiteral("assetId")).toString());
    });
}

void SyncWorker::deleteMemoryAssets(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM memory_to_asset WHERE memory_id = ? AND asset_id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("memoryId")).toString());
        q.addBindValue(r.value(QStringLiteral("assetId")).toString());
    });
}

void SyncWorker::upsertPersons(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR REPLACE INTO person (id, created_at, updated_at, owner_id, name, birth_date, is_hidden, is_favorite, color, face_asset_id) VALUES (?,?,?,?,?,?,?,?,?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("id")).toString());
        q.addBindValue(nullIfMissing(r, "createdAt"));
        q.addBindValue(nullIfMissing(r, "updatedAt"));
        q.addBindValue(r.value(QStringLiteral("ownerId")).toString());
        q.addBindValue(r.value(QStringLiteral("name")).toString());
        q.addBindValue(nullIfMissing(r, "birthDate"));
        q.addBindValue(r.value(QStringLiteral("isHidden")).toBool() ? 1 : 0);
        q.addBindValue(r.value(QStringLiteral("isFavorite")).toBool() ? 1 : 0);
        q.addBindValue(nullIfMissing(r, "color"));
        q.addBindValue(nullIfMissing(r, "faceAssetId"));
    });
}

void SyncWorker::deletePersons(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM person WHERE id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("personId")).toString());
    });
    batchExec(QStringLiteral("UPDATE asset_face SET person_id = NULL WHERE person_id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("personId")).toString());
    });
}

void SyncWorker::upsertAssetFaces(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR REPLACE INTO asset_face (id, asset_id, person_id, image_width, image_height, bounding_x1, bounding_y1, bounding_x2, bounding_y2, source_type, deleted_at, is_visible) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("id")).toString());
        q.addBindValue(r.value(QStringLiteral("assetId")).toString());
        q.addBindValue(r.value(QStringLiteral("personId")).toString());
        q.addBindValue(nullIfMissing(r, "imageWidth"));
        q.addBindValue(nullIfMissing(r, "imageHeight"));
        q.addBindValue(nullIfMissing(r, "boundingBoxX1"));
        q.addBindValue(nullIfMissing(r, "boundingBoxY1"));
        q.addBindValue(nullIfMissing(r, "boundingBoxX2"));
        q.addBindValue(nullIfMissing(r, "boundingBoxY2"));
        q.addBindValue(nullIfMissing(r, "sourceType"));
        q.addBindValue(nullIfMissing(r, "deletedAt"));
        q.addBindValue(r.value(QStringLiteral("isVisible")).toBool(true) ? 1 : 0);
    });
}

void SyncWorker::deleteAssetFaces(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM asset_face WHERE id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("assetFaceId")).toString());
    });
}

void SyncWorker::upsertAssetEdits(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR REPLACE INTO asset_edit (id, asset_id, action, parameters, sequence) VALUES (?,?,?,?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("id")).toString());
        q.addBindValue(r.value(QStringLiteral("assetId")).toString());
        q.addBindValue(r.value(QStringLiteral("action")).toString());
        const QJsonValue params = r.value(QStringLiteral("parameters"));
        q.addBindValue(params.isObject() ? QString::fromUtf8(QJsonDocument(params.toObject()).toJson(QJsonDocument::Compact)) : QVariant());
        q.addBindValue(intIfMissing(r, "sequence"));
    });
}

void SyncWorker::deleteAssetEdits(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM asset_edit WHERE id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("editId")).toString());
    });
}

void SyncWorker::upsertAssetMetadata(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR REPLACE INTO asset_metadata (asset_id, key, value) VALUES (?,?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("assetId")).toString());
        q.addBindValue(r.value(QStringLiteral("key")).toString());
        const QJsonValue v = r.value(QStringLiteral("value"));
        q.addBindValue(v.isObject() ? QString::fromUtf8(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact)) : v.toVariant());
    });
}

void SyncWorker::deleteAssetMetadata(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM asset_metadata WHERE asset_id = ? AND key = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("assetId")).toString());
        q.addBindValue(r.value(QStringLiteral("key")).toString());
    });
}

void SyncWorker::upsertAssetOcr(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR REPLACE INTO asset_ocr (id, asset_id, text, x1, y1, x2, y2, x3, y3, x4, y4, box_score, text_score, is_visible) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("id")).toString());
        q.addBindValue(r.value(QStringLiteral("assetId")).toString());
        q.addBindValue(r.value(QStringLiteral("text")).toString());
        q.addBindValue(nullIfMissing(r, "x1"));
        q.addBindValue(nullIfMissing(r, "y1"));
        q.addBindValue(nullIfMissing(r, "x2"));
        q.addBindValue(nullIfMissing(r, "y2"));
        q.addBindValue(nullIfMissing(r, "x3"));
        q.addBindValue(nullIfMissing(r, "y3"));
        q.addBindValue(nullIfMissing(r, "x4"));
        q.addBindValue(nullIfMissing(r, "y4"));
        q.addBindValue(nullIfMissing(r, "boxScore"));
        q.addBindValue(nullIfMissing(r, "textScore"));
        q.addBindValue(r.value(QStringLiteral("isVisible")).toBool(true) ? 1 : 0);
    });
}

void SyncWorker::deleteAssetOcr(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM asset_ocr WHERE id = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("id")).toString());
    });
}

void SyncWorker::upsertUserMetadata(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("INSERT OR REPLACE INTO user_metadata (user_id, key, value) VALUES (?,?,?)"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("userId")).toString());
        q.addBindValue(r.value(QStringLiteral("key")).toString());
        const QJsonValue v = r.value(QStringLiteral("value"));
        q.addBindValue(v.isObject() ? QString::fromUtf8(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact)) : v.toVariant());
    });
}

void SyncWorker::deleteUserMetadata(const QList<QJsonObject> &records)
{
    batchExec(QStringLiteral("DELETE FROM user_metadata WHERE user_id = ? AND key = ?"), records, [](QSqlQuery &q, const QJsonObject &r) {
        q.addBindValue(r.value(QStringLiteral("userId")).toString());
        q.addBindValue(r.value(QStringLiteral("key")).toString());
    });
}
