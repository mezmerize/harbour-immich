#include "memoriesmodel.h"
#include <QJsonDocument>
#include <QDate>

MemoriesModel::MemoriesModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int MemoriesModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_memories.size();
}

QVariant MemoriesModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_memories.size())
        return QVariant();

    const Memory &m = m_memories.at(index.row());
    switch (role) {
    case MemoryIdRole: return m.id;
    case MemoryAtRole: return m.memoryAt;
    case YearRole: return m.year;
    case IsSavedRole: return m.isSaved;
    case ThumbnailIdRole: return m.thumbnailId;
    case ThumbhashRole: return m.thumbhash;
    case AssetCountRole: return m.assetCount;
    case AssetsJsonRole: return m.assetsJson;
    default: return QVariant();
    }
}

QHash<int, QByteArray> MemoriesModel::roleNames() const
{
    return {
        { MemoryIdRole, "memoryId" },
        { MemoryAtRole, "memoryDate" },
        { YearRole, "memoryYear" },
        { IsSavedRole, "isSaved" },
        { ThumbnailIdRole, "thumbnailId" },
        { ThumbhashRole, "thumbhash" },
        { AssetCountRole, "assetCount" },
        { AssetsJsonRole, "assetsJson" }
    };
}

void MemoriesModel::setTotalCount(int total)
{
    if (m_totalCount == total)
        return;
    m_totalCount = total;
    emit totalCountChanged();
}

void MemoriesModel::appendMemories(const QJsonArray &memories)
{
    if (memories.isEmpty())
        return;

    beginInsertRows(QModelIndex(), m_memories.size(), m_memories.size() + memories.size() - 1);
    for (const QJsonValue &value : memories) {
        const QJsonObject o = value.toObject();
        Memory m;
        m.id = o.value(QStringLiteral("id")).toString();
        m.memoryAt = o.value(QStringLiteral("memoryAt")).toString();
        m.isSaved = o.value(QStringLiteral("isSaved")).toBool();

        const QJsonObject data = o.value(QStringLiteral("data")).toObject();
        m.year = data.value(QStringLiteral("year")).toInt();

        const QJsonArray assets = o.value(QStringLiteral("assets")).toArray();
        m.assetCount = assets.size();
        m.assetsJson = QString::fromUtf8(QJsonDocument(assets).toJson(QJsonDocument::Compact));
        if (!assets.isEmpty()) {
            const QJsonObject first = assets.first().toObject();
            m.thumbnailId = first.value(QStringLiteral("id")).toString();
            m.thumbhash = first.value(QStringLiteral("thumbhash")).toString();
        }
        if (m.year == 0 && !m.memoryAt.isEmpty()) {
            m.year = QDate::fromString(m.memoryAt.left(10), Qt::ISODate).year();
        }
        m_memories.append(m);
    }
    endInsertRows();
    emit countChanged();
}

void MemoriesModel::clear()
{
    if (m_memories.isEmpty())
        return;
    beginResetModel();
    m_memories.clear();
    endResetModel();
    emit countChanged();
}

void MemoriesModel::setSaved(const QString &memoryId, bool saved)
{
    for (int i = 0; i < m_memories.size(); ++i) {
        if (m_memories.at(i).id == memoryId) {
            if (m_memories[i].isSaved == saved)
                return;
            m_memories[i].isSaved = saved;
            const QModelIndex idx = index(i, 0);
            emit dataChanged(idx, idx, { IsSavedRole });
            return;
        }
    }
}
