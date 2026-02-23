#include "imageprovider.h"
#include "authmanager.h"
#include "settingsmanager.h"
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QDebug>
#include <QThread>

// Static member initialization
QAtomicInt ImmichImageResponse::s_activeRequests(0);

static QNetworkAccessManager* getThreadLocalNetworkManager()
{
   thread_local QNetworkAccessManager* manager = nullptr;
   if (!manager) {
       manager = new QNetworkAccessManager();
       // Clean up when thread exits
       QObject::connect(QThread::currentThread(), &QThread::finished, [=]() {
           delete manager;
       });
   }
   return manager;
}

ImmichImageResponse::ImmichImageResponse(const QString &url, const QString &authToken, const QSize &requestedSize)
   : m_url(url)
   , m_authToken(authToken)
   , m_networkManager(nullptr)
   , m_reply(nullptr)
   , m_requestedSize(requestedSize)
   , m_cancelled(false)
   , m_started(false)
{
   startRequest();
}

void ImmichImageResponse::startRequest()
{
   if (m_started || m_cancelled) return;

   m_started = true;
   s_activeRequests.fetchAndAddAcquire(1);

   m_networkManager = getThreadLocalNetworkManager();

   QNetworkRequest request(m_url);
   request.setRawHeader("Authorization", QString("Bearer %1").arg(m_authToken).toUtf8());
   request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);

   m_reply = m_networkManager->get(request);
   connect(m_reply, &QNetworkReply::finished, this, &ImmichImageResponse::onFinished);
}

void ImmichImageResponse::requestCompleted()
{
   s_activeRequests.fetchAndSubAcquire(1);
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
   if (m_started) {
       requestCompleted();
   }
   emit finished();
}

void ImmichImageResponse::onFinished()
{
   // Always decrement counter when request completes
   requestCompleted();

   // Check if cancelled or reply is invalid
   if (m_cancelled || !m_reply) {
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
       return nullptr;
   }

   QString type = parts[0];
   QString assetId = parts[1];

   QString url;
   if (type == "thumbnail") {
       url = m_authManager->serverUrl() + "/api/assets/" + assetId + "/thumbnail?edited=true";
       if (m_settingsManager) {
           QString size = m_settingsManager->thumbnailQuality();
           if (!size.isEmpty()) {
               url += "&size=" + size;
           }
       }
   } else if (type == "original") {
       url = m_authManager->serverUrl() + "/api/assets/" + assetId + "/original";
   } else if (type == "person") {
       url = m_authManager->serverUrl() + "/api/people/" + assetId + "/thumbnail";
   } else {
       qWarning() << "ImmichImageProvider: Unknown type:" << type;
       return nullptr;
   }

   return new ImmichImageResponse(url, m_authManager->getAccessToken(), requestedSize);
}
