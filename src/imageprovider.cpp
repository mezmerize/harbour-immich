#include "imageprovider.h"
#include "authmanager.h"
#include "clientcertmanager.h"
#include "settingsmanager.h"
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QDebug>
#include <QThread>
#include <QThreadStorage>
#include <QStandardPaths>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QDateTime>
#include <QFileInfo>
#include <QCryptographicHash>
#include <algorithm>

static QNetworkAccessManager *sharedNetworkManager()
{
    static QThreadStorage<QNetworkAccessManager *> storage;
    if (!storage.hasLocalData()) {
        storage.setLocalData(new TlsNetworkAccessManager);
    }
    return storage.localData();
}

namespace {
const qint64 DiskCacheMaxBytes = 300LL * 1024 * 1024;
const int DiskCacheMaxAgeDays = 30;

QString diskCacheDir()
{
    static QString dir;
    if (dir.isEmpty()) {
        dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/immich-images");
        QDir().mkpath(dir);
    }
    return dir;
}

QString diskCachePath(const QString &url)
{
    const QByteArray key = QCryptographicHash::hash(url.toUtf8(), QCryptographicHash::Sha1).toHex();
    return diskCacheDir() + QLatin1Char('/') + QString::fromLatin1(key) + QStringLiteral(".img");
}

QAtomicInt g_diskCachePruned(0);

void pruneDiskCacheOnce()
{
    if (g_diskCachePruned.fetchAndStoreRelaxed(1))
        return;

    qint64 total = 0;
    QList<QFileInfo> files;
    const QDateTime staleBefore = QDateTime::currentDateTime().addDays(-DiskCacheMaxAgeDays);
    QDirIterator it(diskCacheDir(), QStringList() << QStringLiteral("*.img"), QDir::Files, QDirIterator::NoIteratorFlags);
    while (it.hasNext()) {
        it.next();
        QFileInfo fi = it.fileInfo();
        if (fi.lastModified() < staleBefore) {
            QFile::remove(fi.absoluteFilePath());
            continue;
        }
        total += fi.size();
        files.append(fi);
    }

    if (total <= DiskCacheMaxBytes)
        return;

    std::sort(files.begin(), files.end(), [](const QFileInfo &a, const QFileInfo &b) {
        return a.lastModified() < b.lastModified();
    });
    for (const QFileInfo &fi : files) {
        if (total <= DiskCacheMaxBytes)
            break;
        total -= fi.size();
        QFile::remove(fi.absoluteFilePath());
    }
}
}

// Static member initialization
QAtomicInt ImmichImageResponse::s_activeRequests(0);
QMutex ImmichImageResponse::s_queueMutex;
QQueue<ImmichImageResponse*> ImmichImageResponse::s_pendingQueue;
QMutex ImmichImageResponse::s_cacheMutex;
QCache<QString, QImage> ImmichImageResponse::s_imageCache(16 * 1024 * 1024); // ~16MB cost limit

ImmichImageResponse::ImmichImageResponse(const QString &url, const QString &authToken, const QSize &requestedSize)
    : m_url(url)
    , m_authToken(authToken)
    , m_networkManager(nullptr)
    , m_reply(nullptr)
    , m_requestedSize(requestedSize)
    , m_cancelled(false)
    , m_started(false)
    , m_finished(false)
    , m_networkActive(false)
{
    enqueueOrStart(this);
}

void ImmichImageResponse::enqueueOrStart(ImmichImageResponse *response)
{
    QMutexLocker locker(&s_queueMutex);
    if (s_activeRequests.load() < MAX_CONCURRENT_REQUESTS) {
        locker.unlock();
        response->startRequest();
    } else {
        s_pendingQueue.enqueue(response);
    }
}

void ImmichImageResponse::processQueue()
{
    QMutexLocker locker(&s_queueMutex);
    while (!s_pendingQueue.isEmpty() && s_activeRequests.load() < MAX_CONCURRENT_REQUESTS) {
        ImmichImageResponse *next = s_pendingQueue.dequeue();
        locker.unlock();
        if (!next->m_cancelled) {
            next->startRequest();
        } else if (!next->m_finished) {
            // Already cancelled while queued - just emit finished
            next->m_finished = true;
            emit next->finished();
        }
        locker.relock();
    }
}

