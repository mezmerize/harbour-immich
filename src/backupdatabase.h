#ifndef BACKUPDATABASE_H
#define BACKUPDATABASE_H

#include <QObject>
#include <QSqlDatabase>
#include <QHash>
#include <QStringList>
#include <QSet>

class BackupDatabase : public QObject
{
    Q_OBJECT

public:
    enum Status {
        Pending = 0,
        Uploading = 1,
        BackedUp = 2,
        Failed = 3
    };
    Q_ENUM(Status)

    struct FileRecord {
        qint64 size;
        qint64 modified;
        int status;
        QString remoteAssetId;
    };

    explicit BackupDatabase(QObject *parent = nullptr);
    ~BackupDatabase();

    bool initialize();

    // File tracking
    bool addFile(const QString &filePath, qint64 fileSize, qint64 fileModified);
    bool hasFile(const QString &filePath) const;
    bool hasFileChanged(const QString &filePath, qint64 fileSize, qint64 fileModified) const;
    bool removeFile(const QString &filePath);

    QHash<QString, FileRecord> allRecords() const;
    QHash<QString, FileRecord> recordsWithPrefix(const QString &pathPrefix) const;

    // Status updates
    bool setStatus(const QString &filePath, Status status, const QString &remoteAssetId = QString(), const QString &errorMessage = QString());
    Status fileStatus(const QString &filePath) const;

    // Queries
    QStringList pendingFiles(int limit = 100) const;
    QStringList failedFiles() const;
    QStringList allFilePaths() const;
    int countByStatus(Status status) const;
    int totalTrackedFiles() const;

    // Remote asset
    QSet<QString> allBackedUpRemoteAssetIds() const;
    QString remoteAssetIdForFile(const QString &filePath) const;

    // Manual upload
    bool registerManualUpload(const QString &filePath, qint64 fileSize, qint64 fileModified, const QString &remoteAssetId);

    // Server deletion
    bool removeByRemoteAssetIds(const QStringList &ids);
    int removeMissingRemoteAssets(const QSet<QString> &existingIds, qint64 olderThanMs);

    static QString makeDeviceAssetId(const QString &fileName, qint64 lastModifiedMs);

    // Retry failed uploads
    bool resetFile(const QString &filePath);

    // Issue during upload - back to pending
    int resetStuckUploads();

    // Database management
    bool clearAll();

    // Pre-build from server comparison
    bool addFileAsBackedUp(const QString &filePath, qint64 fileSize, qint64 fileModified, const QString &remoteAssetId = QString());

private:
    QSqlDatabase m_db;
    bool createTables();
};

#endif
