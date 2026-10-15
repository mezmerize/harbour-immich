#ifndef EXIFREADER_H
#define EXIFREADER_H

#include <QString>
#include <QVariantMap>

namespace ExifReader {
QVariantMap read(const QString &path);
}

#endif // EXIFREADER_H
