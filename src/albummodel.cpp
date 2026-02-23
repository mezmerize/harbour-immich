#include "albummodel.h"
#include <QJsonObject>
#include <algorithm>

AlbumModel::AlbumModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int AlbumModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_albums.size();
}

QVariant AlbumModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_albums.size())
        return QVariant();

    const Album &album = m_albums[index.row()];

    switch (role) {
    case IdRole:
        return album.id;
    case AlbumNameRole:
        return album.albumName;
    case AlbumThumbnailAssetIdRole:
        return album.albumThumbnailAssetId;
    case AssetCountRole:
        return album.assetCount;
    case CreatedAtRole:
        return album.createdAt;
    case UpdatedAtRole:
        return album.updatedAt;
    case StartDateRole:
        return album.startDate;
    case EndDateRole:
        return album.endDate;
    case IsOwnedRole:
        return album.isOwned;
    case OwnerNameRole:
        return album.ownerName;
    }

    return QVariant();
}

QHash<int, QByteArray> AlbumModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "albumId";
    roles[AlbumNameRole] = "albumName";
    roles[AlbumThumbnailAssetIdRole] = "albumThumbnailAssetId";
    roles[AssetCountRole] = "assetCount";
    roles[CreatedAtRole] = "createdAt";
    roles[UpdatedAtRole] = "updatedAt";
    roles[StartDateRole] = "startDate";
    roles[EndDateRole] = "endDate";
    roles[IsOwnedRole] = "isOwned";
    roles[OwnerNameRole] = "ownerName";
    return roles;
}

void AlbumModel::loadAlbums(const QJsonArray &albumsJson)
{
    beginResetModel();
    m_albums.clear();

    for (const QJsonValue &value : albumsJson) {
        QJsonObject obj = value.toObject();
        Album album;
        album.id = obj["id"].toString();
        album.albumName = obj["albumName"].toString();
        album.albumThumbnailAssetId = obj["albumThumbnailAssetId"].toString();
        album.assetCount = obj["assetCount"].toInt();
        album.createdAt = obj["createdAt"].toString();
        album.updatedAt = obj["updatedAt"].toString();
        album.startDate = obj["startDate"].toString();
        album.endDate = obj["endDate"].toString();

        // Owner info
        QJsonObject ownerObj = obj["owner"].toObject();
        QString ownerEmail = ownerObj["email"].toString();
        album.ownerName = ownerObj["name"].toString();
        if (album.ownerName.isEmpty()) {
            album.ownerName = ownerEmail;
        }
        album.isOwned = !obj["shared"].toBool();

        m_albums.append(album);
    }

    endResetModel();
}

void AlbumModel::sortAlbums(const QString &field, bool ascending)
{
    beginResetModel();

    std::sort(m_albums.begin(), m_albums.end(), [&field, ascending](const Album &a, const Album &b) {
        int cmp = 0;
        if (field == "albumName") {
            cmp = QString::localeAwareCompare(a.albumName, b.albumName);
        } else if (field == "assetCount") {
            cmp = (a.assetCount < b.assetCount) ? -1 : (a.assetCount > b.assetCount) ? 1 : 0;
        } else if (field == "updatedAt") {
            cmp = a.updatedAt.compare(b.updatedAt);
        } else if (field == "createdAt") {
            cmp = a.createdAt.compare(b.createdAt);
        } else if (field == "endDate") {
            cmp = a.endDate.compare(b.endDate);
        } else if (field == "startDate") {
            cmp = a.startDate.compare(b.startDate);
        }
        return ascending ? cmp < 0 : cmp > 0;
    });

    endResetModel();
}
