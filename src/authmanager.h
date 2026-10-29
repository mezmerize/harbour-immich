#ifndef AUTHMANAGER_H
#define AUTHMANAGER_H

#include <QObject>
#include <QPointer>
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
    Q_PROPERTY(QString serverVersion READ serverVersion NOTIFY serverVersionChanged)
    Q_PROPERTY(QString clusterGroupId READ clusterGroupId NOTIFY clusterGroupIdChanged)
    Q_PROPERTY(bool serverSupported READ serverSupported NOTIFY serverVersionChanged)
    Q_PROPERTY(bool checkingServer READ checkingServer NOTIFY checkingServerChanged)

public:
    explicit AuthManager(SecureStorage *storage, QObject *parent = nullptr);

    bool isAuthenticated() const;
    QString serverUrl() const;
    void setServerUrl(const QString &url);
    QString email() const;
    QString userId() const;
    QString serverVersion() const;
    QString clusterGroupId() const;
    bool serverSupported() const;
    bool checkingServer() const;

    Q_INVOKABLE void login(const QString &email, const QString &password);
    Q_INVOKABLE void logout();
    Q_INVOKABLE void checkStoredCredentials();
    Q_INVOKABLE void checkServer(const QString &url);

    QString getAccessToken() const;
    Q_INVOKABLE void reloginWithStoredCredentials();
    Q_INVOKABLE void validateToken();
    Q_INVOKABLE void fetchCurrentUser();
    void setOAuthCredentials(const QString &serverUrl, const QString &accessToken, const QString &userEmail);

signals:
    void isAuthenticatedChanged();
    void serverUrlChanged();
    void accessTokenChanged();
    void emailChanged();
    void userIdChanged();
    void loginSucceeded();
    void loginFailed(const QString &error);
    void serverCheckSucceeded();
    void serverCheckFailed(const QString &error);
    void serverVersionChanged();
    void clusterGroupIdChanged();
    void checkingServerChanged();

private slots:
    void onLoginReplyFinished();
    void onValidateTokenReplyFinished();
    void onUserMeReplyFinished();
    void onServerCheckReplyFinished();

private:
    QNetworkAccessManager *m_networkManager;
    SecureStorage *m_storage;
    QString m_serverUrl;
    QString m_email;
    QString m_userId;
    QString m_accessToken;
    QString m_serverVersion;
    QString m_clusterGroupId;
    bool m_isAuthenticated;
    bool m_serverSupported;
    bool m_checkingServer;
    bool m_serverCheckAutoLogin;
    QString m_serverCheckUrl;
    QPointer<QNetworkReply> m_serverCheckReply;

    void setCheckingServer(bool checking);
    void setAuthenticated(bool authenticated);
    void startServerCheck(const QString &url, bool autoLogin);
    void proceedWithStoredCredentials();
    void setEmail(const QString &email);
    void setUserId(const QString &userId);
};

#endif
