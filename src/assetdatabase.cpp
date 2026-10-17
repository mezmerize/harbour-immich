#include "assetdatabase.h"
#include "exifreader.h"
#include <QThread>
#include <QMetaObject>
#include <QSqlQuery>
#include <QSqlError>
#include <QStandardPaths>
#include <QDir>
#include <QDebug>
#include <QVariant>
#include <QSet>
#include <QFileInfo>
#include <QDateTime>
#include <QImageReader>
#include <QMimeDatabase>

AssetDatabase *AssetDatabase::s_instance = nullptr;

AssetDatabase::AssetDatabase(QObject *parent)
    : QObject(parent)
{
    s_instance = this;
}

AssetDatabase::~AssetDatabase()
{
    if (m_readerThread) {
        m_readerThread->quit();
        m_readerThread->wait();
        delete m_readerThread;
        m_readerThread = nullptr;
    }
    if (m_db.isOpen()) {
        m_db.close();
    }
    m_db = QSqlDatabase();
    QSqlDatabase::removeDatabase(QStringLiteral("catalog_connection"));
    if (s_instance == this) {
        s_instance = nullptr;
    }
}

bool AssetDatabase::initialize()
{
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataDir);
    QString dbPath = dataDir + QStringLiteral("/catalog.db");

    m_db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), QStringLiteral("catalog_connection"));
    m_db.setDatabaseName(dbPath);

    if (!m_db.open()) {
        qWarning() << "AssetDatabase: Failed to open database:" << m_db.lastError().text();
        return false;
    }

    qInfo() << "AssetDatabase: Opened catalog at" << dbPath;

    QSqlQuery pragma(m_db);
    bool fresh = true;
    {
        QSqlQuery t(m_db);
        if (t.exec(QStringLiteral("SELECT 1 FROM sqlite_master WHERE type='table' LIMIT 1")) && t.next()) {
            fresh = false;
        }
    }
    if (fresh) {
        pragma.exec(QStringLiteral("PRAGMA auto_vacuum=INCREMENTAL"));
    }
    pragma.exec(QStringLiteral("PRAGMA journal_mode=WAL"));
    pragma.exec(QStringLiteral("PRAGMA synchronous=NORMAL"));
    pragma.exec(QStringLiteral("PRAGMA cache_size=-8192"));
    pragma.exec(QStringLiteral("PRAGMA foreign_keys=ON"));
    pragma.exec(QStringLiteral("PRAGMA busy_timeout=5000"));

    return createSchema(fresh);
}

QSqlDatabase AssetDatabase::db() const
{
    if (QThread::currentThread() == thread()) {
        return m_db;
    }
    const QString name = QStringLiteral("catalog-%1").arg(reinterpret_cast<quintptr>(QThread::currentThreadId()));
    if (!QSqlDatabase::contains(name)) {
        QSqlDatabase conn = QSqlDatabase::cloneDatabase(m_db, name);
        if (!conn.open()) {
            qWarning() << "AssetDatabase: Worker connection failed:" << conn.lastError().text();
        } else {
            QSqlQuery q(conn);
            q.exec(QStringLiteral("PRAGMA busy_timeout=5000"));
            q.exec(QStringLiteral("PRAGMA synchronous=NORMAL"));
            q.exec(QStringLiteral("PRAGMA cache_size=-8192"));
        }
    }
    return QSqlDatabase::database(name);
}

qint64 AssetDatabase::tableRowCount(const QString &table) const
{
    QSqlQuery q(db());
    if (!q.exec(QStringLiteral("SELECT COUNT(*) FROM \"%1\"").arg(table))) {
        return -1;
    }
    return q.next() ? q.value(0).toLongLong() : -1;
}

bool AssetDatabase::tableHasRows(const QString &table) const
{
    QSqlQuery q(db());
    if (!q.exec(QStringLiteral("SELECT 1 FROM \"%1\" LIMIT 1").arg(table))) {
        return false;
    }
    return q.next();
}

