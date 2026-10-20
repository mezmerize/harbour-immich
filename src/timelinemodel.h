#ifndef TIMELINEMODEL_H
#define TIMELINEMODEL_H

#include <QObject>
#include <QDateTime>
#include <QVariantList>
#include <QVariantMap>
#include <QSet>
#include <QHash>
#include <QStringList>

class BackupManager;
class AssetDatabase;

struct TimelineAsset {
    QString id;
    QString ownerId;
    QString type;
    QString name;
    bool isFavorite = false;
    QDateTime createdAt;
    QString thumbhash;
    QString duration;
    QString stackId;
    QString livePhotoVideoId;
    int stackAssetCount = 0;
    bool isLocal = false;
    QString localPath;
};

inline bool operator==(const TimelineAsset &a, const TimelineAsset &b)
{
    return a.id == b.id && a.ownerId == b.ownerId && a.type == b.type
        && a.name == b.name && a.isFavorite == b.isFavorite
        && a.createdAt == b.createdAt && a.thumbhash == b.thumbhash
        && a.duration == b.duration && a.stackId == b.stackId
        && a.livePhotoVideoId == b.livePhotoVideoId
        && a.stackAssetCount == b.stackAssetCount && a.isLocal == b.isLocal
        && a.localPath == b.localPath;
}

inline bool operator!=(const TimelineAsset &a, const TimelineAsset &b)
{
    return !(a == b);
}

inline uint qHash(const TimelineAsset &a, uint seed = 0)
{
    auto mix = [&seed](uint h) {
        seed ^= h + 0x9e3779b9u + (seed << 6) + (seed >> 2);
    };
    mix(qHash(a.id));
    mix(qHash(a.ownerId));
    mix(qHash(a.type));
    mix(qHash(a.name));
    mix(uint(a.isFavorite));
    mix(qHash(a.createdAt));
    mix(qHash(a.thumbhash));
    mix(qHash(a.duration));
    mix(qHash(a.stackId));
    mix(qHash(a.livePhotoVideoId));
    mix(uint(a.stackAssetCount));
    mix(uint(a.isLocal));
    mix(qHash(a.localPath));
    return seed;
}

Q_DECLARE_METATYPE(TimelineAsset)
Q_DECLARE_METATYPE(QList<TimelineAsset>)
Q_DECLARE_METATYPE(QList<QList<TimelineAsset>>)

struct TimelineBucket {
    QString timeBucket; // Local day key: "YYYY-MM-DD"
    QDateTime dateTime; // Parsed datetime for display
    QString monthYear;  // Display format: "January 2024"
    QString date; // Display format: "01.01.2024"
    int count; // Number of assets in bucket
    bool loaded; // Whether assets have been fetched
    bool loading; // Whether assets are being fetched
    bool stale = false; // Loaded but the catalog changed
    int rowStart = -1; // First render row belonging to this bucket
    int rowEnd = -1; // Last render row belonging to this bucket
    QList<TimelineAsset> assets;
};

struct RenderRow {
    enum Type {
        MonthHeader = 0,
        DayHeader = 1,
        AssetRow = 2,
        Placeholder = 3
    };
    int type = Placeholder;
    int bucketIndex = -1;
    int firstAsset = 0; // Index into the assets list
    int assetCount = 0; // Assets covered by this row
    int firstGlobal = 0; // Global asset index of the first asset
    QString label; // Header text
    QString day; // Local day key of the owning bucket
    QString firstAssetId; // AssetRow: first asset ID
    qreal y = 0.0;
    qreal height = 0.0;
    mutable QVariantList cachedAssets;
    mutable uint contentKey = 0;
    mutable bool contentKeyValid = false;
};

class CatalogQueryWorker : public QObject
{
    Q_OBJECT
public:
    Q_INVOKABLE void refresh(quint64 gen, const QString &bucketSql, const QString &daySql, const QVariantList &binds, const QStringList &reloadDays, int preloadBudget);
    Q_INVOKABLE void queryDays(quint64 gen, const QString &sql, const QVariantList &binds, const QStringList &days);
    Q_INVOKABLE void resolveAssetDay(quint64 gen, const QString &sql, const QVariantList &binds, const QString &assetId);

signals:
    void refreshReady(quint64 gen, const QStringList &days, const QList<int> &counts, const QStringList &loadedDays, const QList<QList<TimelineAsset>> &assets, const QStringList &failedDays, bool ok);
    void daysReady(quint64 gen, const QStringList &days, const QList<QList<TimelineAsset>> &assets, const QStringList &failedDays);
    void assetDayResolved(quint64 gen, const QString &requestedId, const QString &resolvedId, const QString &day);
};

class TimelineModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectedCountChanged)
    Q_PROPERTY(bool loading READ loading WRITE setLoading NOTIFY loadingChanged)
    Q_PROPERTY(int bucketCount READ bucketCount NOTIFY bucketCountChanged)
    Q_PROPERTY(QString context READ context WRITE setContext NOTIFY contextChanged)
    Q_PROPERTY(QVariantMap queryParams READ queryParams WRITE setQueryParams NOTIFY queryParamsChanged)
    Q_PROPERTY(bool groupByCreatedAt READ groupByCreatedAt WRITE setGroupByCreatedAt NOTIFY groupByCreatedAtChanged)
    Q_PROPERTY(int columns READ columns WRITE setColumns NOTIFY renderLayoutChanged)
    Q_PROPERTY(qreal cellSize READ cellSize WRITE setCellSize NOTIFY renderLayoutChanged)
    Q_PROPERTY(qreal monthHeaderHeight READ monthHeaderHeight WRITE setMonthHeaderHeight NOTIFY renderLayoutChanged)
    Q_PROPERTY(qreal dayHeaderHeight READ dayHeaderHeight WRITE setDayHeaderHeight NOTIFY renderLayoutChanged)
    Q_PROPERTY(int renderRowCount READ renderRowCount NOTIFY renderLayoutChanged)
    Q_PROPERTY(qreal renderContentHeight READ renderContentHeight NOTIFY renderContentHeightChanged)
    Q_PROPERTY(int layoutVersion READ layoutVersion NOTIFY renderLayoutChanged)
    Q_PROPERTY(int dataVersion READ dataVersion NOTIFY renderDataChanged)
    Q_PROPERTY(QStringList heroAssetIds READ heroAssetIds NOTIFY heroAssetIdsChanged)

public:
    explicit TimelineModel(QObject *parent = nullptr);
    ~TimelineModel() override;

    Q_INVOKABLE void fetchBuckets();

    // Bucket management
    Q_INVOKABLE bool isBucketLoaded(int bucketIndex) const;
    Q_INVOKABLE void requestBucketLoad(int bucketIndex);
    Q_INVOKABLE int getBucketCount() const;
    Q_INVOKABLE QVariantList getBucketAssets(int bucketIndex) const;
    Q_INVOKABLE QStringList getLoadedAssetIds() const;
    Q_INVOKABLE QString bucketMonthYear(int bucketIndex) const;

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

    // Local/remote selection splitting
    Q_INVOKABLE QStringList getSelectedLocalPaths() const;
    Q_INVOKABLE QStringList getSelectedRemoteIds() const;
    Q_INVOKABLE bool hasSelectedLocal() const;
    Q_INVOKABLE bool hasSelectedRemote() const;

    void setBackupManager(BackupManager *backupManager);
    Q_INVOKABLE void removeLocalFiles(const QStringList &paths);

    Q_INVOKABLE void scrollToAsset(const QString &assetId);

    Q_INVOKABLE QVariantMap getAssetByAssetIndex(int assetIndex) const;
    Q_INVOKABLE QVariantMap getAssetLocation(int assetIndex) const;

    Q_INVOKABLE QVariantMap renderRowAt(int rowIndex) const;
    Q_INVOKABLE QVariantList renderRowAssets(int rowIndex) const;
    Q_INVOKABLE int firstRowAtY(qreal y) const;
    Q_INVOKABLE int lastRowAtY(qreal y) const;
    Q_INVOKABLE int rowIndexForAsset(int bucketIndex, int assetIndex) const;
    Q_INVOKABLE int rowIndexForGlobalAsset(int globalIndex) const;
    Q_INVOKABLE int rowIndexForAssetId(const QString &assetId) const;
    Q_INVOKABLE QVariantMap nearestMonthEntry(qreal y) const;
    Q_INVOKABLE int globalIndexForAssetId(const QString &assetId) const;

    Q_INVOKABLE void setViewport(qreal top, qreal height);

    // Properties
    int totalCount() const;
    int selectedCount() const;
    bool loading() const;
    Q_INVOKABLE void setLoading(bool loading);
    int bucketCount() const;

    QString context() const;
    Q_INVOKABLE void setContext(const QString &context);
    QVariantMap queryParams() const;
    Q_INVOKABLE void setQueryParams(const QVariantMap &params);
    bool groupByCreatedAt() const { return m_groupByCreatedAt; }
    Q_INVOKABLE void setGroupByCreatedAt(bool value);

    int columns() const;
    void setColumns(int columns);
    qreal cellSize() const;
    void setCellSize(qreal size);
    qreal monthHeaderHeight() const;
    void setMonthHeaderHeight(qreal height);
    qreal dayHeaderHeight() const;
    void setDayHeaderHeight(qreal height);
    int renderRowCount() const;
    qreal renderContentHeight() const;
    int layoutVersion() const;
    int dataVersion() const;
    QStringList heroAssetIds() const;

    Q_INVOKABLE void clear();

