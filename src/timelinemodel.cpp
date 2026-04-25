#include "timelinemodel.h"
#include <QJsonObject>
#include <QJsonDocument>
#include <QDebug>
#include <QLocale>
#include <limits>

namespace {
const int MaxConcurrentBucketLoads = 2;
const int MaxQueuedBucketLoads = 4;
}

TimelineModel::TimelineModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_totalCount(0)
    , m_loading(false)
    , m_isFavoriteFilter(false)
    , m_pendingScrollBucketIndex(-1)
    , m_activeBucketLoads(0)
{
}

int TimelineModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_buckets.size();
}

QVariant TimelineModel::data(const QModelIndex &index, int role) const
{
    Q_UNUSED(index)
    Q_UNUSED(role)
    // This model doesn't use traditional row-based access
    // QML accesses data through getBucketAt() and getBucketAssets()
    return QVariant();
}

QHash<int, QByteArray> TimelineModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "assetId";
    roles[IsFavoriteRole] = "isFavorite";
    roles[IsSelectedRole] = "isSelected";
    roles[IsVideoRole] = "isVideo";
    roles[IsGroupHeaderRole] = "isGroupHeader";
    roles[GroupTitleRole] = "groupTitle";
    roles[GroupSubtitleRole] = "groupSubtitle";
    roles[GroupIndexRole] = "groupIndex";
    roles[StackIdRole] = "stackId";
    roles[StackAssetCountRole] = "stackAssetCount";
    return roles;
}

void TimelineModel::loadBuckets(const QJsonArray &bucketsJson)
{
    qInfo() << "TimelineModel: Loading" << bucketsJson.size() << "buckets";
    beginResetModel();
    m_buckets.clear();
    m_selectedIds.clear();
    m_assetIndex.clear();
    m_bucketIndex.clear();
    m_bucketOffsets.clear();
    m_bucketLoadQueue.clear();
    m_activeBucketLoads = 0;
    m_totalCount = 0;

    for (const QJsonValue &value : bucketsJson) {
        QJsonObject obj = value.toObject();
        int count = obj[QStringLiteral("count")].toInt();
        // Skip empty buckets (e.g. months with no favorites)
        if (count <= 0) {
            continue;
        }
        TimelineBucket bucket;
        bucket.timeBucket = obj[QStringLiteral("timeBucket")].toString();
        bucket.count = count;
        bucket.loaded = false;
        bucket.loading = false;
        bucket.cachedSubGroups.clear();
        bucket.subGroupsDirty = true;

        // Parse the timeBucket to create display strings
        bucket.dateTime = QDateTime::fromString(bucket.timeBucket, Qt::ISODate);
        if (bucket.dateTime.isValid()) {
            bucket.monthYear = QLocale().toString(bucket.dateTime, QStringLiteral("MMMM yyyy"));
            bucket.date = QLocale().toString(bucket.dateTime, QStringLiteral("dd.MM.yyyy"));
        } else {
            // Fallback - try parsing just the date part
            QString dateStr = bucket.timeBucket.left(10);
            QDate date = QDate::fromString(dateStr, Qt::ISODate);
            if (date.isValid()) {
                bucket.monthYear = QLocale().toString(date, QStringLiteral("MMMM yyyy"));
                bucket.date = QLocale().toString(date, QStringLiteral("dd.MM.yyyy"));
                bucket.dateTime = QDateTime(date, QTime(0, 0));
            }
        }

        m_bucketOffsets.append(m_totalCount);
        m_bucketIndex[bucket.timeBucket] = m_buckets.size();
        m_buckets.append(bucket);
        m_totalCount += bucket.count;
    }

    endResetModel();
    qInfo() << "TimelineModel: Loaded" << m_buckets.size() << "buckets, total assets:" << m_totalCount;
    emit bucketCountChanged();
    emit totalCountChanged();
    emit selectedCountChanged();
}

