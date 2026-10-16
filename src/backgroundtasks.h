#ifndef BACKGROUNDTASKS_H
#define BACKGROUNDTASKS_H

#include <QObject>
#include <QRunnable>
#include <QSet>
#include <QStringList>
#include <QVariantList>

class ChecksumTask : public QObject, public QRunnable
{
    Q_OBJECT

public:
    ChecksumTask(const QStringList &paths, quint64 token, QObject *parent = nullptr);
    void run() override;

signals:
    void completed(quint64 token, const QVariantList &entries);

private:
    QStringList m_paths;
    quint64 m_token;
};

class MediaScanTask : public QObject, public QRunnable
{
    Q_OBJECT

public:
    MediaScanTask(const QStringList &folders, const QSet<QString> &extensions, qint64 fromDateMs, quint64 token, QObject *parent = nullptr);
    void run() override;

signals:
    void completed(quint64 token, const QVariantList &files);

private:
    QStringList m_folders;
    QSet<QString> m_extensions;
    qint64 m_fromDateMs;
    quint64 m_token;
};

#endif // BACKGROUNDTASKS_H
