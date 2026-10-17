#ifndef ASSETDATABASE_H
#define ASSETDATABASE_H

#include <QObject>
#include <QSqlDatabase>
#include <QString>
#include <QSet>
#include <QVariantMap>

class QThread;

class AssetDatabase : public QObject
{
    Q_OBJECT

public:
    explicit AssetDatabase(QObject *parent = nullptr);
    ~AssetDatabase();

    static AssetDatabase *instance() {
        return s_instance;
    }

    enum Table {
        Assets = 0x1,
        Exif = 0x2,
        Albums = 0x4,
        AlbumAssets = 0x8,
        Stacks = 0x10,
        Partners = 0x20,
        Users = 0x40,
        People = 0x80,
        Memories = 0x100,
        LocalAssets = 0x200,
        Other = 0x400,
        AllTables = 0x7FF
    };

    bool initialize();

    QSqlDatabase db() const;
    Q_INVOKABLE qint64 tableRowCount(const QString &table) const;
    bool tableHasRows(const QString &table) const;
    bool clearSyncedData(bool reclaimSpace = true);
    Q_INVOKABLE QString metaValue(const QString &key) const;
    bool setMetaValue(const QString &key, const QString &value);
    QSet<QString> ownRemoteAssetIds() const;
    Q_INVOKABLE QVariantMap localAssetInfo(const QString &path) const;
    void patchRemoteAssets(const QStringList &ids, const QString &column, const QVariant &value);
    void applyStack(const QString &stackId, const QString &primaryAssetId, const QStringList &assetIds);
    void removeStack(const QString &stackId);
    void deleteRemoteAssets(const QStringList &ids);
    void addAlbumAssets(const QString &albumId, const QStringList &assetIds);
    void removeAlbumAssets(const QString &albumId, const QStringList &assetIds);
    void upsertPartner(const QString &sharedById, const QString &sharedWithId, bool inTimeline);
    void removePartner(const QString &sharedById, const QString &sharedWithId);
    void clearTrashedRemoteAssets();
    void restoreAllTrashedRemoteAssets();
    void notifyChanged(int mask);
    QThread *readerThread();

signals:
    void changed(int mask);

private slots:
    void emitChanged(int mask);

private:
    bool createSchema(bool fresh);

    QSqlDatabase m_db;
    QThread *m_readerThread = nullptr;
    static AssetDatabase *s_instance;
};

#endif // ASSETDATABASE_H
