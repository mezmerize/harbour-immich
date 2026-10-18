#include "backupdatabase.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QStandardPaths>
#include <QDir>
#include <QFileInfo>
#include <QDebug>
#include <QDateTime>

BackupDatabase::BackupDatabase(QObject *parent)
    : QObject(parent)
{
}

BackupDatabase::~BackupDatabase()
{
    if (m_db.isOpen()) {
        m_db.close();
    }
}

bool BackupDatabase::initialize()
{
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataDir);
    QString dbPath = dataDir + "/backup.db";

    m_db = QSqlDatabase::addDatabase("QSQLITE", "backup_connection");
    m_db.setDatabaseName(dbPath);

    if (!m_db.open()) {
        qWarning() << "BackupDatabase: Failed to open database:" << m_db.lastError().text();
        return false;
    }

    qInfo() << "BackupDatabase: Opened database at" << dbPath;

    QSqlQuery pragma(m_db);
    pragma.exec("PRAGMA journal_mode=WAL");
    pragma.exec("PRAGMA synchronous=NORMAL");

    if (!createTables()) {
        return false;
    }

    // Remove DeletedOnServer status
    QSqlQuery(m_db).exec("DELETE FROM backup_files WHERE status = 4");
    return true;
}

bool BackupDatabase::createTables()
{
    QSqlQuery query(m_db);

    bool ok = query.exec("CREATE TABLE IF NOT EXISTS backup_files ("
       " id INTEGER PRIMARY KEY AUTOINCREMENT,"
       " file_path TEXT UNIQUE NOT NULL,"
       " file_name TEXT NOT NULL,"
       " file_size INTEGER NOT NULL,"
       " file_modified INTEGER NOT NULL,"
       " device_asset_id TEXT NOT NULL,"
       " remote_asset_id TEXT DEFAULT '',"
       " status INTEGER DEFAULT 0,"
       " last_attempt INTEGER DEFAULT 0,"
       " error_message TEXT DEFAULT '',"
       " created_at INTEGER NOT NULL"
       ")"
   );

    if (!ok) {
        qWarning() << "BackupDatabase: Failed to create table:" << query.lastError().text();
        return false;
    }

    // Indexes for common queries
    query.exec("CREATE INDEX IF NOT EXISTS idx_status ON backup_files(status)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_remote_asset ON backup_files(remote_asset_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_device_asset ON backup_files(device_asset_id)");

    qInfo() << "BackupDatabase: Tables initialized";
    return true;
}

QString BackupDatabase::makeDeviceAssetId(const QString &fileName, qint64 lastModifiedMs)
{
    return QString("%1-%2").arg(fileName).arg(lastModifiedMs);
}

