#ifndef OAUTHMANAGER_H
#define OAUTHMANAGER_H

#include <QObject>
#include <QString>

class QNetworkAccessManager;
class AuthManager;

class OAuthManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool oauthEnabled READ oauthEnabled NOTIFY oauthEnabledChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit OAuthManager(AuthManager *authManager, QObject *parent = nullptr);

    bool oauthEnabled() const;
    bool busy() const;

    Q_INVOKABLE void checkOAuthAvailability(const QString &serverUrl);
    Q_INVOKABLE void startOAuthLogin(const QString &serverUrl);
    Q_INVOKABLE void cancelOAuthLogin();

public slots:
    void handleCallbackUrl(const QString &url);

signals:
    void oauthEnabledChanged();
    void busyChanged();
    void oauthLoginSucceeded();
    void oauthLoginFailed(const QString &error);

private slots:
#ifndef HARBOUR_BUILD
    void onServerConfigReplyFinished();
#endif
    void onAuthorizeReplyFinished();
    void onCallbackReplyFinished();

private:
    QNetworkAccessManager *m_networkManager;
    AuthManager *m_authManager;
    QString m_serverUrl;
    QString m_codeVerifier;
    QString m_state;
    bool m_oauthEnabled;
    bool m_busy;

    void setBusy(bool busy);
    void setOAuthEnabled(bool enabled);
    void handleOAuthCallback(const QString &callbackUrl);
    QString redirectUri() const;
    void raiseWindow();
    void resetOAuthState();
    static QString generateRandomString(int length);
    static QString computeCodeChallenge(const QString &codeVerifier);
};

#endif // OAUTHMANAGER_H