void TimelineModel::loadBucketAssets(const QString &timeBucket, const QJsonObject &bucketData)
{
    qInfo() << "TimelineModel: Loading assets for bucket:" << timeBucket;
    int bucketIndex = findBucketByTimeBucket(timeBucket);
    if (bucketIndex < 0) {
        qWarning() << "TimelineModel: Bucket not found for timeBucket:" << timeBucket;
        return;
    }

    TimelineBucket &bucket = m_buckets[bucketIndex];
    bucket.assets.clear();
    bucket.cachedSubGroups.clear();
    bucket.subGroupsDirty = true;

    // Parse parallel arrays from bucket response
    QJsonArray ids = bucketData[QStringLiteral("id")].toArray();
    QJsonArray isImageArr = bucketData[QStringLiteral("isImage")].toArray();
    QJsonArray isFavoriteArr = bucketData[QStringLiteral("isFavorite")].toArray();
    QJsonArray fileCreatedAtArr = bucketData[QStringLiteral("fileCreatedAt")].toArray();
    QJsonArray thumbhashArr = bucketData[QStringLiteral("thumbhash")].toArray();
    QJsonArray durationArr = bucketData[QStringLiteral("duration")].toArray();
    QJsonArray stackArr = bucketData[QStringLiteral("stack")].toArray();

    int count = ids.size();
    bucket.assets.reserve(count);

    for (int i = 0; i < count; ++i) {
        TimelineAsset asset;
        asset.id = ids[i].toString();
        asset.isVideo = !isImageArr[i].toBool(); // isImage=false means video
        asset.isFavorite = isFavoriteArr[i].toBool();
        asset.createdAt = QDateTime::fromString(fileCreatedAtArr[i].toString(), Qt::ISODate);
        asset.thumbhash = i < thumbhashArr.size() ? thumbhashArr[i].toString() : QString();
        asset.duration = i < durationArr.size() ? durationArr[i].toString() : QString();

        // Parse stack info: null means not a stack, array has id + assetCount
        if (i < stackArr.size() && stackArr[i].isArray()) {
            QJsonArray stackEntry = stackArr[i].toArray();
            asset.stackId = stackEntry.size() > 0 ? stackEntry[0].toString() : QString();
            asset.stackAssetCount = stackEntry.size() > 1 ? stackEntry[1].toString().toInt() : 0;
        } else {
            asset.stackId = QString();
            asset.stackAssetCount = 0;
        }

        bucket.assets.append(asset);
        m_assetIndex[asset.id] = qMakePair(bucketIndex, bucket.assets.size() - 1);
    }

    bucket.loaded = true;
    bucket.loading = false;
    if (m_activeBucketLoads > 0) {
        --m_activeBucketLoads;
    }

    // Notify that data changed for this bucket
    emit dataChanged(index(bucketIndex), index(bucketIndex));
    emit bucketAssetsLoaded(bucketIndex);

    if (m_pendingScrollBucketIndex == bucketIndex) {
        resolvePendingScroll(bucketIndex);
    }

    processQueuedBucketLoads();
}

bool TimelineModel::isBucketLoaded(int bucketIndex) const
{
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return false;
    return m_buckets.at(bucketIndex).loaded;
}

void TimelineModel::requestBucketLoad(int bucketIndex)
{
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return;

    const TimelineBucket &bucket = m_buckets.at(bucketIndex);
    if (bucket.loaded || bucket.loading)
        return;

    if (m_activeBucketLoads < MaxConcurrentBucketLoads) {
        dispatchBucketLoad(bucketIndex);
        return;
    }

    if (m_bucketLoadQueue.contains(bucketIndex))
        m_bucketLoadQueue.removeAll(bucketIndex);

    if (bucketIndex == m_pendingScrollBucketIndex) {
        m_bucketLoadQueue.prepend(bucketIndex);
    } else {
        while (m_bucketLoadQueue.size() >= MaxQueuedBucketLoads) {
            int droppedIndex = m_bucketLoadQueue.dequeue();
            if (droppedIndex == m_pendingScrollBucketIndex) {
                m_bucketLoadQueue.prepend(droppedIndex);
                break;
            }
        }
        m_bucketLoadQueue.enqueue(bucketIndex);
    }
}

void TimelineModel::dispatchBucketLoad(int bucketIndex)
{
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return;

    TimelineBucket &bucket = m_buckets[bucketIndex];
    if (bucket.loaded || bucket.loading)
        return;

    bucket.loading = true;
    ++m_activeBucketLoads;
    emit bucketLoadRequested(bucket.timeBucket, m_isFavoriteFilter);
}

