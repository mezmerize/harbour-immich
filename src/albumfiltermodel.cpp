#include "albumfiltermodel.h"
#include "albummodel.h"

AlbumFilterModel::AlbumFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
    setFilterRole(AlbumModel::AlbumNameRole);
    setFilterCaseSensitivity(Qt::CaseInsensitive);
    connect(this, &QAbstractItemModel::rowsInserted, this, &AlbumFilterModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &AlbumFilterModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &AlbumFilterModel::countChanged);
    connect(this, &QAbstractItemModel::layoutChanged, this, &AlbumFilterModel::countChanged);
}

void AlbumFilterModel::setAlbumModel(QObject *model)
{
    if (m_albumModel != model) {
        m_albumModel = model;
        setSourceModel(qobject_cast<QAbstractItemModel *>(model));
        emit albumModelChanged();
    }
}

void AlbumFilterModel::setFilterText(const QString &text)
{
    if (m_filterText != text) {
        m_filterText = text;
        setFilterFixedString(text);
        emit filterTextChanged();
    }
}
