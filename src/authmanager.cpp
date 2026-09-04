#include "authmanager.h"
#include <QDebug>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>

AuthManager::AuthManager(SecureStorage *storage, QObject *parent)
    : QObject(parent)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_storage(storage)
    , m_isAuthenticated(false)
{
}

bool AuthManager::isAuthenticated() const
{
    return m_isAuthenticated;
}

QString AuthManager::serverUrl() const
{
    return m_serverUrl;
}

void AuthManager::setServerUrl(const QString &url)
{
    if (m_serverUrl != url) {
        m_serverUrl = url;
        m_storage->saveServerUrl(url);
        emit serverUrlChanged();
    }
}

void AuthManager::setAuthenticated(bool authenticated)
{
    if (m_isAuthenticated != authenticated) {
        m_isAuthenticated = authenticated;
        emit isAuthenticatedChanged();
    }
}

QString AuthManager::email() const
{
    return m_email;
}

QString AuthManager::userId() const
{
    return m_userId;
}

void AuthManager::setUserId(const QString &userId)
{
    if (m_userId != userId) {
        m_userId = userId;
        emit userIdChanged();
    }
}

QString AuthManager::storedPassword() const
{
    return m_storage->loadPassword();
}

void AuthManager::setEmail(const QString &email)
{
    if (m_email != email) {
        m_email = email;
        m_storage->saveEmail(email);
        emit emailChanged();
    }
}

void AuthManager::checkStoredCredentials()
{
    qInfo() << "AuthManager: Checking stored credentials";
    m_serverUrl = m_storage->loadServerUrl();
    m_email = m_storage->loadEmail();
    m_accessToken = m_storage->loadAccessToken();
    emit serverUrlChanged();
    emit accessTokenChanged();

    if (!m_serverUrl.isEmpty() && !m_accessToken.isEmpty()) {
        qInfo() << "AuthManager: Found access token, validating";
        validateToken();
    } else {
        QString storedPassword = m_storage->loadPassword();
        if (!m_serverUrl.isEmpty() && !m_email.isEmpty() && !storedPassword.isEmpty()) {
            qInfo() << "AuthManager: No token, logging in with stored credentials";
            login(m_email, storedPassword);
        } else {
            qInfo() << "AuthManager: No stored credentials found";
            emit loginFailed(QString());
        }
    }
}

void AuthManager::reloginWithStoredCredentials()
{
    QString storedPassword = m_storage->loadPassword();
    if (!m_serverUrl.isEmpty() && !m_email.isEmpty() && !storedPassword.isEmpty()) {
        login(m_email, storedPassword);
    } else {
        emit authenticationRequired();
    }
}

void AuthManager::login(const QString &email, const QString &password)
{
    qInfo() << "AuthManager: Logging as" << email;
    setEmail(email);
    m_storage->savePassword(password);

    QUrl url(m_serverUrl + QStringLiteral("/api/auth/login"));
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QJsonObject json;
    json["email"] = email;
    json["password"] = password;

    QJsonDocument doc(json);
    QByteArray data = doc.toJson();

    QNetworkReply *reply = m_networkManager->post(request, data);
    connect(reply, &QNetworkReply::finished, this, &AuthManager::onLoginReplyFinished);
}

void AuthManager::onLoginReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;

    if (reply->error() == QNetworkReply::NoError) {
        QByteArray response = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject obj = doc.object();

        m_accessToken = obj["accessToken"].toString();

        m_storage->saveAccessToken(m_accessToken);
        emit accessTokenChanged();

        qInfo() << "AuthManager: Login succeeded";
        setAuthenticated(true);
        fetchCurrentUser();
        emit loginSucceeded();
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
        
        qInfo() << "AuthManager: Login failed:" << errorString;
        m_accessToken.clear();
        m_storage->saveAccessToken(QString());
        emit accessTokenChanged();
        setAuthenticated(false);
        emit loginFailed(errorString);
    }

    reply->deleteLater();
}

void AuthManager::logout()
{
    qInfo() << "AuthManager: Logging out";
    m_accessToken.clear();
    m_email.clear();
    m_userId.clear();
    m_storage->clearAll();
    emit accessTokenChanged();
    setAuthenticated(false);
    emit emailChanged();
    emit userIdChanged();
}

void AuthManager::setOAuthCredentials(const QString &serverUrl, const QString &accessToken, const QString &userEmail)
{
    qInfo() << "AuthManager: Setting OAuth credentials for" << userEmail;

    m_serverUrl = serverUrl;
    m_accessToken = accessToken;

    m_storage->saveServerUrl(serverUrl);
    m_storage->saveAccessToken(accessToken);
    m_storage->savePassword(QString());

    if (!userEmail.isEmpty()) {
        setEmail(userEmail);
    }

    emit serverUrlChanged();
    emit accessTokenChanged();
    setAuthenticated(true);
    fetchCurrentUser();
    emit loginSucceeded();
}

QString AuthManager::getAccessToken() const
{
    return m_accessToken;
}

void AuthManager::validateToken()
{
    QUrl url(m_serverUrl + QStringLiteral("/api/auth/validateToken"));
    QNetworkRequest request(url);
    request.setRawHeader("Authorization", QString("Bearer %1").arg(m_accessToken).toUtf8());
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QNetworkReply *reply = m_networkManager->post(request, QByteArray());
    connect(reply, &QNetworkReply::finished, this, &AuthManager::onValidateTokenReplyFinished);
}

void AuthManager::onValidateTokenReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;

    if (reply->error() == QNetworkReply::NoError) {
        QByteArray response = reply->readAll();
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject obj = doc.object();

        if (obj["authStatus"].toBool()) {
            qInfo() << "AuthManager: Token validated successfully";
            setAuthenticated(true);
            fetchCurrentUser();
            emit loginSucceeded();
        } else {
            qInfo() << "AuthManager: Token invalid, re-logging in";
            reloginWithStoredCredentials();
        }
    } else {
        qInfo() << "AuthManager: Token validation failed, re-logging in";
        reloginWithStoredCredentials();
    }

    reply->deleteLater();
}

void AuthManager::fetchCurrentUser()
{
    QUrl url(m_serverUrl + QStringLiteral("/api/users/me"));
    QNetworkRequest request(url);
    request.setRawHeader("Authorization", QString("Bearer %1").arg(m_accessToken).toUtf8());

    QNetworkReply *reply = m_networkManager->get(request);
    connect(reply, &QNetworkReply::finished, this, &AuthManager::onUserMeReplyFinished);
}

void AuthManager::onUserMeReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;

    if (reply->error() == QNetworkReply::NoError) {
        QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        QJsonObject obj = doc.object();
        setUserId(obj["id"].toString());
        QString email = obj["email"].toString();
        if (!email.isEmpty()) {
            setEmail(email);
        }
        qInfo() << "AuthManager: Current user fetched, id:" << m_userId;
    } else {
        qWarning() << "AuthManager: Failed to fetch current user:" << reply->errorString();
    }

    reply->deleteLater();
}
