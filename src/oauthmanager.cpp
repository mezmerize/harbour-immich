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
#include <QTcpSocket>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QWindow>
#include <QDebug>

OAuthManager::OAuthManager(AuthManager *authManager, SecureStorage *storage, QObject *parent)
   : QObject(parent)
   , m_networkManager(new QNetworkAccessManager(this))
   , m_callbackServer(new QTcpServer(this))
   , m_authManager(authManager)
   , m_storage(storage)
   , m_oauthEnabled(false)
   , m_busy(false)
{
   connect(m_callbackServer, &QTcpServer::newConnection, this, &OAuthManager::onNewConnection);
}

OAuthManager::~OAuthManager()
{
   stopCallbackServer();
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
   return QString("http://127.0.0.1:%1/callback").arg(CALLBACK_PORT);
}

bool OAuthManager::startCallbackServer()
{
   if (m_callbackServer->isListening()) {
       return true;
   }

   if (!m_callbackServer->listen(QHostAddress::LocalHost, CALLBACK_PORT)) {
       qWarning() << "OAuthManager: Failed to start callback server on port" << CALLBACK_PORT
                   << ":" << m_callbackServer->errorString();
       return false;
   }

   qDebug() << "OAuthManager: Callback server listening on port" << CALLBACK_PORT;
   return true;
}

void OAuthManager::stopCallbackServer()
{
   if (m_callbackServer->isListening()) {
       m_callbackServer->close();
       qDebug() << "OAuthManager: Callback server stopped";
   }
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

   if (!startCallbackServer()) {
       setBusy(false);
       emit oauthLoginFailed("Could not start local callback server");
       return;
   }

   QUrl url(serverUrl + "/api/oauth/authorize");
   QNetworkRequest request(url);
   request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

   QJsonObject json;
   json["redirectUri"] = redirectUri();

   QNetworkReply *reply = m_networkManager->post(request, QJsonDocument(json).toJson());
   connect(reply, &QNetworkReply::finished, this, &OAuthManager::onAuthorizeReplyFinished);
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
           stopCallbackServer();
           setBusy(false);
           emit oauthLoginFailed("OAuth URL not received from server");
       }
   } else {
       stopCallbackServer();
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

void OAuthManager::onNewConnection()
{
   QTcpSocket *socket = m_callbackServer->nextPendingConnection();
   if (!socket) return;

   connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
       QByteArray data = socket->readAll();
       QString request = QString::fromUtf8(data);

       // Parse the HTTP request line to extract the path and query
       // e.g. "GET /callback?code=abc&state=xyz HTTP/1.1\r\n..."
       int endOfLine = request.indexOf("\r\n");
       if (endOfLine < 0) endOfLine = request.length();
       QString requestLine = request.left(endOfLine);
       QStringList parts = requestLine.split(' ');

       QString callbackUrl;
       if (parts.size() >= 2) {
           // Reconstruct the full callback URL
           callbackUrl = redirectUri().section('/', 0, 2) + parts[1];
       }

       // Send a response to the browser
       QByteArray httpResponse =
           "HTTP/1.1 200 OK\r\n"
           "Content-Type: text/html; charset=utf-8\r\n"
           "Connection: close\r\n"
           "\r\n"
           "<!DOCTYPE html><html><head>"
           "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
           "<style>body{font-family:sans-serif;display:flex;justify-content:center;"
           "align-items:center;min-height:100vh;margin:0;background:#1a1a2e;color:#e0e0e0;}"
           ".card{text-align:center;padding:2em;border-radius:12px;background:#16213e;}"
           "h1{color:#4ecca3;}p{color:#a0a0b0;}</style></head><body>"
           "<div class=\"card\"><h1>&#10003; Authentication Successful</h1>"
           "<p>You can close this tab and return to the app.</p></div>"
           "</body></html>";

       socket->write(httpResponse);
       socket->flush();
       socket->disconnectFromHost();

       // Bring the app to foreground
       raiseWindow();

       // Stop listening for more connections
       stopCallbackServer();

       if (!callbackUrl.isEmpty()) {
           handleOAuthCallback(callbackUrl);
       } else {
           setBusy(false);
           emit oauthLoginFailed("Invalid OAuth callback received");
       }
   });

   connect(socket, &QTcpSocket::disconnected, socket, &QTcpSocket::deleteLater);
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
