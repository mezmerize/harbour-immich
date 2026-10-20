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
    QString type;
    QString personName;
};

class MemoriesModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum MemoryRoles {
        MemoryIdRole = Qt::UserRole + 1,
        MemoryAtRole,
        YearRole,
        IsSavedRole,
        ThumbnailIdRole,
        ThumbhashRole,
        AssetCountRole,
        AssetsJsonRole,
        TypeRole,
        PersonNameRole
    };

    explicit MemoriesModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const {
        return m_memories.size();
    }
    Q_INVOKABLE void appendMemories(const QJsonArray &memories);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void setSaved(const QString &memoryId, bool saved);

signals:
    void countChanged();

private:
    QList<Memory> m_memories;
};

#endif
