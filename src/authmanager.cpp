#include "authmanager.h"
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
    m_serverUrl = m_storage->loadServerUrl();
    m_email = m_storage->loadEmail();
    m_accessToken = m_storage->loadAccessToken();

    if (!m_serverUrl.isEmpty() && !m_accessToken.isEmpty()) {
        // We have access token - validate it
        validateToken();
    } else {
        QString storedPassword = m_storage->loadPassword();
        if (!m_serverUrl.isEmpty() && !m_email.isEmpty() && !storedPassword.isEmpty()) {
            // No access token but credentials are stored
            login(m_email, storedPassword);
        } else {
            // No credentials
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
    // Store email and password for later use
    setEmail(email);
    m_storage->savePassword(password);

    QUrl url(m_serverUrl + "/api/auth/login");
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

        setAuthenticated(true);
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
        
        emit loginFailed(errorString);
    }

    reply->deleteLater();
}

void AuthManager::logout()
{
    m_accessToken.clear();
    m_email.clear();
    m_storage->clearAll();
    setAuthenticated(false);
    emit emailChanged();
}

QString AuthManager::getAccessToken() const
{
    return m_accessToken;
}

void AuthManager::validateToken()
{
    QUrl url(m_serverUrl + "/api/auth/validateToken");
    QNetworkRequest request(url);
    request.setRawHeader("X-Api-Key", m_accessToken.toUtf8());

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
            // Token is valid
            setAuthenticated(true);
            emit loginSucceeded();
        } else {
            // Token invalid - use stored credentials
            reloginWithStoredCredentials();
        }
    } else {
        // Validation failed - use stored credentials
        reloginWithStoredCredentials();
    }

    reply->deleteLater();
}