bool BackupDatabase::addFile(const QString &filePath, qint64 fileSize, qint64 fileModified)
{
    QFileInfo fi(filePath);
    QString deviceAssetId = makeDeviceAssetId(fi.fileName(), fileModified);

    QSqlQuery query(m_db);
    query.prepare("INSERT OR IGNORE INTO backup_files"
       " (file_path, file_name, file_size, file_modified, device_asset_id, status, created_at)"
       " VALUES (:path, :name, :size, :modified, :deviceId, :status, :created)"
   );
    query.bindValue(":path", filePath);
    query.bindValue(":name", fi.fileName());
    query.bindValue(":size", fileSize);
    query.bindValue(":modified", fileModified);
    query.bindValue(":deviceId", deviceAssetId);
    query.bindValue(":status", static_cast<int>(Pending));
    query.bindValue(":created", QDateTime::currentMSecsSinceEpoch());

    if (!query.exec()) {
        qWarning() << "BackupDatabase: Failed to add file:" << query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}

bool BackupDatabase::hasFile(const QString &filePath) const
{
    QSqlQuery query(m_db);
    query.prepare("SELECT 1 FROM backup_files WHERE file_path = :path LIMIT 1");
    query.bindValue(":path", filePath);
    query.exec();
    return query.next();
}

bool BackupDatabase::hasFileChanged(const QString &filePath, qint64 fileSize, qint64 fileModified) const
{
    QSqlQuery query(m_db);
    query.prepare("SELECT file_size, file_modified FROM backup_files WHERE file_path = :path LIMIT 1");
    query.bindValue(":path", filePath);
    query.exec();
    if (query.next()) {
        return query.value(0).toLongLong() != fileSize || query.value(1).toLongLong() != fileModified;
    }
    return true; // Not found = treat as changed
}

bool BackupDatabase::removeFile(const QString &filePath)
{
    QSqlQuery query(m_db);
    query.prepare("DELETE FROM backup_files WHERE file_path = :path");
    query.bindValue(":path", filePath);
    return query.exec();
}

static void readRecords(QSqlQuery &query, QHash<QString, BackupDatabase::FileRecord> &records)
{
    while (query.next()) {
        BackupDatabase::FileRecord r;
        r.size = query.value(1).toLongLong();
        r.modified = query.value(2).toLongLong();
        r.status = query.value(3).toInt();
        r.remoteAssetId = query.value(4).toString();
        records.insert(query.value(0).toString(), r);
    }
}

QHash<QString, BackupDatabase::FileRecord> BackupDatabase::allRecords() const
{
    QHash<QString, FileRecord> records;
    QSqlQuery query(m_db);
    query.exec("SELECT file_path, file_size, file_modified, status, remote_asset_id FROM backup_files");
    readRecords(query, records);
    return records;
}

QHash<QString, BackupDatabase::FileRecord> BackupDatabase::recordsWithPrefix(const QString &pathPrefix) const
{
    QHash<QString, FileRecord> records;
    QSqlQuery query(m_db);
    query.prepare("SELECT file_path, file_size, file_modified, status, remote_asset_id FROM backup_files WHERE file_path >= :lo AND file_path < :hi");
    query.bindValue(":lo", pathPrefix);
    query.bindValue(":hi", pathPrefix + QLatin1Char('0'));
    query.exec();
    readRecords(query, records);
    return records;
}

bool BackupDatabase::setStatus(const QString &filePath, Status status, const QString &remoteAssetId, const QString &errorMessage)
{
    QSqlQuery query(m_db);

    if (!remoteAssetId.isEmpty()) {
        query.prepare("UPDATE backup_files SET status = :status, remote_asset_id = :remoteId, last_attempt = :attempt, error_message = :error WHERE file_path = :path");
        query.bindValue(":remoteId", remoteAssetId);
    } else {
        query.prepare("UPDATE backup_files SET status = :status, last_attempt = :attempt, error_message = :error WHERE file_path = :path");
    }

    query.bindValue(":status", static_cast<int>(status));
    query.bindValue(":attempt", QDateTime::currentMSecsSinceEpoch());
    query.bindValue(":error", errorMessage);
    query.bindValue(":path", filePath);

    if (!query.exec()) {
        qWarning() << "BackupDatabase: Failed to update status:" << query.lastError().text();
        return false;
    }
    return true;
}

BackupDatabase::Status BackupDatabase::fileStatus(const QString &filePath) const
{
    QSqlQuery query(m_db);
    query.prepare("SELECT status FROM backup_files WHERE file_path = :path LIMIT 1");
    query.bindValue(":path", filePath);
    query.exec();
    if (query.next()) {
        return static_cast<Status>(query.value(0).toInt());
    }
    return Pending;
}

QStringList BackupDatabase::pendingFiles(int limit) const
{
    QStringList files;
    QSqlQuery query(m_db);
    query.prepare("SELECT file_path FROM backup_files WHERE status = :status ORDER BY created_at ASC LIMIT :limit");
    query.bindValue(":status", static_cast<int>(Pending));
    query.bindValue(":limit", limit);
    query.exec();
    while (query.next()) {
        files.append(query.value(0).toString());
    }
    return files;
}

QStringList BackupDatabase::failedFiles() const
{
    QStringList files;
    QSqlQuery query(m_db);
    query.prepare("SELECT file_path FROM backup_files WHERE status = :status ORDER BY last_attempt ASC");
    query.bindValue(":status", static_cast<int>(Failed));
    query.exec();
    while (query.next()) {
        files.append(query.value(0).toString());
    }
    return files;
}

QStringList BackupDatabase::allFilePaths() const
{
    QStringList files;
    QSqlQuery query(m_db);
    query.exec("SELECT file_path FROM backup_files");
    while (query.next()) {
        files.append(query.value(0).toString());
    }
    return files;
}

int BackupDatabase::countByStatus(Status status) const
{
    QSqlQuery query(m_db);
    query.prepare("SELECT COUNT(*) FROM backup_files WHERE status = :status");
    query.bindValue(":status", static_cast<int>(status));
    query.exec();
    if (query.next()) {
        return query.value(0).toInt();
    }
    return 0;
}

int BackupDatabase::totalTrackedFiles() const
{
    QSqlQuery query(m_db);
    query.exec("SELECT COUNT(*) FROM backup_files");
    if (query.next()) {
        return query.value(0).toInt();
    }
    return 0;
}

QSet<QString> BackupDatabase::allBackedUpRemoteAssetIds() const
{
    QSet<QString> ids;
    QSqlQuery query(m_db);
    query.prepare("SELECT remote_asset_id FROM backup_files WHERE status = :status AND remote_asset_id != ''");
    query.bindValue(":status", static_cast<int>(BackedUp));
    query.exec();
    while (query.next()) {
        ids.insert(query.value(0).toString());
    }
    return ids;
}

QString BackupDatabase::remoteAssetIdForFile(const QString &filePath) const
{
    QSqlQuery query(m_db);
    query.prepare("SELECT remote_asset_id FROM backup_files WHERE file_path = :path LIMIT 1");
    query.bindValue(":path", filePath);
    query.exec();
    if (query.next()) {
        return query.value(0).toString();
    }
    return QString();
}

bool BackupDatabase::registerManualUpload(const QString &filePath, qint64 fileSize, qint64 fileModified, const QString &remoteAssetId)
{
    QFileInfo fi(filePath);
    QString deviceAssetId = makeDeviceAssetId(fi.fileName(), fileModified);

    QSqlQuery query(m_db);
    query.prepare("INSERT OR REPLACE INTO backup_files"
       " (file_path, file_name, file_size, file_modified, device_asset_id,"
       " remote_asset_id, status, last_attempt, created_at)"
       " VALUES (:path, :name, :size, :modified, :deviceId, :remoteId, :status, :attempt, :created)"
   );
    query.bindValue(":path", filePath);
    query.bindValue(":name", fi.fileName());
    query.bindValue(":size", fileSize);
    query.bindValue(":modified", fileModified);
    query.bindValue(":deviceId", deviceAssetId);
    query.bindValue(":remoteId", remoteAssetId);
    query.bindValue(":status", static_cast<int>(BackedUp));
    query.bindValue(":attempt", QDateTime::currentMSecsSinceEpoch());
    query.bindValue(":created", QDateTime::currentMSecsSinceEpoch());

    if (!query.exec()) {
        qWarning() << "BackupDatabase: Failed to register manual upload:" << query.lastError().text();
        return false;
    }
    return true;
}

bool BackupDatabase::removeByRemoteAssetIds(const QStringList &ids)
{
    if (ids.isEmpty()) return false;
    m_db.transaction();
    bool removed = false;
    QSqlQuery query(m_db);
    query.prepare("DELETE FROM backup_files WHERE remote_asset_id = :id");
    for (const QString &id : ids) {
        query.bindValue(":id", id);
        query.exec();
        removed = removed || query.numRowsAffected() > 0;
        query.finish();
    }
    m_db.commit();
    return removed;
}

int BackupDatabase::removeMissingRemoteAssets(const QSet<QString> &existingIds, qint64 olderThanMs)
{
    m_db.transaction();
    QSqlQuery query(m_db);
    query.exec(QStringLiteral("CREATE TEMP TABLE IF NOT EXISTS recon_ids (id TEXT PRIMARY KEY)"));
    query.exec(QStringLiteral("DELETE FROM recon_ids"));
    query.prepare(QStringLiteral("INSERT OR IGNORE INTO recon_ids (id) VALUES (?)"));
    for (const QString &id : existingIds) {
        query.addBindValue(id);
        query.exec();
        query.finish();
    }

    QSqlQuery del(m_db);
    del.prepare(QStringLiteral("DELETE FROM backup_files WHERE status = :status AND remote_asset_id != '' AND remote_asset_id NOT IN (SELECT id FROM recon_ids) AND last_attempt < :older"));
    del.bindValue(QStringLiteral(":status"), static_cast<int>(BackedUp));
    del.bindValue(QStringLiteral(":older"), olderThanMs);
    if (!del.exec()) {
        qWarning() << "BackupDatabase: reconciliation delete failed:" << del.lastError().text();
        m_db.rollback();
        return 0;
    }
    const int removed = del.numRowsAffected();
    query.exec(QStringLiteral("DROP TABLE recon_ids"));
    m_db.commit();
    return removed;
}

bool BackupDatabase::resetFile(const QString &filePath)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE backup_files SET status = :status, error_message = '' WHERE file_path = :path");
    query.bindValue(":status", static_cast<int>(Pending));
    query.bindValue(":path", filePath);
    return query.exec();
}

