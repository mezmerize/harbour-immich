#include "timelinemodel.h"
#include <QJsonObject>
#include <QJsonDocument>
#include <QDebug>
#include <QLocale>

TimelineModel::TimelineModel(QObject *parent)
   : QAbstractListModel(parent)
   , m_totalCount(0)
   , m_loading(false)
   , m_isFavoriteFilter(false)
{
}

int TimelineModel::rowCount(const QModelIndex &parent) const
{
   if (parent.isValid())
       return 0;
   return m_totalCount;
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
   return roles;
}

void TimelineModel::loadBuckets(const QJsonArray &bucketsJson)
{
   beginResetModel();
   m_buckets.clear();
   m_selectedIds.clear();
   m_assetIndex.clear();
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

       // Parse the timeBucket to create display strings
       bucket.dateTime = QDateTime::fromString(bucket.timeBucket, Qt::ISODate);
       if (bucket.dateTime.isValid()) {
           bucket.monthYear = bucket.dateTime.toString(QStringLiteral("MMMM yyyy"));
           bucket.date = bucket.dateTime.toString(QStringLiteral("dd.MM.yyyy"));
       } else {
           // Fallback - try parsing just the date part
           QString dateStr = bucket.timeBucket.left(10);
           QDate date = QDate::fromString(dateStr, Qt::ISODate);
           if (date.isValid()) {
               bucket.monthYear = QLocale().toString(date, QStringLiteral("MMMM yyyy"));
               bucket.date = date.toString(QStringLiteral("dd.MM.yyyy"));
               bucket.dateTime = QDateTime(date, QTime(0, 0));
           }
       }

       m_buckets.append(bucket);
       m_totalCount += bucket.count;
   }

   endResetModel();
   emit bucketCountChanged();
   emit totalCountChanged();
}