void TimelineModel::processQueuedBucketLoads()
{
    while (m_activeBucketLoads < MaxConcurrentBucketLoads && !m_bucketLoadQueue.isEmpty()) {
        int bucketIndex;
        if (!m_bucketLoadQueue.isEmpty() && m_bucketLoadQueue.head() == m_pendingScrollBucketIndex) {
            bucketIndex = m_bucketLoadQueue.dequeue();
        } else {
            bucketIndex = m_bucketLoadQueue.takeLast();
        }
        if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
            continue;

        const TimelineBucket &bucket = m_buckets.at(bucketIndex);
        if (bucket.loaded || bucket.loading)
            continue;

        dispatchBucketLoad(bucketIndex);
    }
    if (m_activeBucketLoads == 0 && m_bucketLoadQueue.isEmpty()) {
        emit bucketLoadsIdle();
    }
}

int TimelineModel::getBucketCount() const
{
    return m_buckets.size();
}

QVariantMap TimelineModel::getBucketAt(int index) const
{
    QVariantMap result;
    if (index < 0 || index >= m_buckets.size())
        return result;

    const TimelineBucket &bucket = m_buckets.at(index);
    result[QStringLiteral("timeBucket")] = bucket.timeBucket;
    result[QStringLiteral("monthYear")] = bucket.monthYear;
    result[QStringLiteral("date")] = bucket.date;
    result[QStringLiteral("count")] = bucket.count;
    result[QStringLiteral("loaded")] = bucket.loaded;
    return result;
}

QVariantList TimelineModel::getBucketAssets(int bucketIndex) const
{
    QVariantList result;
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return result;

    const TimelineBucket &bucket = m_buckets.at(bucketIndex);
    if (!bucket.loaded)
        return result;

    int assetIndex = 0;
    for (const TimelineAsset &asset : bucket.assets) {
        QVariantMap assetMap;
        assetMap[QStringLiteral("id")] = asset.id;
        assetMap[QStringLiteral("isFavorite")] = asset.isFavorite;
        assetMap[QStringLiteral("isVideo")] = asset.isVideo;
        assetMap[QStringLiteral("thumbhash")] = asset.thumbhash;
        assetMap[QStringLiteral("duration")] = asset.duration;
        assetMap[QStringLiteral("stackId")] = asset.stackId;
        assetMap[QStringLiteral("stackAssetCount")] = asset.stackAssetCount;
        assetMap[QStringLiteral("assetIndex")] = assetIndex++;
        result.append(assetMap);
    }
    return result;
}

QVariantList TimelineModel::getBucketSubGroups(int bucketIndex) const
{
    QVariantList result;
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return result;

    const TimelineBucket &bucket = m_buckets.at(bucketIndex);
    if (!bucket.loaded || bucket.assets.isEmpty())
        return result;

    if (!bucket.subGroupsDirty) {
        return bucket.cachedSubGroups;
    }

    int globalBaseIndex = m_bucketOffsets.value(bucketIndex, 0);

    // Group assets by date (day)
    QMap<QString, QVariantList> groupedAssets;
    QStringList dateOrder; // To maintain order

    int assetIndex = 0;
    for (const TimelineAsset &asset : bucket.assets) {
        QString dateKey = asset.createdAt.date().toString(Qt::ISODate);

        if (!groupedAssets.contains(dateKey)) {
            dateOrder.append(dateKey);
            groupedAssets[dateKey] = QVariantList();
        }

        QVariantMap assetMap;
        assetMap[QStringLiteral("id")] = asset.id;
        assetMap[QStringLiteral("isFavorite")] = asset.isFavorite;
        assetMap[QStringLiteral("isVideo")] = asset.isVideo;
        assetMap[QStringLiteral("thumbhash")] = asset.thumbhash;
        assetMap[QStringLiteral("duration")] = asset.duration;
        assetMap[QStringLiteral("stackId")] = asset.stackId;
        assetMap[QStringLiteral("stackAssetCount")] = asset.stackAssetCount;
        assetMap[QStringLiteral("assetIndex")] = assetIndex++;
        assetMap[QStringLiteral("globalIndex")] = globalBaseIndex + assetIndex - 1;

        groupedAssets[dateKey].append(assetMap);
    }

    // Build result maintaining chronological order (newest first)
    for (const QString &dateKey : dateOrder) {
        QVariantMap subGroup;
        QDate date = QDate::fromString(dateKey, Qt::ISODate);
        subGroup[QStringLiteral("date")] = dateKey;
        subGroup[QStringLiteral("displayDate")] = QLocale().toString(date, QStringLiteral("dd.MM.yyyy"));
        subGroup[QStringLiteral("assets")] = groupedAssets[dateKey];
        subGroup[QStringLiteral("count")] = groupedAssets[dateKey].size();
        result.append(subGroup);
    }

    bucket.cachedSubGroups = result;
    bucket.subGroupsDirty = false;
    return result;
}

