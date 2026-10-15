#include "localthumbnailprovider.h"
#include <QStandardPaths>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QDateTime>
#include <QCryptographicHash>
#include <QImageReader>
#include <QImageIOHandler>
#include <QMimeDatabase>
#include <QProcess>
#include <QThreadPool>
#include <QRunnable>
#include <QCoreApplication>
#include <QDebug>
#include <QUrl>
#include <QMetaObject>
#include <algorithm>

namespace {

const qint64 DiskCacheMaxBytes = 150LL * 1024 * 1024;
const int DiskCacheMaxAgeDays = 30;

QThreadPool *thumbnailPool()
{
    static QThreadPool *pool = []() {
        QThreadPool *p = new QThreadPool;
        p->setMaxThreadCount(2);
        return p;
    }();
    return pool;
}

QString thumbnailCacheDir()
{
    static QString dir;
    if (dir.isEmpty()) {
        dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/local-thumbnails");
        QDir().mkpath(dir);
    }
    return dir;
}

int bucketFor(const QSize &requestedSize)
{
    int s = qMax(requestedSize.width(), requestedSize.height());
    if (s <= 0)
        s = 1024;
    static const int buckets[] = {128, 256, 512, 768, 1024, 1536, 2048};
    for (int b : buckets) {
        if (s <= b) return b;
    }
    return 2048;
}

QString cachePathFor(const QString &path, qint64 mtimeMs, qint64 fileSize, int bucket, bool crop)
{
    const QString key = path + QLatin1Char('|') + QString::number(mtimeMs) + QLatin1Char('|') + QString::number(fileSize) + QLatin1Char('|') + QString::number(bucket) + QLatin1Char('|') + (crop ? QStringLiteral("crop") : QStringLiteral("fit"));
    const QByteArray hex = QCryptographicHash::hash(key.toUtf8(), QCryptographicHash::Sha1).toHex();
    return thumbnailCacheDir() + QLatin1Char('/') + QString::fromLatin1(hex) + QStringLiteral(".jpg");
}

QAtomicInt g_pruned(0);
QAtomicInt g_tmpCounter(0);

void pruneOnce()
{
    if (g_pruned.fetchAndStoreRelaxed(1))
        return;

    qint64 total = 0;
    QList<QFileInfo> files;
    const QDateTime staleBefore = QDateTime::currentDateTime().addDays(-DiskCacheMaxAgeDays);
    QDirIterator it(thumbnailCacheDir(), QStringList() << QStringLiteral("*.jpg"), QDir::Files, QDirIterator::NoIteratorFlags);
    while (it.hasNext()) {
        it.next();
        const QFileInfo fi = it.fileInfo();
        if (fi.lastModified() < staleBefore) {
            QFile::remove(fi.absoluteFilePath());
            continue;
        }
        total += fi.size();
        files.append(fi);
    }

    if (total <= DiskCacheMaxBytes)
        return;

    std::sort(files.begin(), files.end(), [](const QFileInfo &a, const QFileInfo &b) {
        return a.lastModified() < b.lastModified();
    });
    for (const QFileInfo &fi : files) {
        if (total <= DiskCacheMaxBytes)
            break;
        total -= fi.size();
        QFile::remove(fi.absoluteFilePath());
    }
}

bool isVideoFile(const QString &path)
{
    return QMimeDatabase().mimeTypeForFile(path).name().startsWith(QLatin1String("video/"));
}

QImage makeImageThumbnail(const QString &path, int bucket, bool crop)
{
    QImageReader reader(path);
    reader.setAutoTransform(true);
    reader.setQuality(49);

    const Qt::AspectRatioMode mode = crop ? Qt::KeepAspectRatioByExpanding : Qt::KeepAspectRatio;
    const QSize box(bucket, bucket);
    const QSize orig = reader.size();
    if (orig.isValid()) {
        const bool rotate90 = (reader.transformation() & QImageIOHandler::TransformationRotate90) != 0;
        const QSize d = rotate90 ? orig.transposed() : orig;
        QSize sd = d.scaled(box, mode);
        if (sd.width() > d.width() || sd.height() > d.height()) {
            sd = d;
        }
        reader.setScaledSize(rotate90 ? sd.transposed() : sd);
        return reader.read();
    }

    QImage img = reader.read();
    if (img.isNull())
        return img;
    if (img.width() > bucket || img.height() > bucket) {
        img = img.scaled(box, mode, Qt::SmoothTransformation);
    }
    return img;
}

QImage makeVideoThumbnail(const QString &path, int bucket, bool crop, const QString &tmpPath, QString *error)
{
    const QString tool = QStringLiteral("/usr/bin/thumbnaild-video");
    if (!QFile::exists(tool)) {
        *error = QStringLiteral("No video thumbnailer");
        return QImage();
    }
    QStringList args;
    args << path << QStringLiteral("-w") << QString::number(bucket) << QStringLiteral("-h") << QString::number(bucket) << QStringLiteral("-o") << tmpPath;
    if (crop) args << QStringLiteral("-c");

    QProcess p;
    p.start(tool, args);
    if (!p.waitForFinished(15000)) {
        p.kill();
        p.waitForFinished(1000);
        QFile::remove(tmpPath);
        *error = QStringLiteral("Video thumbnailer timed out");
        return QImage();
    }
    QImage img;
    if (p.exitCode() != 0 || !img.load(tmpPath) || img.isNull()) {
        QFile::remove(tmpPath);
        *error = QStringLiteral("Video thumbnailer failed");
        return QImage();
    }
    return img;
}

class ThumbnailJob : public QRunnable
{
public:
    ThumbnailJob(const QSharedPointer<LocalThumbnailResponse::State> &state, const QString &path, bool crop, int bucket)
        : m_state(state)
        , m_path(path)
        , m_crop(crop)
        , m_bucket(bucket)
    {
    }

