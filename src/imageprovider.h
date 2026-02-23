#ifndef IMAGEPROVIDER_H
#define IMAGEPROVIDER_H

#include <QQuickAsyncImageProvider>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QQuickImageResponse>
#include <QPointer>
#include <QMutex>
#include <QQueue>
#include <QAtomicInt>

class AuthManager;
class SettingsManager;

class ImmichImageResponse : public QQuickImageResponse
{
    Q_OBJECT
public:
    ImmichImageResponse(const QString &url, const QString &authToken, const QSize &requestedSize);
    ~ImmichImageResponse() override;
    QQuickTextureFactory * textureFactory() const override;
    QString errorString() const override;
    void cancel() override;

    void startRequest(); // Called when slot becomes available
    bool isStarted() const { return m_started; }

private slots:
    void onFinished();

private:
    QString m_url;
    QString m_authToken;
    QNetworkAccessManager *m_networkManager;
    QPointer<QNetworkReply> m_reply;
    QImage m_image;
    QSize m_requestedSize;
    QString m_errorString;
    bool m_cancelled;
    bool m_started;

    static QAtomicInt s_activeRequests;
    static const int MAX_CONCURRENT_REQUESTS = 12; // Limit concurrent loads

    static void requestCompleted();
};

class ImmichImageProvider: public QQuickAsyncImageProvider {
public:
    ImmichImageProvider(AuthManager *authManager, SettingsManager *settingsManager);
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;

private:
    AuthManager *m_authManager;
    SettingsManager *m_settingsManager;
};

#endif