QString TimelineModel::getBucketTimeBucket(int bucketIndex) const
{
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return QString();
    return m_buckets.at(bucketIndex).timeBucket;
}

int TimelineModel::findBucketByTimeBucket(const QString &timeBucket) const
{
    auto it = m_bucketIndex.find(timeBucket);
    if (it != m_bucketIndex.end())
        return it.value();
    return -1;
}

void TimelineModel::rebuildAssetIndex()
{
    m_assetIndex.clear();
    for (int b = 0; b < m_buckets.size(); ++b) {
        const TimelineBucket &bucket = m_buckets.at(b);
        for (int a = 0; a < bucket.assets.size(); ++a) {
            m_assetIndex[bucket.assets.at(a).id] = qMakePair(b, a);
        }
    }
}

void TimelineModel::rebuildBucketOffsets()
{
    m_bucketOffsets.clear();
    int offset = 0;
    for (int b = 0; b < m_buckets.size(); ++b) {
        m_bucketOffsets.append(offset);
        offset += m_buckets.at(b).count;
    }
}

int TimelineModel::findBucketByAssetIndex(int assetIndex) const
{
    for (int b = 0; b < m_buckets.size(); ++b) {
        int bucketStart = m_bucketOffsets.value(b, -1);
        if (bucketStart < 0) {
            continue;
        }
        if (assetIndex >= bucketStart && assetIndex < bucketStart + m_buckets.at(b).count) {
            return b;
        }
    }
    return -1;
}

void TimelineModel::toggleSelection(int bucketIndex, int assetIndex)
{
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return;

    const TimelineBucket &bucket = m_buckets.at(bucketIndex);
    if (assetIndex < 0 || assetIndex >= bucket.assets.size())
        return;

    const QString &assetId = bucket.assets.at(assetIndex).id;
    if (m_selectedIds.contains(assetId)) {
        m_selectedIds.remove(assetId);
    } else {
        m_selectedIds.insert(assetId);
    }
    emit selectedCountChanged();
}

void TimelineModel::clearSelection()
{
    m_selectedIds.clear();
    emit selectedCountChanged();
}

QStringList TimelineModel::getSelectedAssetIds() const
{
    return m_selectedIds.values();
}

bool TimelineModel::isAssetSelected(const QString &assetId) const
{
    return m_selectedIds.contains(assetId);
}

bool TimelineModel::areAllSelectedFavorites() const
{
    if (m_selectedIds.isEmpty())
        return false;

    for (const QString &assetId : m_selectedIds) {
        auto it = m_assetIndex.find(assetId);
        if (it != m_assetIndex.end()) {
            int bucketIdx = it.value().first;
            int assetIdx = it.value().second;
            if (bucketIdx < m_buckets.size() && assetIdx < m_buckets.at(bucketIdx).assets.size()) {
                if (!m_buckets.at(bucketIdx).assets.at(assetIdx).isFavorite)
                    return false;
            }
        }
    }
    return true;
}

bool TimelineModel::areAnySelectedFavorites() const
{
    for (const QString &assetId : m_selectedIds) {
        auto it = m_assetIndex.find(assetId);
        if (it != m_assetIndex.end()) {
            int bucketIdx = it.value().first;
            int assetIdx = it.value().second;
            if (bucketIdx < m_buckets.size() && assetIdx < m_buckets.at(bucketIdx).assets.size()) {
                if (m_buckets.at(bucketIdx).assets.at(assetIdx).isFavorite)
                    return true;
            }
        }
    }
    return false;
}

bool TimelineModel::isAnySelectedAStack() const
{
    for (const QString &assetId : m_selectedIds) {
        auto it = m_assetIndex.find(assetId);
        if (it != m_assetIndex.end()) {
            int bucketIdx = it.value().first;
            int assetIdx = it.value().second;
            if (bucketIdx < m_buckets.size() && assetIdx < m_buckets.at(bucketIdx).assets.size()) {
                if (!m_buckets.at(bucketIdx).assets.at(assetIdx).stackId.isEmpty())
                    return true;
            }
        }
    }
    return false;
}

