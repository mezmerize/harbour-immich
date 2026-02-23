#ifndef OAUTHMANAGER_H
#define OAUTHMANAGER_H

#include <QObject>
#include <QString>
#include <QTcpServer>

class QNetworkAccessManager;
class QNetworkReply;
class QTcpSocket;
class AuthManager;
class SecureStorage;

class OAuthManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool oauthEnabled READ oauthEnabled NOTIFY oauthEnabledChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit OAuthManager(AuthManager *authManager, SecureStorage *storage, QObject *parent = nullptr);
    ~OAuthManager();

    bool oauthEnabled() const;
    bool busy() const;

    Q_INVOKABLE void checkOAuthAvailability(const QString &serverUrl);
    Q_INVOKABLE void startOAuthLogin(const QString &serverUrl);

signals:
    void oauthEnabledChanged();
    void busyChanged();
    void oauthLoginSucceeded();
    void oauthLoginFailed(const QString &error);

private slots:
    void onServerConfigReplyFinished();
    void onAuthorizeReplyFinished();
    void onCallbackReplyFinished();
    void onNewConnection();

private:
    QNetworkAccessManager *m_networkManager;
    QTcpServer *m_callbackServer;
    AuthManager *m_authManager;
    SecureStorage *m_storage;
    QString m_serverUrl;
    bool m_oauthEnabled;
    bool m_busy;
    static const int CALLBACK_PORT = 34821;

    void setBusy(bool busy);
    void setOAuthEnabled(bool enabled);
    bool startCallbackServer();
    void stopCallbackServer();
    void handleOAuthCallback(const QString &callbackUrl);
    QString redirectUri() const;
    void raiseWindow();
};

#endif // OAUTHMANAGER_H