bool AssetDatabase::clearSyncedData(bool reclaimSpace)
{
    static const char *tables[] = {
        "remote_asset", "remote_asset_exif", "stack",
        "sync_user", "auth_user", "partner",
        "album", "album_user", "album_to_asset",
        "person", "asset_face", "memory", "memory_to_asset",
        "asset_edit", "asset_metadata", "asset_ocr", "user_metadata"
    };
    QSqlDatabase conn = db();
    if (!conn.transaction()) {
        return false;
    }
    QSqlQuery q(conn);
    for (const char *table : tables) {
        if (!q.exec(QStringLiteral("DELETE FROM %1").arg(QString::fromLatin1(table)))) {
            qWarning() << "AssetDatabase: Failed clearSyncedData on" << table << q.lastError().text();
            conn.rollback();
            return false;
        }
    }
    q.exec(QStringLiteral("DELETE FROM sync_meta WHERE key IN ('last_sync_at','current_user_id','catalog_server','catalog_user','catalog_session')"));
    if (!conn.commit()) {
        conn.rollback();
        return false;
    }
    if (reclaimSpace) {
        q.exec(QStringLiteral("PRAGMA incremental_vacuum"));
    }
    notifyChanged(AllTables);
    return true;
}

QString AssetDatabase::metaValue(const QString &key) const
{
    QSqlQuery q(db());
    q.prepare(QStringLiteral("SELECT value FROM sync_meta WHERE key = ?"));
    q.addBindValue(key);
    if (q.exec() && q.next()) {
        return q.value(0).toString();
    }
    return QString();
}

bool AssetDatabase::setMetaValue(const QString &key, const QString &value)
{
    QSqlQuery q(db());
    q.prepare(QStringLiteral("INSERT OR REPLACE INTO sync_meta (key, value) VALUES (?, ?)"));
    q.addBindValue(key);
    q.addBindValue(value);
    return q.exec();
}

QSet<QString> AssetDatabase::ownRemoteAssetIds() const
{
    QSet<QString> ids;
    QSqlQuery q(db());
    q.exec(QStringLiteral("SELECT id FROM remote_asset WHERE owner_id = (SELECT value FROM sync_meta WHERE key = 'current_user_id')"));
    while (q.next()) {
        ids.insert(q.value(0).toString());
    }
    return ids;
}

QVariantMap AssetDatabase::localAssetInfo(const QString &path) const
{
    QVariantMap info;
    const QFileInfo fi(path);

    QString name, createdAt, type;
    qint64 size = -1, width = -1, height = -1;

    QSqlQuery q(db());
    q.prepare(QStringLiteral("SELECT name, created_at, size, width, height, type FROM local_asset WHERE path = ?"));
    q.addBindValue(path);
    if (q.exec() && q.next()) {
        name = q.value(0).toString();
        createdAt = q.value(1).toString();
        if (!q.value(2).isNull()) size = q.value(2).toLongLong();
        if (!q.value(3).isNull()) width = q.value(3).toLongLong();
        if (!q.value(4).isNull()) height = q.value(4).toLongLong();
        type = q.value(5).toString();
    }

    // Fall back to the filesystem for not indexed
    if (name.isEmpty()) {
        name = fi.fileName();
    }
    if (size < 0) {
        size = fi.size();
    }
    if (createdAt.isEmpty()) {
        createdAt = fi.lastModified().toUTC().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'"));
    }
    if (type.isEmpty()) {
        type = QMimeDatabase().mimeTypeForFile(fi).name().startsWith(QLatin1String("video/")) ? QStringLiteral("VIDEO") : QStringLiteral("IMAGE");
    }
    if ((width < 0 || height < 0) && type != QLatin1String("VIDEO")) {
        // Header read only
        const QSize dims = QImageReader(path).size();
        if (dims.isValid()) {
            width = dims.width();
            height = dims.height();
        }
    }

    info[QStringLiteral("originalFileName")] = name;
    info[QStringLiteral("fileCreatedAt")] = createdAt;
    info[QStringLiteral("fileModifiedAt")] = fi.lastModified().toUTC().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'"));
    info[QStringLiteral("type")] = type;

    QVariantMap exif;
    if (type != QLatin1String("VIDEO")) {
        exif = ExifReader::read(path);
    }
    if (width >= 0)
        exif[QStringLiteral("exifImageWidth")] = width;
    if (height >= 0)
        exif[QStringLiteral("exifImageHeight")] = height;
    const int orientation = exif.value(QStringLiteral("orientation")).toString().toInt();
    if (orientation >= 5 && orientation <= 8 && exif.contains(QStringLiteral("exifImageWidth")) && exif.contains(QStringLiteral("exifImageHeight"))) {
        const QVariant w = exif.value(QStringLiteral("exifImageWidth"));
        exif[QStringLiteral("exifImageWidth")] = exif.value(QStringLiteral("exifImageHeight"));
        exif[QStringLiteral("exifImageHeight")] = w;
    }
    if (size >= 0)
        exif[QStringLiteral("fileSizeInByte")] = size;
    if (exif.contains(QStringLiteral("dateTimeOriginal"))) {
        info[QStringLiteral("localDateTime")] = exif.value(QStringLiteral("dateTimeOriginal"));
    }
    if (!exif.isEmpty()) {
        info[QStringLiteral("exifInfo")] = exif;
    }
    return info;
}

