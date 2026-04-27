#ifndef ALBUMMODEL_H
#define ALBUMMODEL_H

#include <QAbstractListModel>
#include <QJsonArray>

class AuthManager;

struct Album {
    QString id;
    QString ownerId;
    QString albumName;
    QString description;
    QString albumThumbnailAssetId;
    int assetCount;
    QString createdAt;
    QString updatedAt;
    QString startDate;
    QString endDate;
    bool shared;
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
        DescriptionRole,
        AlbumThumbnailAssetIdRole,
        AssetCountRole,
        CreatedAtRole,
        UpdatedAtRole,
        StartDateRole,
        EndDateRole,
        OwnerIdRole,
        SharedRole,
        IsOwnedRole,
        OwnerNameRole
    };

    explicit AlbumModel(AuthManager *authManager, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE void loadAlbums(const QJsonArray &albumsJson);
    Q_INVOKABLE void sortAlbums(const QString &field, bool ascending);
    Q_INVOKABLE void updateAlbumMetadata(const QString &albumId, const QString &albumName, const QString &albumThumbnailAssetId);

private:
    void refreshOwnershipFlags();
    QList<Album> m_albums;
    AuthManager *m_authManager;
};

#endif
