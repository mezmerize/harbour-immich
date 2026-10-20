#ifndef PEOPLEMODEL_H
#define PEOPLEMODEL_H

#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QJsonArray>
#include <QVariantMap>
#include <QSet>
#include <QPair>

struct Person {
    QString id;
    QString name;
    QString birthDate;
    bool hasThumbnail = false;
    bool isFavorite = false;
    bool isHidden = false;
    QString updatedAt;
    QStringList sharedWithNames;
    QStringList sharedByNames;
};

class PersonSourceModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum PersonRoles {
        PersonIdRole = Qt::UserRole + 1,
        NameRole,
        BirthDateRole,
        HasThumbnailRole,
        IsFavoriteRole,
        IsHiddenRole,
        UpdatedAtRole,
        IsSharedByMeRole,
        IsSharedWithMeRole,
        SharedWithNamesRole,
        SharedByNamesRole,
        SelectedRole
    };

    explicit PersonSourceModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void loadPeople(const QJsonArray &people);
    void setShares(const QJsonArray &shares, const QString &me);
    void setSelected(int sourceRow, bool selected);
    void clearSelection();
    QStringList selectedIds() const;
    const Person &personAt(int row) const;

private:
    QList<Person> m_people;
    QSet<QString> m_selectedIds;
    QHash<QString, QPair<QStringList, QStringList>> m_shares;
    void applyShares(Person &p) const;
};

class PeopleModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(QString filterText READ filterText WRITE setFilterText NOTIFY filterTextChanged)
    Q_PROPERTY(bool showFavorites READ showFavorites WRITE setShowFavorites NOTIFY showFavoritesChanged)
    Q_PROPERTY(QString activeFilter READ activeFilter WRITE setActiveFilter NOTIFY activeFilterChanged)
    Q_PROPERTY(bool sortAscending READ sortAscending WRITE setSortAscending NOTIFY sortAscendingChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectedCountChanged)

public:
    explicit PeopleModel(QObject *parent = nullptr);

    QString filterText() const {
        return m_filterText;
    }
    void setFilterText(const QString &text);

    bool showFavorites() const {
        return m_showFavorites;
    }
    void setShowFavorites(bool value);

    QString activeFilter() const {
        return m_activeFilter;
    }
    void setActiveFilter(const QString &filter);

    bool sortAscending() const {
        return m_sortAscending;
    }
    void setSortAscending(bool value);

    int count() const {
        return rowCount();
    }
    int totalCount() const;

    Q_INVOKABLE void loadPeople(const QJsonArray &people);
    Q_INVOKABLE QVariantMap get(int proxyRow) const;
    Q_INVOKABLE void setShares(const QJsonArray &shares, const QString &me);
    Q_INVOKABLE void toggleSelection(int proxyRow);
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE QStringList selectedIds() const;
    int selectedCount() const;

signals:
    void filterTextChanged();
    void showFavoritesChanged();
    void activeFilterChanged();
    void sortAscendingChanged();
    void countChanged();
    void totalCountChanged();
    void selectedCountChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

private:
    PersonSourceModel *m_source;
    QString m_filterText;
    bool m_showFavorites = false;
    QString m_activeFilter = QStringLiteral("name");
    bool m_sortAscending = true;
};

#endif
