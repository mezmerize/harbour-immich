#ifndef LOCALTHUMBNAILPROVIDER_H
#define LOCALTHUMBNAILPROVIDER_H

#include <QQuickAsyncImageProvider>
#include <QQuickImageResponse>
#include <QQuickTextureFactory>
#include <QSharedPointer>
#include <QMutex>
#include <QImage>
#include <QString>
#include <QSize>
#include <QAtomicInt>

class LocalThumbnailResponse : public QQuickImageResponse
{
    Q_OBJECT
public:
    struct State {
        QMutex mutex;
        QAtomicInt cancelled;
        LocalThumbnailResponse *response;
        QImage image;
        QString error;
        State() : cancelled(0), response(nullptr) {}
    };

    LocalThumbnailResponse(const QString &path, bool crop, const QSize &requestedSize);
    ~LocalThumbnailResponse() override;
    QQuickTextureFactory *textureFactory() const override;
    QString errorString() const override;
    void cancel() override;

    Q_INVOKABLE void onJobFinished();

private:
    QSharedPointer<State> m_state;
    bool m_finished;
};

class LocalThumbnailProvider : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};

#endif // LOCALTHUMBNAILPROVIDER_H
