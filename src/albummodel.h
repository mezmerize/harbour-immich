#ifndef ALBUMMODEL_H
#define ALBUMMODEL_H

#include <QAbstractListModel>
#include <QJsonArray>

struct Album {
    QString id;
    QString albumName;
    QString albumThumbnailAssetId;
    int assetCount;
    QString createdAt;
    QString updatedAt;
    QString startDate;
    QString endDate;
    bool isOwned;
    QString ownerName;
};

class AlbumModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum AlbumRoles {
        IdRole = Qt::UserRole + 1,
        AlbumNameRole,
        AlbumThumbnailAssetIdRole,
        AssetCountRole,
        CreatedAtRole,
        UpdatedAtRole,
        StartDateRole,
        EndDateRole,
        IsOwnedRole,
        OwnerNameRole
    };

    explicit AlbumModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void loadAlbums(const QJsonArray &albumsJson);
    Q_INVOKABLE void sortAlbums(const QString &field, bool ascending);

private:
    QList<Album> m_albums;
};

#endif