QVariantMap TimelineModel::getAssetByAssetIndex(int assetIndex) const
{
    QVariantMap result;
    if (assetIndex < 0 || assetIndex >= m_totalCount)
        return result;

    int bucketIdx = findBucketByAssetIndex(assetIndex);
    if (bucketIdx < 0 || bucketIdx >= m_buckets.size())
        return result;

    const TimelineBucket &bucket = m_buckets.at(bucketIdx);
    if (!bucket.loaded)
        return result;

    int assetIdx = assetIndex - m_bucketOffsets.value(bucketIdx, 0);
    if (assetIdx < 0 || assetIdx >= bucket.assets.size())
        return result;

    const TimelineAsset &asset = bucket.assets.at(assetIdx);
    result[QStringLiteral("id")] = asset.id;
    result[QStringLiteral("isFavorite")] = asset.isFavorite;
    result[QStringLiteral("isVideo")] = asset.isVideo;
    result[QStringLiteral("duration")] = asset.duration;
    result[QStringLiteral("stackId")] = asset.stackId;
    result[QStringLiteral("stackAssetCount")] = asset.stackAssetCount;
    result[QStringLiteral("thumbhash")] = asset.thumbhash;
    return result;
}

QVariantMap TimelineModel::getAssetLocation(int assetIndex) const
{
    QVariantMap result;
    if (assetIndex < 0 || assetIndex >= m_totalCount)
        return result;

    int bucketIdx = findBucketByAssetIndex(assetIndex);
    if (bucketIdx < 0 || bucketIdx >= m_buckets.size())
        return result;

    int assetIdx = assetIndex - m_bucketOffsets.value(bucketIdx, 0);
    result[QStringLiteral("bucketIndex")] = bucketIdx;
    result[QStringLiteral("assetIndex")] = assetIdx;
    result[QStringLiteral("loaded")] = m_buckets.at(bucketIdx).loaded;
    return result;
}

int TimelineModel::getAssetIndexById(const QString &assetId) const
{
    auto it = m_assetIndex.find(assetId);
    if (it != m_assetIndex.end()) {
        int bucketIdx = it.value().first;
        int assetIdx = it.value().second;
        return m_bucketOffsets.value(bucketIdx, 0) + assetIdx;
    }
    return -1;
}

void TimelineModel::updateFavorites(const QStringList &assetIds, bool isFavorite)
{
    QSet<int> affectedBuckets;
    for (const QString &assetId : assetIds) {
        auto it = m_assetIndex.find(assetId);
        if (it != m_assetIndex.end()) {
            int bucketIdx = it.value().first;
            int assetIdx = it.value().second;
            if (bucketIdx < m_buckets.size() && assetIdx < m_buckets[bucketIdx].assets.size()) {
                m_buckets[bucketIdx].assets[assetIdx].isFavorite = isFavorite;
                m_buckets[bucketIdx].cachedSubGroups.clear();
                m_buckets[bucketIdx].subGroupsDirty = true;
                affectedBuckets.insert(bucketIdx);
            }
        }
    }
    for (int bucketIdx : affectedBuckets) {
        emit dataChanged(index(bucketIdx), index(bucketIdx));
        emit bucketDataUpdated(bucketIdx);
    }
}

void TimelineModel::removeAssets(const QStringList &assetIds)
{
    QSet<QString> toRemove = QSet<QString>::fromList(assetIds);
    QSet<int> affectedBuckets;

    for (int b = 0; b < m_buckets.size(); ++b) {
        TimelineBucket &bucket = m_buckets[b];
        bool changed = false;
        QMutableListIterator<TimelineAsset> it(bucket.assets);
        while (it.hasNext()) {
            if (toRemove.contains(it.next().id)) {
                it.remove();
                bucket.count--;
                m_totalCount--;
                changed = true;
            }
        }
        if (changed) {
            bucket.cachedSubGroups.clear();
            bucket.subGroupsDirty = true;
            affectedBuckets.insert(b);
        }
    }

    // Remove from selection
    for (const QString &assetId : assetIds) {
        m_selectedIds.remove(assetId);
    }

    rebuildAssetIndex();
    rebuildBucketOffsets();
    emit totalCountChanged();
    emit selectedCountChanged();
    emit dataChanged(index(0), index(m_buckets.size() - 1));
    for (int bucketIdx : affectedBuckets) {
        emit bucketDataUpdated(bucketIdx);
    }
}

