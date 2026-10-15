#include "exifreader.h"
#include "exifparser.h"

#include <QFile>
#include <QDateTime>
#include <QtGlobal>

namespace ExifReader {

QVariantMap read(const QString &path)
{
    QVariantMap map;

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return map;
    }
    const QByteArray data = file.read(256 * 1024);
    if (data.isEmpty()) {
        return map;
    }

    ExifData ex;
    if (!parseJpegExif(reinterpret_cast<const unsigned char *>(data.constData()), static_cast<size_t>(data.size()), ex)) {
        return map;
    }

    if (!ex.make.empty()) {
        map[QStringLiteral("make")] = QString::fromUtf8(ex.make.c_str());
    }
    if (!ex.model.empty()) {
        map[QStringLiteral("model")] = QString::fromUtf8(ex.model.c_str());
    }
    if (!ex.description.empty()) {
        map[QStringLiteral("description")] = QString::fromUtf8(ex.description.c_str());
    }
    if (!ex.lensModel.empty()) {
        map[QStringLiteral("lensModel")] = QString::fromUtf8(ex.lensModel.c_str());
    }
    if (ex.orientation > 0) {
        map[QStringLiteral("orientation")] = QString::number(ex.orientation);
    }
    if (!ex.dateTimeOriginal.empty()) {
        const QString raw = QString::fromUtf8(ex.dateTimeOriginal.c_str());
        const QDateTime dt = QDateTime::fromString(raw, QStringLiteral("yyyy:MM:dd HH:mm:ss"));
        if (dt.isValid()) {
            QString value = dt.toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss"));
            if (!ex.offsetTimeOriginal.empty()) {
                value += QString::fromUtf8(ex.offsetTimeOriginal.c_str()).trimmed();
            }
            map[QStringLiteral("dateTimeOriginal")] = value;
        }
    }
    if (ex.exposureTime > 0) {
        if (ex.exposureTime < 1) {
            map[QStringLiteral("exposureTime")] = QStringLiteral("1/") + QString::number(qRound(1.0 / ex.exposureTime));
        } else {
            map[QStringLiteral("exposureTime")] = QString::number(ex.exposureTime);
        }
    }
    if (ex.fNumber > 0) {
        map[QStringLiteral("fNumber")] = qRound(ex.fNumber * 10.0) / 10.0;
    }
    if (ex.iso > 0) {
        map[QStringLiteral("iso")] = ex.iso;
    }
    if (ex.focalLength > 0) {
        map[QStringLiteral("focalLength")] = qRound(ex.focalLength * 10.0) / 10.0;
    }
    if (ex.hasGps) {
        map[QStringLiteral("latitude")] = ex.latitude;
        map[QStringLiteral("longitude")] = ex.longitude;
    }
    if (ex.pixelX > 0) {
        map[QStringLiteral("exifImageWidth")] = ex.pixelX;
    }
    if (ex.pixelY > 0) {
        map[QStringLiteral("exifImageHeight")] = ex.pixelY;
    }
    return map;
}

} // namespace ExifReader
