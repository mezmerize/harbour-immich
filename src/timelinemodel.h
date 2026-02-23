#ifndef TIMELINEMODEL_H
#define TIMELINEMODEL_H

#include <QAbstractListModel>
#include <QJsonArray>
#include <QDateTime>
#include <QSet>

struct TimelineAsset {
   QString id;
   bool isFavorite;
   bool isVideo;
   QDateTime createdAt;
   QString thumbhash;
};

struct TimelineBucket {
   QString timeBucket;      // ISO date string from API
   QDateTime dateTime;      // Parsed datetime for display
   QString monthYear;       // Display format: "January 2024"
   QString date;            // Display format: "01.01.2024"
   int count;               // Number of assets in bucket
   bool loaded;             // Whether assets have been fetched
   bool loading;            // Whether assets are currently being fetched
   QList<TimelineAsset> assets;
};

class TimelineModel : public QAbstractListModel
{
   Q_OBJECT
   Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
   Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectedCountChanged)
   Q_PROPERTY(bool loading READ loading WRITE setLoading NOTIFY loadingChanged)
   Q_PROPERTY(QString serverUrl READ serverUrl WRITE setServerUrl NOTIFY serverUrlChanged)
   Q_PROPERTY(int bucketCount READ bucketCount NOTIFY bucketCountChanged)

public:
   enum AssetRoles {
       IdRole = Qt::UserRole + 1,
       IsFavoriteRole,
       IsSelectedRole,
       IsVideoRole,
       IsGroupHeaderRole,
       GroupTitleRole,
       GroupSubtitleRole,
       GroupIndexRole
   };

   explicit TimelineModel(QObject *parent = nullptr);

   int rowCount(const QModelIndex &parent = QModelIndex()) const override;
   QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
   QHash<int, QByteArray> roleNames() const override;

   // Bucket management
   Q_INVOKABLE void loadBuckets(const QJsonArray &bucketsJson);
   Q_INVOKABLE void loadBucketAssets(const QString &timeBucket, const QJsonObject &bucketData);
   Q_INVOKABLE bool isBucketLoaded(int bucketIndex) const;
   Q_INVOKABLE void requestBucketLoad(int bucketIndex);
   Q_INVOKABLE int getBucketCount() const;
   Q_INVOKABLE QVariantMap getBucketAt(int index) const;
   Q_INVOKABLE QVariantList getBucketAssets(int bucketIndex) const;
   Q_INVOKABLE QVariantList getBucketSubGroups(int bucketIndex) const;
   Q_INVOKABLE QString getBucketTimeBucket(int bucketIndex) const;

   // Selection
   Q_INVOKABLE void toggleSelection(int bucketIndex, int assetIndex);
   Q_INVOKABLE void clearSelection();
   Q_INVOKABLE QStringList getSelectedAssetIds() const;
   Q_INVOKABLE bool isAssetSelected(const QString &assetId) const;
   Q_INVOKABLE bool areAllSelectedFavorites() const;
   Q_INVOKABLE bool areAnySelectedFavorites() const;

   // Asset updates
   Q_INVOKABLE void updateFavorites(const QStringList &assetIds, bool isFavorite);
   Q_INVOKABLE void updateAssetMetadata(const QString &assetId, const QJsonObject &metadata);
   Q_INVOKABLE void removeAssets(const QStringList &assetIds);
   Q_INVOKABLE void scrollToAsset(const QString &assetId, const QString &dateString);

   Q_INVOKABLE QVariantMap getAssetByAssetIndex(int assetIndex) const;
   Q_INVOKABLE int getAssetIndexById(const QString &assetId) const;

   // Properties
   int totalCount() const;
   int selectedCount() const;
   bool loading() const;
   Q_INVOKABLE void setLoading(bool loading);
   QString serverUrl() const;
   Q_INVOKABLE void setServerUrl(const QString &url);
   int bucketCount() const;

   Q_INVOKABLE void clear();

   // Filter state
   bool isFavoriteFilter() const;
   Q_INVOKABLE void setFavoriteFilter(bool isFavorite);

signals:
   void totalCountChanged();
   void selectedCountChanged();
   void loadingChanged();
   void serverUrlChanged();
   void bucketCountChanged();
   void favoriteFilterChanged();
   void bucketLoadRequested(const QString &timeBucket, bool isFavorite);
   void assetMetadataRequested(const QString &assetId);
   void scrollToAssetRequested(const QString &assetId, int bucketIndex);

private:
   QList<TimelineBucket> m_buckets;
   QSet<QString> m_selectedIds;
   QHash<QString, QPair<int, int>> m_assetIndex; // assetId -> (bucketIndex, assetIndex)
   int m_totalCount;
   bool m_loading;
   QString m_serverUrl;
   bool m_isFavoriteFilter;

   void rebuildAssetIndex();
   int findBucketByTimeBucket(const QString &timeBucket) const;
};

#endif