signals:
    void totalCountChanged();
    void selectedCountChanged();
    void loadingChanged();
    void bucketCountChanged();
    void contextChanged();
    void queryParamsChanged();
    void groupByCreatedAtChanged();
    void bucketsLoaded();
    void scrollToAssetRequested(const QString &assetId, int bucketIndex, int assetIndexInBucket);
    void bucketAssetsLoaded(int bucketIndex);
    void renderLayoutAboutToChange();
    void renderLayoutChanged();
    void renderContentHeightChanged();
    void renderDataChanged();
    void heroAssetIdsChanged();
    void layoutShifted(qreal dy);

private:
    void onRefreshReady(quint64 gen, const QStringList &days, const QList<int> &counts, const QStringList &loadedDays, const QList<QList<TimelineAsset>> &assets, const QStringList &failedDays, bool ok);
    void onDaysReady(quint64 gen, const QStringList &days, const QList<QList<TimelineAsset>> &assets, const QStringList &failedDays);
    void onAssetDayResolved(quint64 gen, const QString &requestedId, const QString &resolvedId, const QString &day);
    void onCatalogChanged(int mask);
    void flushPendingDays();
    void bumpGeneration();

    QString catalogSourceSql(QVariantList &binds) const;
    QString bucketQuerySql(const QString &source) const;
    QString dayQuerySql(const QString &source) const;
    TimelineBucket makeBucket(const QString &day, int count) const;
    int catalogChangedMask() const;

    void rebuildAssetIndex();
    void rebuildBucketOffsets();
    QVariantMap assetToVariantMap(const TimelineAsset &asset) const;
    int findBucketByAssetIndex(int assetIndex) const;
    void resolvePendingScroll(int bucketIndex);
    void markBucketLoadFailed(int bucketIndex);
    void applyRefresh(const QStringList &days, const QList<int> &counts, const QStringList &loadedDays, const QList<QList<TimelineAsset>> &assets, const QStringList &failedDays);
    bool applyDayAssets(int bucketIndex, const QList<TimelineAsset> &assets, QSet<QString> *oldAssetIds);
    void commitDayResults(const QStringList &days, const QList<QList<TimelineAsset>> &assets);
    void updateHeroIds();

    BackupManager *m_backupManager;
    bool sortDescending() const;
    void recomputeTotals();

    QList<TimelineBucket> m_buckets;
    QSet<QString> m_selectedIds;
    QHash<QString, QPair<int, int>> m_assetIndex;
    QList<int> m_bucketOffsets;
    int m_totalCount;
    bool m_loading;
    QString m_userId;
    bool m_groupByCreatedAt = false;
    QString m_context;
    QVariantMap m_queryParams;

    CatalogQueryWorker *m_worker = nullptr;
    quint64 m_generation = 0;
    quint64 m_inflightBucketGen = 0;
    quint64 m_inflightDaysGen = 0;
    bool m_bucketQueryInFlight = false;
    bool m_daysInFlight = false;
    bool m_refetchPending = false;
    bool m_everFetched = false;
    QStringList m_pendingDays;

    qreal m_viewportTop = 0.0;
    qreal m_viewportHeight = 0.0;

    QStringList m_heroAssetIds;

    // Pending scroll state
    QString m_pendingScrollAssetId;
    int m_pendingScrollBucketIndex;
    QString m_pendingScrollDay;

    struct MonthEntry {
        qreal y;
        QString label;
    };
    QList<RenderRow> m_rows;
    QList<MonthEntry> m_monthEntries;
    qreal m_renderContentHeight;
    int m_columns;
    qreal m_cellSize;
    qreal m_monthHeaderHeight;
    qreal m_dayHeaderHeight;
    int m_layoutVersion;
    int m_dataVersion;

    void rebuildRows();
    void buildBucketRows(int bucketIndex, QList<RenderRow> &rows, qreal &y, int globalBase, QString &lastMonthKey) const;
    qreal assetRowsHeight(int count) const;
    void invalidateRowCaches(int bucketIndex);
    void bumpLayoutVersion();
    void bumpDataVersion();
};

#endif
