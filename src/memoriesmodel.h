#ifndef MEMORIESMODEL_H
#define MEMORIESMODEL_H

#include <QAbstractListModel>
#include <QJsonArray>
#include <QJsonObject>

struct Memory {
    QString id;
    QString memoryAt;
    int year = 0;
    bool isSaved = false;
    QString thumbnailId;
    QString thumbhash;
    int assetCount = 0;
    QString assetsJson;
};

class MemoriesModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int totalCount READ totalCount WRITE setTotalCount NOTIFY totalCountChanged)

public:
    enum MemoryRoles {
        MemoryIdRole = Qt::UserRole + 1,
        MemoryAtRole,
        YearRole,
        IsSavedRole,
        ThumbnailIdRole,
        ThumbhashRole,
        AssetCountRole,
        AssetsJsonRole
    };

    explicit MemoriesModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const {
        return m_memories.size();
    }
    int totalCount() const {
        return m_totalCount;
    }
    void setTotalCount(int total);

    Q_INVOKABLE void appendMemories(const QJsonArray &memories);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void setSaved(const QString &memoryId, bool saved);

signals:
    void countChanged();
    void totalCountChanged();

private:
    QList<Memory> m_memories;
    int m_totalCount = 0;
};

#endif