void ImmichImageResponse::startRequest()
{
    if (m_started || m_cancelled)
        return;

    if (m_url.isEmpty()) {
        m_errorString = QStringLiteral("Invalid image request");
        m_started = true;
        m_finished = true;
        QMetaObject::invokeMethod(this, "finished", Qt::QueuedConnection);
        return;
    }

    // Check in-memory cache first (no network needed)
    {
        QMutexLocker locker(&s_cacheMutex);
        QImage *cached = s_imageCache.object(m_url);
        if (cached) {
            m_image = *cached;
            m_started = true;
            m_finished = true;
            // m_networkActive stays false - we didn't touch s_activeRequests
            QMetaObject::invokeMethod(this, "finished", Qt::QueuedConnection);
            return;
        }
    }

    pruneDiskCacheOnce();

    // Disk cache
    {
        const QString cachePath = diskCachePath(m_url);
        const QFileInfo fi(cachePath);
        if (fi.exists() && fi.lastModified().addDays(DiskCacheMaxAgeDays) < QDateTime::currentDateTime()) {
            // Entry is stale
            QFile::remove(cachePath);
        }
        QFile file(cachePath);
        if (file.exists() && file.open(QIODevice::ReadOnly)) {
            const QByteArray data = file.readAll();
            file.close();
            if (!data.isEmpty() && m_image.loadFromData(data)) {
                m_started = true;
                m_finished = true;
                {
                    QMutexLocker locker(&s_cacheMutex);
                    s_imageCache.insert(m_url, new QImage(m_image), m_image.byteCount());
                }
                QMetaObject::invokeMethod(this, "finished", Qt::QueuedConnection);
                return;
            }
            // Corrupt entry - drop it
            file.remove();
        }
    }

    m_started = true;
    m_networkActive = true;
    s_activeRequests.fetchAndAddAcquire(1);

    m_networkManager = sharedNetworkManager();

    QNetworkRequest request(m_url);
    request.setRawHeader("Authorization", QString("Bearer %1").arg(m_authToken).toUtf8());
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
    request.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);

    m_reply = m_networkManager->get(request);
    connect(m_reply, &QNetworkReply::finished, this, &ImmichImageResponse::onFinished);
}

void ImmichImageResponse::requestCompleted()
{
    s_activeRequests.fetchAndSubAcquire(1);
    processQueue();
}

ImmichImageResponse::~ImmichImageResponse()
{
    if (m_reply) {
        m_reply->disconnect(this);
        if (!m_reply->isFinished()) {
            m_reply->abort();
        }
        m_reply->deleteLater();
    }
    if (m_networkActive) {
        m_networkActive = false;
        requestCompleted();
    }
    if (!m_started) {
        QMutexLocker locker(&s_queueMutex);
        s_pendingQueue.removeOne(this);
    }
}

void ImmichImageResponse::cancel()
{
    m_cancelled = true;
    if (m_reply) {
        m_reply->disconnect(this);
        if (!m_reply->isFinished()) {
            m_reply->abort();
        }
    }
    if (m_networkActive) {
        m_networkActive = false;
        requestCompleted();
    } else if (!m_started) {
        QMutexLocker locker(&s_queueMutex);
        s_pendingQueue.removeOne(this);
    }
    if (!m_finished) {
        m_errorString = QStringLiteral("Cancelled");
        m_finished = true;
        emit finished();
    }
}

void ImmichImageResponse::onFinished()
{
    if (m_networkActive) {
        m_networkActive = false;
        requestCompleted();
    }

    if (m_finished) return;

    if (m_cancelled || !m_reply) {
        m_finished = true;
        emit finished();
        return;
    }

    m_reply->disconnect(this);

    if (m_reply->error() == QNetworkReply::NoError) {
        QByteArray data = m_reply->readAll();

        if (data.isEmpty()) {
            m_errorString = QStringLiteral("Empty response data");
        } else {
            const QString cachePath = diskCachePath(m_url);
            const QString tmpPath = cachePath + QStringLiteral(".") + QString::number(reinterpret_cast<quintptr>(m_reply.data()), 16) + QStringLiteral(".tmp");
            QFile tmpFile(tmpPath);
            if (tmpFile.open(QIODevice::WriteOnly)) {
                tmpFile.write(data);
                tmpFile.close();
                QFile::remove(cachePath);
                QFile::rename(tmpPath, cachePath);
            }

            // Try to load image with error handling for memory issues
            try {
                if (!m_image.loadFromData(data)) {
                    m_errorString = QStringLiteral("Failed to load image data");
                    qWarning() << "ImmichImageProvider: Failed to parse image, size:" << data.size();
                } else {
                    if (!m_image.isNull()) {
                        QSize targetSize = m_requestedSize;
                        if (!targetSize.isValid()) {
                            targetSize = QSize(1920, 1920);
                        }
                        if (m_image.width() > targetSize.width() || m_image.height() > targetSize.height()) {
                            m_image = m_image.scaled(targetSize, Qt::KeepAspectRatio, Qt::FastTransformation);
                        }

                        QMutexLocker locker(&s_cacheMutex);
                        s_imageCache.insert(m_url, new QImage(m_image), m_image.byteCount());
                    }
                }
            } catch (const std::bad_alloc &) {
                m_errorString = QStringLiteral("Out of memory loading image");
                qWarning() << "ImmichImageProvider: Out of memory loading image, size:" << data.size();
                m_image = QImage();
            }
        }
    } else {
        m_errorString = m_reply->errorString();
        if (m_reply->error() != QNetworkReply::OperationCanceledError) {
            qWarning() << "ImmichImageProvider: Network error:" << m_reply->error();
        }
    }

    // Schedule reply for deletion
    m_reply->deleteLater();

    m_finished = true;
    emit finished();
}

