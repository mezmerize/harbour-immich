#ifndef ALBUMFILTERMODEL_H
#define ALBUMFILTERMODEL_H

#include <QSortFilterProxyModel>

class AlbumFilterModel : public QSortFilterProxyModel
{
    Q_OBJECT
    Q_PROPERTY(QObject *sourceAlbumModel READ albumModel WRITE setAlbumModel NOTIFY albumModelChanged)
    Q_PROPERTY(QString filterText READ filterText WRITE setFilterText NOTIFY filterTextChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit AlbumFilterModel(QObject *parent = nullptr);

    QObject *albumModel() const { return m_albumModel; }
    void setAlbumModel(QObject *model);

    QString filterText() const { return m_filterText; }
    void setFilterText(const QString &text);

    int count() const { return rowCount(); }

signals:
    void albumModelChanged();
    void filterTextChanged();
    void countChanged();

private:
    QObject *m_albumModel = nullptr;
    QString m_filterText;
};

#endif // ALBUMFILTERMODEL_H
