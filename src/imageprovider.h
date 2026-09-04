#ifndef IMAGEPROVIDER_H
#define IMAGEPROVIDER_H

#include <QObject>
#include <QString>
#include <QQuickAsyncImageProvider>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QQuickImageResponse>
#include <QPointer>
#include <QMutex>
#include <QQueue>
#include <QAtomicInt>
#include <QCache>

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
    bool m_finished;
    bool m_networkActive;

    static QAtomicInt s_activeRequests;
    static const int MAX_CONCURRENT_REQUESTS = 8;

    static void requestCompleted();
    static void enqueueOrStart(ImmichImageResponse *response);
    static void processQueue();
    static QMutex s_queueMutex;
    static QQueue<ImmichImageResponse*> s_pendingQueue;

    // In-memory thumbnail cache to avoid re-fetching on bucket reload
    static QMutex s_cacheMutex;
    static QCache<QString, QImage> s_imageCache;
};

class ImmichImageProvider: public QObject, public QQuickAsyncImageProvider {
    Q_OBJECT
public:
    ImmichImageProvider(AuthManager *authManager, SettingsManager *settingsManager, QObject *parent = nullptr);
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;

private slots:
    void refreshServerUrl();
    void refreshAccessToken();
    void refreshDetailQuality();

private:
    AuthManager *m_authManager;
    SettingsManager *m_settingsManager;

    mutable QMutex m_stateMutex;
    QString m_serverUrl;
    QString m_accessToken;
    QString m_detailQuality;
};

#endif
