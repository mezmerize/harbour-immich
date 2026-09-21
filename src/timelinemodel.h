#ifndef TIMELINEMODEL_H
#define TIMELINEMODEL_H

#include <QAbstractListModel>
#include <QJsonArray>
#include <QDateTime>
#include <QVariantList>
#include <QSet>
#include <QQueue>

class ImmichApi;

struct TimelineAsset {
    QString id;
    QString ownerId;
    bool isFavorite;
    bool isVideo;
    QDateTime createdAt;
    QString thumbhash;
    QString duration;
    QString stackId;
    QString livePhotoVideoId;
    int stackAssetCount;
};

struct TimelineBucket {
    QString timeBucket;      // ISO date string from API
    QDateTime dateTime;      // Parsed datetime for display
    QString monthYear;       // Display format: "January 2024"
    QString date;            // Display format: "01.01.2024"
    int count;               // Number of assets in bucket
    bool loaded;             // Whether assets have been fetched
    bool loading;            // Whether assets are currently being fetched
    int loadAttempts;        // Number of fetch attempts
    QList<TimelineAsset> assets;
    mutable QVariantList cachedSubGroups;
    mutable bool subGroupsDirty;
};

class TimelineModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectedCountChanged)
    Q_PROPERTY(bool loading READ loading WRITE setLoading NOTIFY loadingChanged)
    Q_PROPERTY(QString serverUrl READ serverUrl WRITE setServerUrl NOTIFY serverUrlChanged)
    Q_PROPERTY(int bucketCount READ bucketCount NOTIFY bucketCountChanged)
    Q_PROPERTY(bool groupByCreatedAt READ groupByCreatedAt WRITE setGroupByCreatedAt NOTIFY groupByCreatedAtChanged)
    Q_PROPERTY(QObject* api READ api WRITE setApi NOTIFY apiChanged)
    Q_PROPERTY(QString context READ context WRITE setContext NOTIFY contextChanged)
    Q_PROPERTY(QVariantMap queryParams READ queryParams WRITE setQueryParams NOTIFY queryParamsChanged)

public:
    explicit TimelineModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    Q_INVOKABLE void fetchBuckets();

    // Bucket management
    Q_INVOKABLE bool isBucketLoaded(int bucketIndex) const;
    Q_INVOKABLE void requestBucketLoad(int bucketIndex);
    Q_INVOKABLE int getBucketCount() const;
    Q_INVOKABLE QVariantMap getBucketAt(int index) const;
    Q_INVOKABLE QVariantList getBucketAssets(int bucketIndex) const;
    Q_INVOKABLE QStringList getLoadedAssetIds() const;
    Q_INVOKABLE QVariantList getBucketSubGroups(int bucketIndex) const;
    Q_INVOKABLE QString getBucketTimeBucket(int bucketIndex) const;

    // Selection
    Q_INVOKABLE void toggleSelection(int bucketIndex, int assetIndex);
    Q_INVOKABLE void setSelectionForAssets(const QStringList &assetIds, bool selected);
    Q_INVOKABLE bool areAllAssetsSelected(const QStringList &assetIds) const;
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE QStringList getSelectedAssetIds() const;
    Q_INVOKABLE bool isAssetSelected(const QString &assetId) const;
    Q_INVOKABLE bool areAllSelectedFavorites() const;
    Q_INVOKABLE bool areAnySelectedFavorites() const;
    Q_INVOKABLE bool isAnySelectedAStack() const;
    Q_INVOKABLE bool hasSelectedOtherOwner() const;
    Q_INVOKABLE void setUserId(const QString &userId);

    // Asset updates
    Q_INVOKABLE void updateFavorites(const QStringList &assetIds, bool isFavorite);
    Q_INVOKABLE void removeAssets(const QStringList &assetIds);
    Q_INVOKABLE void scrollToAsset(const QString &assetId, const QString &dateString);

    Q_INVOKABLE QVariantMap getAssetByAssetIndex(int assetIndex) const;
    Q_INVOKABLE QVariantMap getAssetLocation(int assetIndex) const;

    // Properties
    int totalCount() const;
    int selectedCount() const;
    bool loading() const;
    Q_INVOKABLE void setLoading(bool loading);
    QString serverUrl() const;
    Q_INVOKABLE void setServerUrl(const QString &url);
    int bucketCount() const;
    bool groupByCreatedAt() const;
    Q_INVOKABLE void setGroupByCreatedAt(bool value);
    QObject* api() const;
    Q_INVOKABLE void setApi(QObject *api);
    QString context() const;
    Q_INVOKABLE void setContext(const QString &context);
    QVariantMap queryParams() const;
    Q_INVOKABLE void setQueryParams(const QVariantMap &params);

    Q_INVOKABLE void clear();

signals:
    void totalCountChanged();
    void selectedCountChanged();
    void loadingChanged();
    void serverUrlChanged();
    void bucketCountChanged();
    void groupByCreatedAtChanged();
    void apiChanged();
    void contextChanged();
    void queryParamsChanged();
    void bucketsLoaded();
    void bucketDataUpdated(int bucketIndex);
    void scrollToAssetRequested(const QString &assetId, int bucketIndex, int assetIndexInBucket);
    void bucketAssetsLoaded(int bucketIndex);
    void bucketLoadsIdle();

private:
    QList<TimelineBucket> m_buckets;
    QSet<QString> m_selectedIds;
    QHash<QString, QPair<int, int>> m_assetIndex; // assetId -> (bucketIndex, assetIndex)
    QHash<QString, int> m_bucketIndex; // timeBucket -> index in m_buckets
    QList<int> m_bucketOffsets;
    int m_totalCount;
    bool m_loading;
    QString m_serverUrl;
    QString m_userId;
    bool m_groupByCreatedAt;
    ImmichApi *m_api;
    QString m_context;
    QVariantMap m_queryParams;

    void loadBuckets(const QJsonArray &bucketsJson);
    void loadBucketAssets(const QString &timeBucket, const QJsonObject &bucketData);
    void rebuildAssetIndex();
    void rebuildBucketOffsets();
    int findBucketByAssetIndex(int assetIndex) const;
    int findBucketByTimeBucket(const QString &timeBucket) const;
    int findClosestBucketByDate(const QDateTime &date) const;
    void markBucketLoadFailed(int bucketIndex);
    void resolvePendingScroll(int bucketIndex);
    void dispatchBucketLoad(int bucketIndex);
    void processQueuedBucketLoads();

    // Pending scroll state
    QString m_pendingScrollAssetId;
    int m_pendingScrollBucketIndex;
    QQueue<int> m_bucketLoadQueue;
    int m_activeBucketLoads;
};

#endif
