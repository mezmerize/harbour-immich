#include "imageprovider.h"
#include "authmanager.h"
#include "settingsmanager.h"
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QDebug>
#include <QThread>

// Static member initialization
QAtomicInt ImmichImageResponse::s_activeRequests(0);
QMutex ImmichImageResponse::s_queueMutex;
QQueue<ImmichImageResponse*> ImmichImageResponse::s_pendingQueue;
QMutex ImmichImageResponse::s_cacheMutex;
QCache<QString, QImage> ImmichImageResponse::s_imageCache(50 * 1024 * 1024); // ~50MB cost limit

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
    if (m_started || m_cancelled) return;

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

    m_started = true;
    m_networkActive = true;
    s_activeRequests.fetchAndAddAcquire(1);

    m_networkManager = new QNetworkAccessManager(this);

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
    // Safety: if we still hold an active request slot, release it
    if (m_networkActive) {
        m_networkActive = false;
        requestCompleted();
    }
    // Safety: if we're still in the queue, remove ourselves
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
    // Only decrement if we actually hold a network slot
    if (m_networkActive) {
        m_networkActive = false;
        requestCompleted();
    } else if (!m_started) {
        // Remove from queue if not yet started
        QMutexLocker locker(&s_queueMutex);
        s_pendingQueue.removeOne(this);
    }
    // Only emit finished if we haven't already — prevents poisoning
    // a successful pixmap cache entry with an error
    if (!m_finished) {
        m_errorString = QStringLiteral("Cancelled");
        m_finished = true;
        emit finished();
    }
}

void ImmichImageResponse::onFinished()
{
    // Release our network slot (exactly once)
    if (m_networkActive) {
        m_networkActive = false;
        requestCompleted();
    }

    // Don't emit twice (cancel may have beaten us)
    if (m_finished) return;

    // Check if cancelled or reply is invalid
    if (m_cancelled || !m_reply) {
        m_finished = true;
        emit finished();
        return;
    }

    // Disconnect to prevent any further callbacks
    m_reply->disconnect(this);

    if (m_reply->error() == QNetworkReply::NoError) {
        QByteArray data = m_reply->readAll();

        if (data.isEmpty()) {
            m_errorString = QStringLiteral("Empty response data");
        } else {
            // Try to load image with error handling for memory issues
            try {
                if (!m_image.loadFromData(data)) {
                    m_errorString = QStringLiteral("Failed to load image data");
                    qWarning() << "ImmichImageProvider: Failed to parse image, size:" << data.size();
                } else {
                    // Scale down to save memory - use smaller size for thumbnails
                    if (!m_image.isNull()) {
                        QSize targetSize = m_requestedSize;
                        if (!targetSize.isValid()) {
                            // Default max size to prevent huge images in memory
                            targetSize = QSize(1920, 1920);
                        }
                        if (m_image.width() > targetSize.width() || m_image.height() > targetSize.height()) {
                            m_image = m_image.scaled(targetSize, Qt::KeepAspectRatio, Qt::FastTransformation);
                        }

                        // Store in cache (cost = byte count of image)
                        QMutexLocker locker(&s_cacheMutex);
                        s_imageCache.insert(m_url, new QImage(m_image), m_image.byteCount());
                    }
                }
            } catch (const std::bad_alloc &) {
                m_errorString = QStringLiteral("Out of memory loading image");
                qWarning() << "ImmichImageProvider: Out of memory loading image, size:" << data.size();
                m_image = QImage();  // Clear any partial image
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

ImmichImageProvider::ImmichImageProvider(AuthManager *authManager, SettingsManager *settingsManager)
    : QQuickAsyncImageProvider()
    , m_authManager(authManager)
    , m_settingsManager(settingsManager)
{
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

    QString url;
    if (type == "thumbnail") {
        url = m_authManager->serverUrl() + QStringLiteral("/api/assets/") + assetId + QStringLiteral("/thumbnail?edited=true&size=thumbnail");
    } else if (type == "detail") {
        QString size = QStringLiteral("preview");
        if (m_settingsManager) {
            size = m_settingsManager->detailQuality();
        }
        url = m_authManager->serverUrl() + QStringLiteral("/api/assets/") + assetId + QStringLiteral("/thumbnail?edited=true&size=") + size;
    } else if (type == "original") {
        url = m_authManager->serverUrl() + QStringLiteral("/api/assets/") + assetId + QStringLiteral("/original");
    } else if (type == "person") {
        url = m_authManager->serverUrl() + QStringLiteral("/api/people/") + assetId + QStringLiteral("/thumbnail");
    } else {
        qWarning() << "ImmichImageProvider: Unknown type:" << type;
        return new ImmichImageResponse(QString(), QString(), requestedSize);
    }

    return new ImmichImageResponse(url, m_authManager->getAccessToken(), requestedSize);
}
