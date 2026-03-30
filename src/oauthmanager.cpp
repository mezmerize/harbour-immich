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
#include <QCryptographicHash>
#include <QDateTime>
#include <QDebug>

OAuthManager::OAuthManager(AuthManager *authManager, SecureStorage *storage, QObject *parent)
   : QObject(parent)
   , m_networkManager(new QNetworkAccessManager(this))
   , m_authManager(authManager)
   , m_storage(storage)
   , m_oauthEnabled(false)
   , m_busy(false)
{
    qsrand(static_cast<uint>(QDateTime::currentMSecsSinceEpoch()));
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

QString OAuthManager::generateRandomString(int length)
{
    const QByteArray chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
    QString result;
    result.reserve(length);
    for (int i = 0; i < length; ++i) {
        result.append(chars.at(qrand() % chars.size()));
    }
    return result;
}

QString OAuthManager::computeCodeChallenge(const QString &codeVerifier)
{
    QByteArray hash = QCryptographicHash::hash(codeVerifier.toUtf8(), QCryptographicHash::Sha256);
    return QString::fromLatin1(hash.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}

void OAuthManager::resetOAuthState()
{
    m_codeVerifier.clear();
    m_state.clear();
    m_serverUrl.clear();
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

   QUrl url(serverUrl + QStringLiteral("/api/oauth/authorize"));
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
   m_codeVerifier = generateRandomString(128);
   m_state = generateRandomString(32);
   setBusy(true);

   QUrl url(serverUrl + QStringLiteral("/api/oauth/authorize"));
   QNetworkRequest request(url);
   request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

   QJsonObject json;
   json["redirectUri"] = redirectUri();
   json["codeChallenge"] = computeCodeChallenge(m_codeVerifier);
   json["state"] = m_state;

   QNetworkReply *reply = m_networkManager->post(request, QJsonDocument(json).toJson());
   connect(reply, &QNetworkReply::finished, this, &OAuthManager::onAuthorizeReplyFinished);
}

void OAuthManager::cancelOAuthLogin()
{
    if (m_busy) {
        resetOAuthState();
        setBusy(false);
        emit oauthLoginFailed(QStringLiteral("Login cancelled"));
    }
}

void OAuthManager::handleCallbackUrl(const QString &url)
{
    qDebug() << "OAuthManager: Received callback URL";

    raiseWindow();

    if (m_serverUrl.isEmpty() || m_codeVerifier.isEmpty() || m_state.isEmpty() || !m_busy) {
        qWarning() << "OAuthManager: Received callback but no OAuth login in progress";
        setBusy(false);
        emit oauthLoginFailed(QStringLiteral("OAuth session expired. Please try again."));
        return;
    }

    QUrl callbackUrl(url);
    QUrlQuery query(callbackUrl);
    QString callbackState = query.queryItemValue(QStringLiteral("state"));

    if (!callbackState.isEmpty() && callbackState != m_state) {
        qWarning() << "OAuthManager: State mismatch - expected:" << m_state << "got:" << callbackState;
        resetOAuthState();
        setBusy(false);
        emit oauthLoginFailed(QStringLiteral("OAuth state mismatch. Please try again."));
        return;
    }

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
   QUrl url(m_serverUrl + QStringLiteral("/api/oauth/callback"));
   QNetworkRequest request(url);
   request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

   QJsonObject json;
   json["url"] = callbackUrl;
   json["codeVerifier"] = m_codeVerifier;
   json["state"] = m_state;

   QNetworkReply *reply = m_networkManager->post(request, QJsonDocument(json).toJson());
   connect(reply, &QNetworkReply::finished, this, &OAuthManager::onCallbackReplyFinished);
}

void OAuthManager::onCallbackReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   QString serverUrl = m_serverUrl;
   resetOAuthState();
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
           m_storage->saveServerUrl(serverUrl);

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
