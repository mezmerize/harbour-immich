#include "localmediaindex.h"
#include "backupmanager.h"
#include "settingsmanager.h"
#include "assetdatabase.h"
#include "backgroundtasks.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QSqlDatabase>
#include <QFileInfo>
#include <QDateTime>
#include <QThreadPool>
#include <QDebug>

namespace {
const int HashBatchSize = 200;
}

LocalMediaIndex::LocalMediaIndex(BackupManager *backupManager, SettingsManager *settings, AssetDatabase *db, QObject *parent)
    : QObject(parent)
    , m_backup(backupManager)
    , m_settings(settings)
    , m_db(db)
{
}

void LocalMediaIndex::scan()
{
    if (!m_db || !m_db->db().isOpen()) {
        return;
    }
    if (m_scanning) {
        m_scanQueued = true;
        return;
    }
    const QStringList folders = m_settings ? m_settings->backupFolders() : QStringList();
    if (folders.isEmpty() || !m_backup || (m_settings && !m_settings->showDeviceMediaOnTimeline())) {
        // No watched folders
        if (m_db->tableHasRows(QStringLiteral("local_asset"))) {
            QSqlQuery q(m_db->db());
            q.exec(QStringLiteral("DELETE FROM local_asset"));
            m_db->notifyChanged(AssetDatabase::LocalAssets);
        }
        return;
    }

    m_scanning = true;
    emit scanningChanged();

    const quint64 token = ++m_scanToken;
    MediaScanTask *task = new MediaScanTask(folders, m_backup->mediaExtensions(), 0, token);
    connect(task, &MediaScanTask::completed, this, &LocalMediaIndex::onScanDone);
    QThreadPool::globalInstance()->start(task);
}

void LocalMediaIndex::onScanDone(quint64 token, const QVariantList &files)
{
    if (token != m_scanToken) {
        return;
    }
    applyScan(files);
    hashNextBatch();
}

void LocalMediaIndex::applyScan(const QVariantList &files)
{
    QSqlDatabase db = m_db->db();

    QHash<QString, QPair<qint64, qint64>> existing;
    {
        QSqlQuery q(db);
        if (q.exec(QStringLiteral("SELECT path, size, mtime FROM local_asset"))) {
            while (q.next()) {
                existing.insert(q.value(0).toString(), qMakePair(q.value(1).toLongLong(), q.value(2).toLongLong()));
            }
        }
    }

    QSet<QString> seen;
    db.transaction();
    {
        QSqlQuery insert(db);
        insert.prepare(QStringLiteral("INSERT OR REPLACE INTO local_asset (id, path, name, type, checksum, size, mtime, created_at) VALUES (?,?,?,?,NULL,?,?,?)"));
        QSqlQuery update(db);

        for (const QVariant &v : files) {
            const QVariantMap f = v.toMap();
            const QString path = f.value(QStringLiteral("path")).toString();
            if (path.isEmpty()) {
                continue;
            }
            seen.insert(path);
            const qint64 size = f.value(QStringLiteral("size")).toLongLong();
            const qint64 mtime = f.value(QStringLiteral("modified")).toLongLong();

            const auto it = existing.constFind(path);
            if (it != existing.constEnd() && it->first == size && it->second == mtime) {
                continue;
            }

            insert.addBindValue(path); // id = path
            insert.addBindValue(path);
            insert.addBindValue(QFileInfo(path).fileName());
            insert.addBindValue(m_backup->isVideoFilePath(path) ? QStringLiteral("VIDEO") : QStringLiteral("IMAGE"));
            insert.addBindValue(size);
            insert.addBindValue(mtime);
            insert.addBindValue(QDateTime::fromMSecsSinceEpoch(mtime).toUTC().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'")));
            if (!insert.exec()) {
                qWarning() << "LocalMediaIndex: Upsert failed:" << insert.lastError().text();
            }
            insert.finish();
            m_indexDirty = true;
        }

        // Remove rows for files that are no longer in watched folders
        update.prepare(QStringLiteral("DELETE FROM local_asset WHERE path = ?"));
        for (auto it = existing.constBegin(); it != existing.constEnd(); ++it) {
            if (!seen.contains(it.key())) {
                update.addBindValue(it.key());
                update.exec();
                update.finish();
                m_indexDirty = true;
            }
        }
    }
    db.commit();
}

void LocalMediaIndex::hashNextBatch()
{
    if (m_pendingHash.isEmpty()) {
        QSqlQuery q(m_db->db());
        if (q.exec(QStringLiteral("SELECT path FROM local_asset WHERE checksum IS NULL"))) {
            while (q.next()) {
                m_pendingHash.append(q.value(0).toString());
            }
        }
    }

    if (m_pendingHash.isEmpty()) {
        finishScan();
        return;
    }

    const QStringList batch = m_pendingHash.mid(0, HashBatchSize);
    m_pendingHash = m_pendingHash.mid(HashBatchSize);

    const quint64 token = ++m_hashToken;
    ChecksumTask *task = new ChecksumTask(batch, token);
    connect(task, &ChecksumTask::completed, this, &LocalMediaIndex::onHashesDone);
    QThreadPool::globalInstance()->start(task);
}

void LocalMediaIndex::onHashesDone(quint64 token, const QVariantList &entries)
{
    if (token != m_hashToken) {
        return;
    }

    QSqlDatabase db = m_db->db();
    db.transaction();
    {
        QSqlQuery q(db);
        q.prepare(QStringLiteral("UPDATE local_asset SET checksum = ? WHERE path = ?"));
        for (const QVariant &v : entries) {
            const QVariantMap e = v.toMap();
            const QString hex = e.value(QStringLiteral("checksum")).toString();
            q.addBindValue(QString::fromLatin1(QByteArray::fromHex(hex.toLatin1()).toBase64()));
            q.addBindValue(e.value(QStringLiteral("path")).toString());
            q.exec();
            q.finish();
        }
    }
    db.commit();
    m_indexDirty = true;

    hashNextBatch();
}

void LocalMediaIndex::finishScan()
{
    m_scanning = false;
    emit scanningChanged();
    if (m_scanQueued) {
        m_scanQueued = false;
        scan();
        return;
    }
    if (m_indexDirty) {
        m_indexDirty = false;
        m_db->notifyChanged(AssetDatabase::LocalAssets);
    }
}