    void run() override
    {
        if (m_state->cancelled.load()) {
            return;
        }

        QImage image;
        QString error;

        const QFileInfo fi(m_path);
        if (!fi.exists()) {
            error = QStringLiteral("File not found");
        } else {
            const QString cachePath = cachePathFor(m_path, fi.lastModified().toMSecsSinceEpoch(), fi.size(), m_bucket, m_crop);
            if (QFile::exists(cachePath) && image.load(cachePath) && !image.isNull()) {
                // cache hit
            } else {
                pruneOnce();
                const QString tmpPath = cachePath + QStringLiteral(".tmp-") + QString::number(QCoreApplication::applicationPid()) + QLatin1Char('-') + QString::number(g_tmpCounter.fetchAndAddRelaxed(1));

                if (isVideoFile(m_path)) {
                    image = makeVideoThumbnail(m_path, m_bucket, m_crop, tmpPath, &error);
                    if (!image.isNull()) {
                        QFile::remove(cachePath);
                        QFile::rename(tmpPath, cachePath);
                    }
                } else {
                    image = makeImageThumbnail(m_path, m_bucket, m_crop);
                    if (image.isNull()) {
                        error = QStringLiteral("Failed to load image");
                    } else if (image.save(tmpPath, "JPG", 85)) {
                        QFile::remove(cachePath);
                        QFile::rename(tmpPath, cachePath);
                    } else {
                        QFile::remove(tmpPath);
                    }
                }
            }
        }

        {
            QMutexLocker locker(&m_state->mutex);
            m_state->image = image;
            m_state->error = error;
            if (m_state->response && !m_state->cancelled.load()) {
                QMetaObject::invokeMethod(m_state->response, "onJobFinished", Qt::QueuedConnection);
            }
        }
    }

private:
    QSharedPointer<LocalThumbnailResponse::State> m_state;
    QString m_path;
    bool m_crop;
    int m_bucket;
};

} // namespace

LocalThumbnailResponse::LocalThumbnailResponse(const QString &path, bool crop, const QSize &requestedSize)
    : m_state(new State)
    , m_finished(false)
{
    m_state->response = this;
    if (path.isEmpty()) {
        m_state->error = QStringLiteral("Invalid thumbnail request");
        m_finished = true;
        QMetaObject::invokeMethod(this, "finished", Qt::QueuedConnection);
        return;
    }
    thumbnailPool()->start(new ThumbnailJob(m_state, path, crop, bucketFor(requestedSize)));
}

LocalThumbnailResponse::~LocalThumbnailResponse()
{
    QMutexLocker locker(&m_state->mutex);
    m_state->cancelled.store(1);
    m_state->response = nullptr;
}

void LocalThumbnailResponse::onJobFinished()
{
    if (m_finished) return;
    m_finished = true;
    emit finished();
}

QQuickTextureFactory *LocalThumbnailResponse::textureFactory() const
{
    QMutexLocker locker(&m_state->mutex);
    return QQuickTextureFactory::textureFactoryForImage(m_state->image);
}

QString LocalThumbnailResponse::errorString() const
{
    QMutexLocker locker(&m_state->mutex);
    return m_state->error;
}

void LocalThumbnailResponse::cancel()
{
    {
        QMutexLocker locker(&m_state->mutex);
        m_state->cancelled.store(1);
        m_state->response = nullptr;
    }
    if (!m_finished) {
        m_finished = true;
        emit finished();
    }
}

QQuickImageResponse *LocalThumbnailProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    const int slash = id.indexOf(QLatin1Char('/'));
    QString mode = slash < 0 ? QString() : id.left(slash);
    QString path = slash < 0 ? id : id.mid(slash + 1);

    if (path.startsWith(QStringLiteral("file://"))) {
        path = path.mid(7);
    }
    path = QUrl::fromPercentEncoding(path.toUtf8());
    if (path.startsWith(QStringLiteral("file://"))) {
        path = path.mid(7);
    }

    const bool crop = (mode == QLatin1String("crop"));
    return new LocalThumbnailResponse(path, crop, requestedSize);
}