void TimelineModel::loadBucketAssets(const QString &timeBucket, const QJsonObject &bucketData)
{
   int bucketIndex = findBucketByTimeBucket(timeBucket);
   if (bucketIndex < 0) {
       qWarning() << "TimelineModel: Bucket not found for timeBucket:" << timeBucket;
       return;
   }

   TimelineBucket &bucket = m_buckets[bucketIndex];
   bucket.assets.clear();

   // Parse parallel arrays from bucket response
   QJsonArray ids = bucketData[QStringLiteral("id")].toArray();
   QJsonArray isImageArr = bucketData[QStringLiteral("isImage")].toArray();
   QJsonArray isFavoriteArr = bucketData[QStringLiteral("isFavorite")].toArray();
   QJsonArray fileCreatedAtArr = bucketData[QStringLiteral("fileCreatedAt")].toArray();
   QJsonArray thumbhashArr = bucketData[QStringLiteral("thumbhash")].toArray();

   int count = ids.size();
   bucket.assets.reserve(count);

   for (int i = 0; i < count; ++i) {
       TimelineAsset asset;
       asset.id = ids[i].toString();
       asset.isVideo = !isImageArr[i].toBool(); // isImage=false means video
       asset.isFavorite = isFavoriteArr[i].toBool();
       asset.createdAt = QDateTime::fromString(fileCreatedAtArr[i].toString(), Qt::ISODate);
       asset.thumbhash = i < thumbhashArr.size() ? thumbhashArr[i].toString() : QString();

       bucket.assets.append(asset);
       m_assetIndex[asset.id] = qMakePair(bucketIndex, bucket.assets.size() - 1);
   }

   bucket.loaded = true;
   bucket.loading = false;

   // Notify that data changed for this bucket
   emit dataChanged(index(bucketIndex), index(bucketIndex));
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

   TimelineBucket &bucket = m_buckets[bucketIndex];
   if (!bucket.loaded && !bucket.loading) {
       bucket.loading = true;
       emit bucketLoadRequested(bucket.timeBucket, m_isFavoriteFilter);
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
       assetMap[QStringLiteral("assetIndex")] = assetIndex++;

       groupedAssets[dateKey].append(assetMap);
   }

   // Build result maintaining chronological order (newest first)
   for (const QString &dateKey : dateOrder) {
       QVariantMap subGroup;
       QDate date = QDate::fromString(dateKey, Qt::ISODate);
       subGroup[QStringLiteral("date")] = dateKey;
       subGroup[QStringLiteral("displayDate")] = date.toString(QStringLiteral("dd.MM.yyyy"));
       subGroup[QStringLiteral("assets")] = groupedAssets[dateKey];
       subGroup[QStringLiteral("count")] = groupedAssets[dateKey].size();
       result.append(subGroup);
   }

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
   for (int i = 0; i < m_buckets.size(); ++i) {
       if (m_buckets.at(i).timeBucket == timeBucket)
           return i;
   }
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

QVariantMap TimelineModel::getAssetByAssetIndex(int assetIndex) const
{
   QVariantMap result;
   if (assetIndex < 0)
       return result;

   int currentIndex = 0;
   for (const TimelineBucket &bucket : m_buckets) {
       if (!bucket.loaded)
           continue;

       for (const TimelineAsset &asset : bucket.assets) {
           if (currentIndex == assetIndex) {
               result[QStringLiteral("id")] = asset.id;
               result[QStringLiteral("isFavorite")] = asset.isFavorite;
               result[QStringLiteral("isVideo")] = asset.isVideo;
               return result;
           }
           currentIndex++;
       }
   }
   return result;
}

int TimelineModel::getAssetIndexById(const QString &assetId) const
{
   int currentIndex = 0;
   for (const TimelineBucket &bucket : m_buckets) {
       if (!bucket.loaded)
           continue;

       for (const TimelineAsset &asset : bucket.assets) {
           if (asset.id == assetId) {
               return currentIndex;
           }
           currentIndex++;
       }
   }
   return -1;
}

void TimelineModel::updateFavorites(const QStringList &assetIds, bool isFavorite)
{
   for (const QString &assetId : assetIds) {
       auto it = m_assetIndex.find(assetId);
       if (it != m_assetIndex.end()) {
           int bucketIdx = it.value().first;
           int assetIdx = it.value().second;
           if (bucketIdx < m_buckets.size() && assetIdx < m_buckets[bucketIdx].assets.size()) {
               m_buckets[bucketIdx].assets[assetIdx].isFavorite = isFavorite;
           }
       }
   }
   emit dataChanged(index(0), index(m_buckets.size() - 1));
}

void TimelineModel::updateAssetMetadata(const QString &assetId, const QJsonObject &metadata)
{
   auto it = m_assetIndex.find(assetId);
   if (it != m_assetIndex.end()) {
       int bucketIdx = it.value().first;
       int assetIdx = it.value().second;
       if (bucketIdx < m_buckets.size() && assetIdx < m_buckets[bucketIdx].assets.size()) {
           TimelineAsset &asset = m_buckets[bucketIdx].assets[assetIdx];

           if (metadata.contains(QStringLiteral("isFavorite"))) {
               asset.isFavorite = metadata[QStringLiteral("isFavorite")].toBool();
           }
       }
   }
}

void TimelineModel::removeAssets(const QStringList &assetIds)
{
   QSet<QString> toRemove = QSet<QString>::fromList(assetIds);

   for (int b = 0; b < m_buckets.size(); ++b) {
       TimelineBucket &bucket = m_buckets[b];
       QMutableListIterator<TimelineAsset> it(bucket.assets);
       while (it.hasNext()) {
           if (toRemove.contains(it.next().id)) {
               it.remove();
               m_totalCount--;
           }
       }
   }

   // Remove from selection
   for (const QString &assetId : assetIds) {
       m_selectedIds.remove(assetId);
   }

   rebuildAssetIndex();
   emit totalCountChanged();
   emit selectedCountChanged();
   emit dataChanged(index(0), index(m_buckets.size() - 1));
}

void TimelineModel::scrollToAsset(const QString &assetId, const QString &dateString)
{
    // Find asset by index
    auto it = m_assetIndex.find(assetId);
    if (it != m_assetIndex.end()) {
        int bucketIndex = it.value().first;
        emit scrollToAssetRequested(assetId, bucketIndex);
        return;
    }

    // Find asset by date if it is too far in the past
    QDateTime assetDate = QDateTime::fromString(dateString, Qt::ISODate);
    if (!assetDate.isValid()) {
        return;
    }
    QString targetMonth = assetDate.toString(QStringLiteral("yyyy-MM"));

    for (int i = 0; i < m_buckets.size(); i++) {
        if (m_buckets[i].timeBucket.startsWith(targetMonth)) {
            emit scrollToAssetRequested(assetId, i);
            return;
        }
    }
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
   m_totalCount = 0;
   endResetModel();
   emit bucketCountChanged();
   emit totalCountChanged();
   emit selectedCountChanged();
}
