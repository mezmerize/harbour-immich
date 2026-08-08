#ifndef PEOPLEMODEL_H
#define PEOPLEMODEL_H

#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QJsonArray>
#include <QVariantMap>

struct Person {
    QString id;
    QString name;
    QString birthDate;
    QString thumbnailPath;
    QString thumbnailId;
    bool isFavorite = false;
    bool isHidden = false;
    QString updatedAt;
};

class PersonSourceModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum PersonRoles {
        PersonIdRole = Qt::UserRole + 1,
        NameRole,
        BirthDateRole,
        ThumbnailPathRole,
        ThumbnailIdRole,
        IsFavoriteRole,
        IsHiddenRole,
        UpdatedAtRole
    };

    explicit PersonSourceModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void loadPeople(const QJsonArray &people);
    const Person &personAt(int row) const;

private:
    QList<Person> m_people;
    QString extractThumbnailId(const QJsonObject &person) const;
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

signals:
    void filterTextChanged();
    void showFavoritesChanged();
    void activeFilterChanged();
    void sortAscendingChanged();
    void countChanged();
    void totalCountChanged();

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