QQuickTextureFactory *ImmichImageResponse::textureFactory() const
{
    return QQuickTextureFactory::textureFactoryForImage(m_image);
}

QString ImmichImageResponse::errorString() const
{
    return m_errorString;
}

ImmichImageProvider::ImmichImageProvider(AuthManager *authManager, SettingsManager *settingsManager, QObject *parent)
    : QObject(parent)
    , QQuickAsyncImageProvider()
    , m_authManager(authManager)
    , m_settingsManager(settingsManager)
    , m_detailQuality(QStringLiteral("preview"))
{
    if (m_authManager) {
        m_serverUrl = m_authManager->serverUrl();
        m_accessToken = m_authManager->getAccessToken();
        connect(m_authManager, &AuthManager::serverUrlChanged, this, &ImmichImageProvider::refreshServerUrl);
        connect(m_authManager, &AuthManager::accessTokenChanged, this, &ImmichImageProvider::refreshAccessToken);
    }
    if (m_settingsManager) {
        m_detailQuality = m_settingsManager->detailQuality();
        connect(m_settingsManager, &SettingsManager::detailQualityChanged, this, &ImmichImageProvider::refreshDetailQuality);
    }
}

void ImmichImageProvider::clearImageDiskCache()
{
    QDirIterator it(diskCacheDir(), QStringList() << QStringLiteral("*.img"), QDir::Files, QDirIterator::NoIteratorFlags);
    while (it.hasNext()) {
        QFile::remove(it.next());
    }
}

void ImmichImageProvider::refreshServerUrl()
{
    QMutexLocker locker(&m_stateMutex);
    m_serverUrl = m_authManager->serverUrl();
}

void ImmichImageProvider::refreshAccessToken()
{
    QMutexLocker locker(&m_stateMutex);
    m_accessToken = m_authManager->getAccessToken();
}

void ImmichImageProvider::refreshDetailQuality()
{
    QMutexLocker locker(&m_stateMutex);
    m_detailQuality = m_settingsManager->detailQuality();
}

QQuickImageResponse *ImmichImageProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    QStringList parts = id.split('/');
    if (parts.size() < 2) {
        qWarning() << "ImmichImageProvider: Invalid id format:" << id;
        return new ImmichImageResponse(QString(), QString(), requestedSize);
    }

    QString type = parts[0];
    QString assetId = parts[1];

    QString serverUrl;
    QString accessToken;
    QString detailQuality;
    {
        QMutexLocker locker(&m_stateMutex);
        serverUrl = m_serverUrl;
        accessToken = m_accessToken;
        detailQuality = m_detailQuality;
    }

    QString url;
    if (type == "thumbnail") {
        url = serverUrl + QStringLiteral("/api/assets/") + assetId + QStringLiteral("/thumbnail?edited=true&size=thumbnail");
    } else if (type == "detail") {
        url = serverUrl + QStringLiteral("/api/assets/") + assetId + QStringLiteral("/thumbnail?edited=true&size=") + detailQuality;
    } else if (type == "original") {
        url = serverUrl + QStringLiteral("/api/assets/") + assetId + QStringLiteral("/original");
    } else if (type == "person") {
        url = serverUrl + QStringLiteral("/api/people/") + assetId + QStringLiteral("/thumbnail");
    } else {
        qWarning() << "ImmichImageProvider: Unknown type:" << type;
        return new ImmichImageResponse(QString(), QString(), requestedSize);
    }

    return new ImmichImageResponse(url, accessToken, requestedSize);
}