int BackupDatabase::resetStuckUploads()
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE backup_files SET status = :status WHERE status = :uploading");
    query.bindValue(":status", static_cast<int>(Pending));
    query.bindValue(":uploading", static_cast<int>(Uploading));
    query.exec();
    return query.numRowsAffected();
}

bool BackupDatabase::clearAll()
{
    QSqlQuery query(m_db);
    if (!query.exec("DELETE FROM backup_files")) {
        qWarning() << "BackupDatabase: Failed to clear database:" << query.lastError().text();
        return false;
    }
    qInfo() << "BackupDatabase: Database cleared";
    return true;
}

bool BackupDatabase::addFileAsBackedUp(const QString &filePath, qint64 fileSize, qint64 fileModified, const QString &remoteAssetId)
{
    QFileInfo fi(filePath);
    QString deviceAssetId = makeDeviceAssetId(fi.fileName(), fileModified);

    QSqlQuery query(m_db);
    query.prepare("INSERT OR IGNORE INTO backup_files"
       " (file_path, file_name, file_size, file_modified, device_asset_id,"
       " remote_asset_id, status, last_attempt, created_at)"
       " VALUES (:path, :name, :size, :modified, :deviceId, :remoteId, :status, :attempt, :created)"
   );
    query.bindValue(":path", filePath);
    query.bindValue(":name", fi.fileName());
    query.bindValue(":size", fileSize);
    query.bindValue(":modified", fileModified);
    query.bindValue(":deviceId", deviceAssetId);
    query.bindValue(":remoteId", remoteAssetId.isEmpty() ? QString("") : remoteAssetId);
    query.bindValue(":status", static_cast<int>(BackedUp));
    query.bindValue(":attempt", QDateTime::currentMSecsSinceEpoch());
    query.bindValue(":created", QDateTime::currentMSecsSinceEpoch());

    if (!query.exec()) {
        qWarning() << "BackupDatabase: Failed to add file as backed up:" << query.lastError().text();
        return false;
    }
    return query.numRowsAffected() > 0;
}