void TimelineModel::scrollToAsset(const QString &assetId, const QString &dateString)
{
    // Try exact ID lookup
    auto it = m_assetIndex.find(assetId);
    if (it != m_assetIndex.end()) {
        int bucketIndex = it.value().first;
        int assetIndexInBucket = it.value().second;
        emit scrollToAssetRequested(assetId, bucketIndex, assetIndexInBucket);
        return;
    }

    // Find asset by date if it is too far in the past
    QDateTime assetDate = QDateTime::fromString(dateString, Qt::ISODate);
    int targetBucket = -1;
    if (assetDate.isValid()) {
        // First try the exact month match
        QString targetMonth = assetDate.toString(QStringLiteral("yyyy-MM"));
        for (int i = 0; i < m_buckets.size(); i++) {
            if (m_buckets[i].timeBucket.startsWith(targetMonth)) {
                targetBucket = i;
                break;
            }
        }

        // If no exact match find closest bucket by date
        if (targetBucket < 0) {
            targetBucket = findClosestBucketByDate(assetDate);
        }
    }

    if (targetBucket < 0) {
        qWarning() << "TimelineModel: Could not find bucket for asset" << assetId << "date:" << dateString;
        return;
    }

    // If bucket is already loaded try to find asset in it
    if (m_buckets[targetBucket].loaded) {
        const auto &assets = m_buckets[targetBucket].assets;
        for (int i = 0; i < assets.size(); i++) {
            if (assets[i].id == assetId) {
                emit scrollToAssetRequested(assetId, targetBucket, i);
                return;
            }
        }
        // Asset not in this bucket, scroll to bucket top
        emit scrollToAssetRequested(assetId, targetBucket, -1);
    } else {
        // Bucket not loaded - store pending scroll and request load
        m_pendingScrollAssetId = assetId;
        m_pendingScrollBucketIndex = targetBucket;
        requestBucketLoad(targetBucket);
    }
}

void TimelineModel::resolvePendingScroll(int bucketIndex)
{
    if (m_pendingScrollAssetId.isEmpty() || m_pendingScrollBucketIndex != bucketIndex) {
        return;
    }

    QString assetId = m_pendingScrollAssetId;
    m_pendingScrollAssetId.clear();
    m_pendingScrollBucketIndex = -1;

    // Find exact asset position in the now loaded bucket
    const auto &assets = m_buckets[bucketIndex].assets;
    for (int i = 0; i < assets.size(); i++) {
        if (assets[i].id == assetId) {
            emit scrollToAssetRequested(assetId, bucketIndex, i);
            return;
        }
    }
    // Asset not in this bucket, scroll to bucket top
    emit scrollToAssetRequested(assetId, bucketIndex, -1);
}

int TimelineModel::findClosestBucketByDate(const QDateTime &date) const
{
    if (m_buckets.isEmpty()) return -1;

    int closestIndex = -1;
    qint64 closestDiff = std::numeric_limits<qint64>::max();

    for (int i = 0; i < m_buckets.size(); i++) {
        if (!m_buckets[i].dateTime.isValid()) continue;
        qint64 diff = qAbs(m_buckets[i].dateTime.secsTo(date));
        if (diff < closestDiff) {
            closestDiff = diff;
            closestIndex = i;
        }
    }

    return closestIndex;
}

int TimelineModel::totalCount() const
{
    return m_totalCount;
}

int TimelineModel::selectedCount() const
{
    return m_selectedIds.size();
}

bool TimelineModel::loading() const
{
    return m_loading;
}

void TimelineModel::setLoading(bool loading)
{
    if (m_loading != loading) {
        m_loading = loading;
        emit loadingChanged();
    }
}

QString TimelineModel::serverUrl() const
{
    return m_serverUrl;
}

void TimelineModel::setServerUrl(const QString &url)
{
    if (m_serverUrl != url) {
        m_serverUrl = url;
        emit serverUrlChanged();
    }
}

int TimelineModel::bucketCount() const
{
    return m_buckets.size();
}

bool TimelineModel::isFavoriteFilter() const
{
    return m_isFavoriteFilter;
}

void TimelineModel::setFavoriteFilter(bool isFavorite)
{
    if (m_isFavoriteFilter != isFavorite) {
        m_isFavoriteFilter = isFavorite;
        emit favoriteFilterChanged();
    }
}

void TimelineModel::clear()
{
    beginResetModel();
    m_buckets.clear();
    m_selectedIds.clear();
    m_assetIndex.clear();
    m_bucketIndex.clear();
    m_bucketOffsets.clear();
    m_bucketLoadQueue.clear();
    m_activeBucketLoads = 0;
    m_totalCount = 0;
    endResetModel();
    emit bucketCountChanged();
    emit totalCountChanged();
    emit selectedCountChanged();
}
