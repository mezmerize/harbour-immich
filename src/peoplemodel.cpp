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
    case PersonIdRole:
        return p.id;
    case NameRole:
        return p.name;
    case BirthDateRole:
        return p.birthDate;
    case HasThumbnailRole:
        return p.hasThumbnail;
    case IsFavoriteRole:
        return p.isFavorite;
    case IsHiddenRole:
        return p.isHidden;
    case UpdatedAtRole:
        return p.updatedAt;
    case IsSharedByMeRole:
        return !p.sharedWithNames.isEmpty();
    case IsSharedWithMeRole:
        return !p.sharedByNames.isEmpty();
    case SharedWithNamesRole:
        return p.sharedWithNames.join(QStringLiteral(", "));
    case SharedByNamesRole:
        return p.sharedByNames.join(QStringLiteral(", "));
    case SelectedRole:
        return m_selectedIds.contains(p.id);
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> PersonSourceModel::roleNames() const
{
    return {
        { PersonIdRole, "personId" },
        { NameRole, "name" },
        { BirthDateRole, "birthDate" },
        { HasThumbnailRole, "hasThumbnail" },
        { IsFavoriteRole, "isFavorite" },
        { IsHiddenRole, "isHidden" },
        { UpdatedAtRole, "updatedAt" },
        { IsSharedByMeRole, "isSharedByMe" },
        { IsSharedWithMeRole, "isSharedWithMe" },
        { SharedWithNamesRole, "sharedWithNames" },
        { SharedByNamesRole, "sharedByNames" },
        { SelectedRole, "selected" }
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
        p.hasThumbnail = o.value(QStringLiteral("hasThumbnail")).toBool();
        p.isFavorite = o.value(QStringLiteral("isFavorite")).toBool();
        p.isHidden = o.value(QStringLiteral("isHidden")).toBool();
        p.updatedAt = o.value(QStringLiteral("updatedAt")).toString();
        applyShares(p);
        m_people.append(p);
    }
    QSet<QString> presentIds;
    for (const Person &p : m_people) {
        presentIds.insert(p.id);
    }
    m_selectedIds.intersect(presentIds);
    endResetModel();
}

void PersonSourceModel::applyShares(Person &p) const
{
    const auto it = m_shares.constFind(p.id);
    if (it != m_shares.constEnd()) {
        p.sharedWithNames = it->first;
        p.sharedByNames = it->second;
    }
}

static QString shareUserName(const QJsonObject &user)
{
    const QString name = user.value(QStringLiteral("name")).toString();
    return name.isEmpty() ? user.value(QStringLiteral("email")).toString() : name;
}

void PersonSourceModel::setShares(const QJsonArray &shares, const QString &me)
{
    m_shares.clear();
    for (const QJsonValue &v : shares) {
        const QJsonObject s = v.toObject();
        const QString personId = s.value(QStringLiteral("personId")).toString();
        if (personId.isEmpty()) {
            continue;
        }
        if (s.value(QStringLiteral("sharedById")).toString() == me) {
            m_shares[personId].first.append(shareUserName(s.value(QStringLiteral("sharedWith")).toObject()));
        } else if (s.value(QStringLiteral("sharedWithId")).toString() == me) {
            m_shares[personId].second.append(shareUserName(s.value(QStringLiteral("sharedBy")).toObject()));
        }
    }
    for (int i = 0; i < m_people.size(); ++i) {
        Person &p = m_people[i];
        const QStringList oldWith = p.sharedWithNames;
        const QStringList oldBy = p.sharedByNames;
        p.sharedWithNames.clear();
        p.sharedByNames.clear();
        applyShares(p);
        if (p.sharedWithNames != oldWith || p.sharedByNames != oldBy) {
            const QModelIndex idx = index(i);
            emit dataChanged(idx, idx, { IsSharedByMeRole, IsSharedWithMeRole, SharedWithNamesRole, SharedByNamesRole });
        }
    }
}

void PersonSourceModel::setSelected(int sourceRow, bool selected)
{
    if (sourceRow < 0 || sourceRow >= m_people.size()) {
        return;
    }
    const QString id = m_people[sourceRow].id;
    if (selected) {
        m_selectedIds.insert(id);
    } else {
        m_selectedIds.remove(id);
    }
    const QModelIndex idx = index(sourceRow);
    emit dataChanged(idx, idx, { SelectedRole });
}

void PersonSourceModel::clearSelection()
{
    for (int i = 0; i < m_people.size(); ++i) {
        setSelected(i, false);
    }
}

QStringList PersonSourceModel::selectedIds() const
{
    QStringList ids;
    for (const Person &p : m_people) {
        if (m_selectedIds.contains(p.id)) {
            ids.append(p.id);
        }
    }
    return ids;
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
    map[QStringLiteral("hasThumbnail")] = p.hasThumbnail;
    map[QStringLiteral("isFavorite")] = p.isFavorite;
    map[QStringLiteral("isHidden")] = p.isHidden;
    map[QStringLiteral("updatedAt")] = p.updatedAt;
    map[QStringLiteral("isSharedByMe")] = !p.sharedWithNames.isEmpty();
    map[QStringLiteral("isSharedWithMe")] = !p.sharedByNames.isEmpty();
    map[QStringLiteral("sharedWithNames")] = p.sharedWithNames.join(QStringLiteral(", "));
    map[QStringLiteral("sharedByNames")] = p.sharedByNames.join(QStringLiteral(", "));
    map[QStringLiteral("selected")] = m_source->selectedIds().contains(p.id);
    return map;
}

void PeopleModel::setShares(const QJsonArray &shares, const QString &me)
{
    m_source->setShares(shares, me);
}

void PeopleModel::toggleSelection(int proxyRow)
{
    const QModelIndex sourceIndex = mapToSource(index(proxyRow, 0));
    if (!sourceIndex.isValid())
        return;
    const Person &p = m_source->personAt(sourceIndex.row());
    m_source->setSelected(sourceIndex.row(), !m_source->selectedIds().contains(p.id));
    emit selectedCountChanged();
}

void PeopleModel::clearSelection()
{
    m_source->clearSelection();
    emit selectedCountChanged();
}

QStringList PeopleModel::selectedIds() const
{
    return m_source->selectedIds();
}

int PeopleModel::selectedCount() const
{
    return m_source->selectedIds().size();
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
