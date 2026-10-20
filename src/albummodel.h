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
    Q_PROPERTY(QString sortField READ sortField WRITE setSortField NOTIFY sortFieldChanged)
    Q_PROPERTY(bool sortAscending READ sortAscending WRITE setSortAscending NOTIFY sortAscendingChanged)

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

    void loadAlbums(const QJsonArray &albumsJson);
    Q_INVOKABLE void updateAlbumMetadata(const QString &albumId, const QString &albumName, const QString &albumThumbnailAssetId);

    QString sortField() const { return m_sortField; }
    void setSortField(const QString &field);
    bool sortAscending() const { return m_sortAscending; }
    void setSortAscending(bool ascending);

signals:
    void sortFieldChanged();
    void sortAscendingChanged();

private:
    void refreshOwnershipFlags();
    void applySort();
    QList<Album> m_albums;
    AuthManager *m_authManager;
    QString m_sortField = QStringLiteral("endDate");
    bool m_sortAscending = false;
};

#endif
