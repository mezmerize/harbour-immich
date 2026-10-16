#include "backgroundtasks.h"
#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QVariantMap>
#include <QDateTime>

ChecksumTask::ChecksumTask(const QStringList &paths, quint64 token, QObject *parent)
    : QObject(parent)
    , m_paths(paths)
    , m_token(token)
{
    setAutoDelete(false);
}

void ChecksumTask::run()
{
    QVariantList entries;
    for (const QString &path : m_paths) {
        QFileInfo fi(path);
        if (!fi.exists())
            continue;

        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
            continue;
        QCryptographicHash hash(QCryptographicHash::Sha1);
        if (!hash.addData(&file)) {
            file.close();
            continue;
        }
        file.close();

        QVariantMap entry;
        entry[QStringLiteral("path")] = path;
        entry[QStringLiteral("checksum")] = QString::fromLatin1(hash.result().toHex());
        entry[QStringLiteral("size")] = fi.size();
        entry[QStringLiteral("modified")] = fi.lastModified().toMSecsSinceEpoch();
        entries.append(entry);
    }
    emit completed(m_token, entries);
    deleteLater();
}

MediaScanTask::MediaScanTask(const QStringList &folders, const QSet<QString> &extensions, qint64 fromDateMs, quint64 token, QObject *parent)
    : QObject(parent)
    , m_folders(folders)
    , m_extensions(extensions)
    , m_fromDateMs(fromDateMs)
    , m_token(token)
{
    setAutoDelete(false);
}

void MediaScanTask::run()
{
    QVariantList files;
    QSet<QString> seen;
    for (const QString &folder : m_folders) {
        QDir dir(folder);
        if (!dir.exists())
            continue;

        QDirIterator it(folder, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            QFileInfo fi = it.fileInfo();
            if (!m_extensions.contains(fi.suffix().toLower()))
                continue;
            if (seen.contains(fi.absoluteFilePath()))
                continue;
            seen.insert(fi.absoluteFilePath());

            qint64 fileMod = fi.lastModified().toMSecsSinceEpoch();
            if (m_fromDateMs > 0 && fileMod < m_fromDateMs)
                continue;

            QVariantMap entry;
            entry[QStringLiteral("path")] = fi.absoluteFilePath();
            entry[QStringLiteral("size")] = fi.size();
            entry[QStringLiteral("modified")] = fileMod;
            files.append(entry);
        }
    }
    emit completed(m_token, files);
    deleteLater();
}