void AssetDatabase::patchRemoteAssets(const QStringList &ids, const QString &column, const QVariant &value)
{
    static const QSet<QString> allowed = {
        QStringLiteral("is_favorite"),
        QStringLiteral("visibility"),
        QStringLiteral("deleted_at"),
        QStringLiteral("is_edited"),
        QStringLiteral("thumb_hash")
    };
    if (ids.isEmpty() || !allowed.contains(column)) {
        return;
    }
    QSqlQuery q(db());
    q.prepare(QStringLiteral("UPDATE remote_asset SET %1 = ? WHERE id = ?").arg(column));
    for (const QString &id : ids) {
        q.addBindValue(value);
        q.addBindValue(id);
        q.exec();
        q.finish();
    }
    notifyChanged(Assets);
}

void AssetDatabase::applyStack(const QString &stackId, const QString &primaryAssetId, const QStringList &assetIds)
{
    const QString now = QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'"));
    QSqlDatabase conn = db();
    if (!conn.transaction()) {
        return;
    }
    QSqlQuery q(conn);
    q.prepare(QStringLiteral("INSERT OR REPLACE INTO stack (id, owner_id, primary_asset_id, created_at, updated_at) VALUES (?, (SELECT value FROM sync_meta WHERE key = 'current_user_id'), ?, ?, ?)"));
    q.addBindValue(stackId);
    q.addBindValue(primaryAssetId);
    q.addBindValue(now);
    q.addBindValue(now);
    if (!q.exec()) {
        qWarning() << "AssetDatabase: Failed applyStack insert:" << q.lastError().text();
    }
    q.finish();
    q.prepare(QStringLiteral("UPDATE remote_asset SET stack_id = ? WHERE id = ?"));
    for (const QString &id : assetIds) {
        q.addBindValue(stackId);
        q.addBindValue(id);
        q.exec();
        q.finish();
    }
    if (!conn.commit()) {
        conn.rollback();
        return;
    }
    notifyChanged(Assets | Stacks);
}

void AssetDatabase::removeStack(const QString &stackId)
{
    QSqlDatabase conn = db();
    if (!conn.transaction()) {
        return;
    }
    QSqlQuery q(conn);
    q.prepare(QStringLiteral("UPDATE remote_asset SET stack_id = NULL WHERE stack_id = ?"));
    q.addBindValue(stackId);
    q.exec();
    q.finish();
    q.prepare(QStringLiteral("DELETE FROM stack WHERE id = ?"));
    q.addBindValue(stackId);
    q.exec();
    q.finish();
    if (!conn.commit()) {
        conn.rollback();
        return;
    }
    notifyChanged(Assets | Stacks);
}

