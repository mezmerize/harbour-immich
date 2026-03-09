#include "oauthmanager.h"
#include "authmanager.h"
#include "securestorage.h"
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>
#include <QUrlQuery>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QWindow>
#include <QDebug>

OAuthManager::OAuthManager(AuthManager *authManager, SecureStorage *storage, QObject *parent)
   : QObject(parent)
   , m_networkManager(new QNetworkAccessManager(this))
   , m_authManager(authManager)
   , m_storage(storage)
   , m_oauthEnabled(false)
   , m_busy(false)
{
}

OAuthManager::~OAuthManager()
{
}

bool OAuthManager::oauthEnabled() const
{
   return m_oauthEnabled;
}

bool OAuthManager::busy() const
{
   return m_busy;
}

void OAuthManager::setBusy(bool busy)
{
   if (m_busy != busy) {
       m_busy = busy;
       emit busyChanged();
   }
}

void OAuthManager::setOAuthEnabled(bool enabled)
{
   if (m_oauthEnabled != enabled) {
       m_oauthEnabled = enabled;
       emit oauthEnabledChanged();
   }
}

QString OAuthManager::redirectUri() const
{
   return QStringLiteral("app.immich://oauth-callback");
}

void OAuthManager::raiseWindow()
{
   const auto windows = QGuiApplication::allWindows();
   if (!windows.isEmpty()) {
       QWindow *window = windows.first();
       window->raise();
       window->requestActivate();
   }
}

void OAuthManager::checkOAuthAvailability(const QString &serverUrl)
{
   m_serverUrl = serverUrl;
   setOAuthEnabled(false);

   QUrl url(serverUrl + "/api/oauth/authorize");
   QNetworkRequest request(url);
   request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

   QJsonObject json;
   json["redirectUri"] = redirectUri();

   QNetworkReply *reply = m_networkManager->post(request, QJsonDocument(json).toJson());
   connect(reply, &QNetworkReply::finished, this, &OAuthManager::onServerConfigReplyFinished);
}

void OAuthManager::onServerConfigReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   if (reply->error() == QNetworkReply::NoError) {
       QByteArray response = reply->readAll();
       QJsonDocument doc = QJsonDocument::fromJson(response);
       QJsonObject obj = doc.object();

       if (obj.contains("url") && !obj["url"].toString().isEmpty()) {
           setOAuthEnabled(true);
       } else {
           setOAuthEnabled(false);
       }
   } else {
       setOAuthEnabled(false);
   }

   reply->deleteLater();
}

void OAuthManager::startOAuthLogin(const QString &serverUrl)
{
   m_serverUrl = serverUrl;
   setBusy(true);

   QUrl url(serverUrl + "/api/oauth/authorize");
   QNetworkRequest request(url);
   request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

   QJsonObject json;
   json["redirectUri"] = redirectUri();

   QNetworkReply *reply = m_networkManager->post(request, QJsonDocument(json).toJson());
   connect(reply, &QNetworkReply::finished, this, &OAuthManager::onAuthorizeReplyFinished);
}

void OAuthManager::cancelOAuthLogin()
{
    if (m_busy) {
        setBusy(false);
        emit oauthLoginFailed(QStringLiteral("Login cancelled"));
    }
}

void OAuthManager::handleCallbackUrl(const QString &url)
{
    qDebug() << "OAuthManager: Received callback URL";

    if (!m_busy) {
        qWarning() << "OAuthManager: Received callback but no OAuth login in progress";
        return;
    }

    raiseWindow();
    handleOAuthCallback(url);
}

void OAuthManager::onAuthorizeReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   if (reply->error() == QNetworkReply::NoError) {
       QByteArray response = reply->readAll();
       QJsonDocument doc = QJsonDocument::fromJson(response);
       QJsonObject obj = doc.object();

       QString oauthUrl = obj["url"].toString();
       if (!oauthUrl.isEmpty()) {
           QDesktopServices::openUrl(QUrl(oauthUrl));
       } else {
           setBusy(false);
           emit oauthLoginFailed("OAuth URL not received from server");
       }
   } else {
       setBusy(false);
       QString errorString = reply->errorString();
       QByteArray response = reply->readAll();
       QJsonDocument doc = QJsonDocument::fromJson(response);

       if (!doc.isNull()) {
           QJsonObject obj = doc.object();
           if (obj.contains("message")) {
               errorString = obj["message"].toString();
           }
       }

       emit oauthLoginFailed(errorString);
   }

   reply->deleteLater();
}

void OAuthManager::handleOAuthCallback(const QString &callbackUrl)
{
   QUrl url(m_serverUrl + "/api/oauth/callback");
   QNetworkRequest request(url);
   request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

   QJsonObject json;
   json["url"] = callbackUrl;

   QNetworkReply *reply = m_networkManager->post(request, QJsonDocument(json).toJson());
   connect(reply, &QNetworkReply::finished, this, &OAuthManager::onCallbackReplyFinished);
}

void OAuthManager::onCallbackReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   setBusy(false);

   if (reply->error() == QNetworkReply::NoError) {
       QByteArray response = reply->readAll();
       QJsonDocument doc = QJsonDocument::fromJson(response);
       QJsonObject obj = doc.object();

       QString accessToken = obj["accessToken"].toString();
       QString userEmail = obj["userEmail"].toString();

       if (!accessToken.isEmpty()) {
           m_storage->saveAccessToken(accessToken);
           if (!userEmail.isEmpty()) {
               m_storage->saveEmail(userEmail);
           }
           m_storage->saveServerUrl(m_serverUrl);

           // Clear any stored password since this is OAuth
           m_storage->savePassword(QString());

           emit oauthLoginSucceeded();
       } else {
           emit oauthLoginFailed("No access token received from OAuth callback");
       }
   } else {
       QString errorString = reply->errorString();
       QByteArray response = reply->readAll();
       QJsonDocument doc = QJsonDocument::fromJson(response);

       if (!doc.isNull()) {
           QJsonObject obj = doc.object();
           if (obj.contains("message")) {
               errorString = obj["message"].toString();
           }
       }

       emit oauthLoginFailed(errorString);
   }

   reply->deleteLater();
}
