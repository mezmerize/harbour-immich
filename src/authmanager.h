#ifndef AUTHMANAGER_H
#define AUTHMANAGER_H

#include <QObject>
#include <QString>
#include "securestorage.h"

class QNetworkAccessManager;
class QNetworkReply;

class AuthManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isAuthenticated READ isAuthenticated NOTIFY isAuthenticatedChanged)
    Q_PROPERTY(QString serverUrl READ serverUrl WRITE setServerUrl NOTIFY serverUrlChanged)
    Q_PROPERTY(QString email READ email NOTIFY emailChanged)
    Q_PROPERTY(QString userId READ userId NOTIFY userIdChanged)
    Q_PROPERTY(QString storedPassword READ storedPassword NOTIFY storedPasswordChanged)

public:
    explicit AuthManager(SecureStorage *storage, QObject *parent = nullptr);

    bool isAuthenticated() const;
    QString serverUrl() const;
    void setServerUrl(const QString &url);
    QString email() const;
    QString userId() const;
    QString storedPassword() const;

    Q_INVOKABLE void login(const QString &email, const QString &password);
    Q_INVOKABLE void logout();
    Q_INVOKABLE void checkStoredCredentials();

    QString getAccessToken() const;
    Q_INVOKABLE void reloginWithStoredCredentials();
    Q_INVOKABLE void validateToken();
    void setOAuthCredentials(const QString &serverUrl, const QString &accessToken, const QString &userEmail);

signals:
    void isAuthenticatedChanged();
    void serverUrlChanged();
    void accessTokenChanged();
    void emailChanged();
    void userIdChanged();
    void storedPasswordChanged();
    void loginSucceeded();
    void loginFailed(const QString &error);
    void authenticationRequired();

private slots:
    void onLoginReplyFinished();
    void onValidateTokenReplyFinished();
    void onUserMeReplyFinished();

private:
    QNetworkAccessManager *m_networkManager;
    SecureStorage *m_storage;
    QString m_serverUrl;
    QString m_email;
    QString m_userId;
    QString m_accessToken;
    bool m_isAuthenticated;

    void setAuthenticated(bool authenticated);
    void setEmail(const QString &email);
    void setUserId(const QString &userId);
    void fetchCurrentUser();
};

#endif