void AssetDatabase::deleteRemoteAssets(const QStringList &ids)
{
    m_db.transaction();
    QSqlQuery q(db());
    q.prepare(QStringLiteral("DELETE FROM remote_asset_exif WHERE asset_id = ?"));
    for (const QString &id : ids) {
        q.addBindValue(id);
        q.exec();
        q.finish();
    }
    q.prepare(QStringLiteral("DELETE FROM album_to_asset WHERE asset_id = ?"));
    for (const QString &id : ids) {
        q.addBindValue(id);
        q.exec();
        q.finish();
    }
    q.prepare(QStringLiteral("DELETE FROM remote_asset WHERE id = ?"));
    for (const QString &id : ids) {
        q.addBindValue(id);
        q.exec();
        q.finish();
    }
    if (!m_db.commit()) {
        qWarning() << "AssetDatabase: Force-delete commit failed:" << m_db.lastError().text();
        m_db.rollback();
        return;
    }
    notifyChanged(Assets | Exif | Albums);
}

void AssetDatabase::addAlbumAssets(const QString &albumId, const QStringList &assetIds)
{
    if (albumId.isEmpty() || assetIds.isEmpty()) {
        return;
    }
    QSqlDatabase conn = db();
    if (!conn.transaction()) {
        return;
    }
    QSqlQuery q(conn);
    q.prepare(QStringLiteral("INSERT OR IGNORE INTO album_to_asset (album_id, asset_id) VALUES (?, ?)"));
    for (const QString &id : assetIds) {
        q.addBindValue(albumId);
        q.addBindValue(id);
        q.exec();
        q.finish();
    }
    if (!conn.commit()) {
        conn.rollback();
        return;
    }
    notifyChanged(AlbumAssets | Albums);
}

void AssetDatabase::upsertPartner(const QString &sharedById, const QString &sharedWithId, bool inTimeline)
{
    if (sharedById.isEmpty() || sharedWithId.isEmpty()) {
        return;
    }
    QSqlQuery q(db());
    q.prepare(QStringLiteral("INSERT OR REPLACE INTO partner (shared_by_id, shared_with_id, in_timeline) VALUES (?, ?, ?)"));
    q.addBindValue(sharedById);
    q.addBindValue(sharedWithId);
    q.addBindValue(inTimeline ? 1 : 0);
    if (!q.exec()) {
        return;
    }
    notifyChanged(Partners);
}

void AssetDatabase::removePartner(const QString &sharedById, const QString &sharedWithId)
{
    if (sharedById.isEmpty() || sharedWithId.isEmpty()) {
        return;
    }
    QSqlQuery q(db());
    q.prepare(QStringLiteral("DELETE FROM partner WHERE shared_by_id = ? AND shared_with_id = ?"));
    q.addBindValue(sharedById);
    q.addBindValue(sharedWithId);
    if (!q.exec()) {
        return;
    }
    notifyChanged(Partners);
}

void AssetDatabase::removeAlbumAssets(const QString &albumId, const QStringList &assetIds)
{
    if (albumId.isEmpty() || assetIds.isEmpty()) {
        return;
    }
    QSqlDatabase conn = db();
    if (!conn.transaction()) {
        return;
    }
    QSqlQuery q(conn);
    q.prepare(QStringLiteral("DELETE FROM album_to_asset WHERE album_id = ? AND asset_id = ?"));
    for (const QString &id : assetIds) {
        q.addBindValue(albumId);
        q.addBindValue(id);
        q.exec();
        q.finish();
    }
    if (!conn.commit()) {
        conn.rollback();
        return;
    }
    notifyChanged(AlbumAssets | Albums);
}

void AssetDatabase::clearTrashedRemoteAssets()
{
    QSqlQuery q(db());
    q.exec(QStringLiteral("DELETE FROM remote_asset_exif WHERE asset_id IN (SELECT id FROM remote_asset WHERE deleted_at IS NOT NULL)"));
    q.exec(QStringLiteral("DELETE FROM remote_asset WHERE deleted_at IS NOT NULL"));
    notifyChanged(Assets | Exif);
}

void AssetDatabase::restoreAllTrashedRemoteAssets()
{
    QSqlQuery q(db());
    q.exec(QStringLiteral("UPDATE remote_asset SET deleted_at = NULL WHERE deleted_at IS NOT NULL"));
    notifyChanged(Assets);
}

void AssetDatabase::notifyChanged(int mask)
{
    if (QThread::currentThread() != thread()) {
        QMetaObject::invokeMethod(this, "emitChanged", Qt::QueuedConnection, Q_ARG(int, mask));
        return;
    }
    emit changed(mask);
}

