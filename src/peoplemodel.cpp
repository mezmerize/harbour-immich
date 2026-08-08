#include "peoplemodel.h"
#include <QJsonObject>

PersonSourceModel::PersonSourceModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int PersonSourceModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_people.size();
}

QVariant PersonSourceModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_people.size())
        return QVariant();

    const Person &p = m_people.at(index.row());
    switch (role) {
    case PersonIdRole: return p.id;
    case NameRole: return p.name;
    case BirthDateRole: return p.birthDate;
    case ThumbnailPathRole: return p.thumbnailPath;
    case ThumbnailIdRole: return p.thumbnailId;
    case IsFavoriteRole: return p.isFavorite;
    case IsHiddenRole: return p.isHidden;
    case UpdatedAtRole: return p.updatedAt;
    default: return QVariant();
    }
}

QHash<int, QByteArray> PersonSourceModel::roleNames() const
{
    return {
        { PersonIdRole, "personId" },
        { NameRole, "name" },
        { BirthDateRole, "birthDate" },
        { ThumbnailPathRole, "thumbnailPath" },
        { ThumbnailIdRole, "thumbnailId" },
        { IsFavoriteRole, "isFavorite" },
        { IsHiddenRole, "isHidden" },
        { UpdatedAtRole, "updatedAt" }
    };
}

void PersonSourceModel::loadPeople(const QJsonArray &people)
{
    beginResetModel();
    m_people.clear();
    m_people.reserve(people.size());
    for (const QJsonValue &value : people) {
        const QJsonObject o = value.toObject();
        Person p;
        p.id = o.value(QStringLiteral("id")).toString();
        p.name = o.value(QStringLiteral("name")).toString();
        p.birthDate = o.value(QStringLiteral("birthDate")).toString();
        p.thumbnailPath = o.value(QStringLiteral("thumbnailPath")).toString();
        p.thumbnailId = extractThumbnailId(o);
        p.isFavorite = o.value(QStringLiteral("isFavorite")).toBool();
        p.isHidden = o.value(QStringLiteral("isHidden")).toBool();
        p.updatedAt = o.value(QStringLiteral("updatedAt")).toString();
        m_people.append(p);
    }
    endResetModel();
}

QString PersonSourceModel::extractThumbnailId(const QJsonObject &person) const
{
    const QString personId = person.value(QStringLiteral("id")).toString();
    const QString thumbnailPath = person.value(QStringLiteral("thumbnailPath")).toString();
    if (thumbnailPath.isEmpty())
        return personId;

    const int slashPos = thumbnailPath.lastIndexOf('/');
    QString fileName = (slashPos >= 0) ? thumbnailPath.mid(slashPos + 1) : thumbnailPath;
    if (fileName.endsWith(".jpeg", Qt::CaseInsensitive))
        fileName.chop(5);
    else if (fileName.endsWith(".jpg", Qt::CaseInsensitive))
        fileName.chop(4);
    return fileName.isEmpty() ? personId : fileName;
}

const Person &PersonSourceModel::personAt(int row) const
{
    return m_people.at(row);
}

PeopleModel::PeopleModel(QObject *parent)
    : QSortFilterProxyModel(parent)
    , m_source(new PersonSourceModel(this))
{
    setSourceModel(m_source);
    setDynamicSortFilter(true);
    sort(0, Qt::AscendingOrder);

    connect(this, &QAbstractItemModel::rowsInserted, this, &PeopleModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &PeopleModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &PeopleModel::countChanged);
    connect(this, &QAbstractItemModel::layoutChanged, this, &PeopleModel::countChanged);
    connect(m_source, &QAbstractItemModel::modelReset, this, &PeopleModel::totalCountChanged);
}

int PeopleModel::totalCount() const
{
    return m_source->rowCount();
}

void PeopleModel::setFilterText(const QString &text)
{
    if (m_filterText == text)
        return;
    m_filterText = text;
    invalidateFilter();
    emit filterTextChanged();
    emit countChanged();
}

void PeopleModel::setShowFavorites(bool value)
{
    if (m_showFavorites == value)
        return;
    m_showFavorites = value;
    invalidateFilter();
    emit showFavoritesChanged();
    emit countChanged();
}

void PeopleModel::setActiveFilter(const QString &filter)
{
    if (m_activeFilter == filter)
        return;
    m_activeFilter = filter;
    invalidate();
    emit activeFilterChanged();
}

void PeopleModel::setSortAscending(bool value)
{
    if (m_sortAscending == value)
        return;
    m_sortAscending = value;
    invalidate();
    emit sortAscendingChanged();
}

void PeopleModel::loadPeople(const QJsonArray &people)
{
    m_source->loadPeople(people);
    emit totalCountChanged();
    emit countChanged();
}

QVariantMap PeopleModel::get(int proxyRow) const
{
    QVariantMap map;
    const QModelIndex proxyIndex = index(proxyRow, 0);
    if (!proxyIndex.isValid())
        return map;
    const QModelIndex sourceIndex = mapToSource(proxyIndex);
    if (!sourceIndex.isValid())
        return map;

    const Person &p = m_source->personAt(sourceIndex.row());
    map[QStringLiteral("personId")] = p.id;
    map[QStringLiteral("name")] = p.name;
    map[QStringLiteral("birthDate")] = p.birthDate;
    map[QStringLiteral("thumbnailPath")] = p.thumbnailPath;
    map[QStringLiteral("thumbnailId")] = p.thumbnailId;
    map[QStringLiteral("isFavorite")] = p.isFavorite;
    map[QStringLiteral("isHidden")] = p.isHidden;
    map[QStringLiteral("updatedAt")] = p.updatedAt;
    return map;
}

bool PeopleModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    Q_UNUSED(sourceParent)
    const Person &p = m_source->personAt(sourceRow);
    if (m_showFavorites && !p.isFavorite)
        return false;
    if (!m_filterText.isEmpty() && !p.name.contains(m_filterText, Qt::CaseInsensitive))
        return false;
    return true;
}

bool PeopleModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    const Person &a = m_source->personAt(left.row());
    const Person &b = m_source->personAt(right.row());

    if (m_activeFilter == QStringLiteral("updatedAt")) {
        const int cmp = a.updatedAt.compare(b.updatedAt);
        return m_sortAscending ? (cmp < 0) : (cmp > 0);
    }

    const bool aEmpty = a.name.isEmpty();
    const bool bEmpty = b.name.isEmpty();
    if (aEmpty != bEmpty)
        return !aEmpty;

    const int cmp = a.name.compare(b.name, Qt::CaseInsensitive);
    return m_sortAscending ? (cmp < 0) : (cmp > 0);
}