void AssetDatabase::emitChanged(int mask)
{
    emit changed(mask);
}

QThread *AssetDatabase::readerThread()
{
    if (!m_readerThread) {
        m_readerThread = new QThread();
        m_readerThread->setObjectName(QStringLiteral("catalog-reader"));
        m_readerThread->start();
    }
    return m_readerThread;
}

bool AssetDatabase::createSchema(bool fresh)
{
    if (!fresh) {
        return true;
    }
    if (!m_db.transaction()) {
        qWarning() << "AssetDatabase: Failed to begin schema transaction:" << m_db.lastError().text();
        return false;
    }
    QSqlQuery q(db());
    const QStringList statements = QStringList{
            QStringLiteral("CREATE TABLE sync_meta ("
                " key TEXT PRIMARY KEY,"
                " value TEXT"
                ")"),
            QStringLiteral("CREATE TABLE remote_asset ("
                " id TEXT PRIMARY KEY,"
                " owner_id TEXT NOT NULL,"
                " name TEXT NOT NULL DEFAULT '',"
                " type TEXT NOT NULL DEFAULT 'IMAGE',"
                " checksum TEXT NOT NULL DEFAULT '',"
                " visibility TEXT NOT NULL DEFAULT 'timeline',"
                " is_favorite INTEGER NOT NULL DEFAULT 0,"
                " is_edited INTEGER NOT NULL DEFAULT 0,"
                " width INTEGER,"
                " height INTEGER,"
                " duration_ms INTEGER,"
                " created_at TEXT NOT NULL DEFAULT '',"
                " updated_at TEXT,"
                " uploaded_at TEXT,"
                " local_date_time TEXT,"
                " deleted_at TEXT,"
                " thumb_hash TEXT,"
                " stack_id TEXT,"
                " live_photo_video_id TEXT,"
                " library_id TEXT"
                ")"),
            QStringLiteral("CREATE INDEX idx_remote_asset_checksum ON remote_asset(checksum)"),
            QStringLiteral("CREATE INDEX idx_remote_asset_stack ON remote_asset(stack_id)"),
            QStringLiteral("CREATE INDEX idx_remote_asset_timeline ON remote_asset(owner_id, visibility, deleted_at, created_at DESC)"),
            QStringLiteral("CREATE TABLE local_asset ("
                " id TEXT PRIMARY KEY,"
                " path TEXT UNIQUE NOT NULL,"
                " name TEXT NOT NULL DEFAULT '',"
                " type TEXT NOT NULL DEFAULT 'IMAGE',"
                " checksum TEXT,"
                " size INTEGER,"
                " mtime INTEGER,"
                " width INTEGER,"
                " height INTEGER,"
                " duration_ms INTEGER,"
                " created_at TEXT NOT NULL DEFAULT '',"
                " orientation INTEGER NOT NULL DEFAULT 0"
                ")"),
            QStringLiteral("CREATE INDEX idx_local_asset_checksum ON local_asset(checksum)"),
            QStringLiteral("CREATE INDEX idx_local_asset_created ON local_asset(created_at)"),
            QStringLiteral("CREATE TABLE stack ("
                " id TEXT PRIMARY KEY,"
                " owner_id TEXT,"
                " primary_asset_id TEXT,"
                " created_at TEXT,"
                " updated_at TEXT"
                ")"),
            QStringLiteral("CREATE TABLE remote_asset_exif ("
                " asset_id TEXT PRIMARY KEY,"
                " description TEXT,"
                " exif_image_width INTEGER,"
                " exif_image_height INTEGER,"
                " file_size INTEGER,"
                " orientation TEXT,"
                " date_time_original TEXT,"
                " modify_date TEXT,"
                " time_zone TEXT,"
                " latitude REAL,"
                " longitude REAL,"
                " projection_type TEXT,"
                " city TEXT,"
                " state TEXT,"
                " country TEXT,"
                " make TEXT,"
                " model TEXT,"
                " lens_model TEXT,"
                " f_number REAL,"
                " focal_length REAL,"
                " iso INTEGER,"
                " exposure_time TEXT,"
                " rating INTEGER,"
                " fps REAL,"
                " profile_description TEXT"
                ")"),
            QStringLiteral("CREATE TABLE sync_user ("
                " id TEXT PRIMARY KEY,"
                " name TEXT,"
                " email TEXT,"
                " avatar_color TEXT,"
                " has_profile_image INTEGER NOT NULL DEFAULT 0,"
                " profile_changed_at TEXT,"
                " deleted_at TEXT"
                ")"),
            QStringLiteral("CREATE TABLE auth_user ("
                " id TEXT PRIMARY KEY,"
                " name TEXT,"
                " email TEXT,"
                " avatar_color TEXT,"
                " has_profile_image INTEGER NOT NULL DEFAULT 0,"
                " profile_changed_at TEXT,"
                " is_admin INTEGER NOT NULL DEFAULT 0,"
                " pin_code TEXT,"
                " oauth_id TEXT,"
                " storage_label TEXT,"
                " quota_size_in_bytes INTEGER,"
                " quota_usage_in_bytes INTEGER,"
                " deleted_at TEXT"
                ")"),
            QStringLiteral("CREATE TABLE partner ("
                "  shared_by_id TEXT NOT NULL,"
                "  shared_with_id TEXT NOT NULL,"
                "  in_timeline INTEGER NOT NULL DEFAULT 0,"
                "  PRIMARY KEY (shared_by_id, shared_with_id)"
                ")"),
            QStringLiteral("CREATE TABLE album ("
                " id TEXT PRIMARY KEY,"
                " name TEXT,"
                " description TEXT,"
                " created_at TEXT,"
                " updated_at TEXT,"
                " thumbnail_asset_id TEXT,"
                " is_activity_enabled INTEGER NOT NULL DEFAULT 1,"
                " asset_order TEXT"
                ")"),
            QStringLiteral("CREATE TABLE album_user ("
                " album_id TEXT NOT NULL,"
                " user_id TEXT NOT NULL,"
                " role TEXT,"
                " PRIMARY KEY (album_id, user_id)"
                ")"),
            QStringLiteral("CREATE TABLE album_to_asset ("
                " album_id TEXT NOT NULL,"
                " asset_id TEXT NOT NULL,"
                " PRIMARY KEY (album_id, asset_id)"
                ")"),
            QStringLiteral("CREATE INDEX idx_album_to_asset_asset ON album_to_asset(asset_id)"),
            QStringLiteral("CREATE TABLE person ("
                " id TEXT PRIMARY KEY,"
                " created_at TEXT,"
                " updated_at TEXT,"
                " owner_id TEXT,"
                " name TEXT,"
                " birth_date TEXT,"
                " is_hidden INTEGER NOT NULL DEFAULT 0,"
                " is_favorite INTEGER NOT NULL DEFAULT 0,"
                " color TEXT,"
                " face_asset_id TEXT"
                ")"),
            QStringLiteral("CREATE TABLE asset_face ("
                " id TEXT PRIMARY KEY,"
                " asset_id TEXT,"
                " person_id TEXT,"
                " image_width INTEGER,"
                " image_height INTEGER,"
                " bounding_x1 INTEGER,"
                " bounding_y1 INTEGER,"
                " bounding_x2 INTEGER,"
                " bounding_y2 INTEGER,"
                " source_type TEXT,"
                " deleted_at TEXT,"
                " is_visible INTEGER NOT NULL DEFAULT 1"
                ")"),
            QStringLiteral("CREATE INDEX idx_asset_face_asset ON asset_face(asset_id)"),
            QStringLiteral("CREATE INDEX idx_asset_face_person ON asset_face(person_id)"),
            QStringLiteral("CREATE TABLE memory ("
                " id TEXT PRIMARY KEY,"
                " created_at TEXT,"
                " updated_at TEXT,"
                " deleted_at TEXT,"
                " owner_id TEXT,"
                " type TEXT,"
                " data TEXT,"
                " is_saved INTEGER NOT NULL DEFAULT 0,"
                " memory_at TEXT,"
                " seen_at TEXT,"
                " show_at TEXT,"
                " hide_at TEXT"
                ")"),
            QStringLiteral("CREATE TABLE memory_to_asset ("
                " memory_id TEXT NOT NULL,"
                " asset_id TEXT NOT NULL,"
                " PRIMARY KEY (memory_id, asset_id)"
                ")"),
            QStringLiteral("CREATE TABLE asset_edit ("
                " id TEXT PRIMARY KEY,"
                " asset_id TEXT,"
                " action TEXT,"
                " parameters TEXT,"
                " sequence INTEGER"
                ")"),
            QStringLiteral("CREATE INDEX idx_asset_edit_asset ON asset_edit(asset_id)"),
            QStringLiteral("CREATE TABLE asset_metadata ("
                " asset_id TEXT NOT NULL,"
                " key TEXT NOT NULL,"
                " value TEXT,"
                " PRIMARY KEY (asset_id, key)"
                ")"),
            QStringLiteral("CREATE TABLE asset_ocr ("
                " id TEXT PRIMARY KEY,"
                " asset_id TEXT,"
                " text TEXT,"
                " x1 REAL, y1 REAL, x2 REAL, y2 REAL,"
                " x3 REAL, y3 REAL, x4 REAL, y4 REAL,"
                " box_score REAL, text_score REAL,"
                " is_visible INTEGER NOT NULL DEFAULT 1"
                ")"),
            QStringLiteral("CREATE INDEX idx_asset_ocr_asset ON asset_ocr(asset_id)"),
            QStringLiteral("CREATE TABLE user_metadata ("
                " user_id TEXT NOT NULL,"
                " key TEXT NOT NULL,"
                " value TEXT,"
                " PRIMARY KEY (user_id, key)"
                ")"),
            QStringLiteral("CREATE VIEW merged_asset AS"
                " SELECT ra.id AS remote_id,"
                " (SELECT la.id FROM local_asset la WHERE la.checksum = ra.checksum LIMIT 1) AS local_id,"
                " ra.name, ra.type, ra.created_at, ra.updated_at,"
                " ra.width, ra.height, ra.duration_ms, ra.is_favorite, ra.thumb_hash,"
                " ra.checksum, ra.owner_id, ra.live_photo_video_id, ra.stack_id,"
                " (SELECT COUNT(*) FROM remote_asset s2 WHERE s2.stack_id = ra.stack_id) AS stack_asset_count,"
                " ra.is_edited, ra.uploaded_at, ra.visibility, ra.deleted_at,"
                " (SELECT la.path FROM local_asset la WHERE la.checksum = ra.checksum LIMIT 1) AS local_path"
                " FROM remote_asset ra"
                " LEFT JOIN stack se ON ra.stack_id = se.id"
                " WHERE ra.deleted_at IS NULL AND ra.visibility = 'timeline'"
                " AND (ra.owner_id = (SELECT value FROM sync_meta WHERE key = 'current_user_id')"
                " OR ra.owner_id IN (SELECT shared_by_id FROM partner"
                " WHERE shared_with_id = (SELECT value FROM sync_meta WHERE key = 'current_user_id')"
                " AND in_timeline = 1))"
                " AND (ra.stack_id IS NULL OR se.id IS NULL OR ra.id = se.primary_asset_id)"
                " UNION ALL"
                " SELECT NULL, la.id, la.name, la.type, la.created_at, NULL,"
                " la.width, la.height, la.duration_ms, 0, NULL,"
                " la.checksum, NULL, NULL, NULL, 0, 0, NULL,"
                " 'timeline', NULL,"
                " la.path"
                " FROM local_asset la"
                " WHERE NOT EXISTS (SELECT 1 FROM remote_asset ra WHERE ra.checksum = la.checksum)")};

    for (const QString &stmt : statements) {
        if (!q.exec(stmt)) {
            qWarning() << "AssetDatabase: Schema creation failed:" << q.lastError().text();
            m_db.rollback();
            return false;
        }
    }
    if (!m_db.commit()) {
        qWarning() << "AssetDatabase: Schema commit failed:" << m_db.lastError().text();
        m_db.rollback();
        return false;
    }
    qInfo() << "AssetDatabase: Catalog schema created";
    return true;
}
