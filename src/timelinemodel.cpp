#include "timelinemodel.h"
#include "dateutils.h"
#include "backupmanager.h"
#include "assetdatabase.h"
#include <QDebug>
#include <QLocale>
#include <QFile>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QTimer>
#include <QMetaObject>
#include <QtMath>
#include <algorithm>

TimelineModel::TimelineModel(QObject *parent)
    : QObject(parent)
    , m_backupManager(nullptr)
    , m_totalCount(0)
    , m_loading(false)
    , m_pendingScrollBucketIndex(-1)
    , m_renderContentHeight(0.0)
    , m_columns(4)
    , m_cellSize(0.0)
    , m_monthHeaderHeight(0.0)
    , m_dayHeaderHeight(0.0)
    , m_layoutVersion(0)
    , m_dataVersion(0)
{
    static bool registered = false;
    if (!registered) {
        registered = true;
        qRegisterMetaType<quint64>("quint64");
        qRegisterMetaType<QList<int>>("QList<int>");
        qRegisterMetaType<QList<TimelineAsset>>("QList<TimelineAsset>");
        qRegisterMetaType<QList<QList<TimelineAsset>>>("QList<QList<TimelineAsset>>");
    }

    AssetDatabase *db = AssetDatabase::instance();
    if (db) {
        m_worker = new CatalogQueryWorker;
        m_worker->moveToThread(db->readerThread());
        connect(m_worker, &CatalogQueryWorker::refreshReady, this, &TimelineModel::onRefreshReady);
        connect(m_worker, &CatalogQueryWorker::daysReady, this, &TimelineModel::onDaysReady);
        connect(m_worker, &CatalogQueryWorker::assetDayResolved, this, &TimelineModel::onAssetDayResolved);
        connect(db, &AssetDatabase::changed, this, &TimelineModel::onCatalogChanged);
    }
}

TimelineModel::~TimelineModel()
{
    if (m_worker) {
        m_worker->deleteLater();
    }
}

TimelineBucket TimelineModel::makeBucket(const QString &day, int count) const
{
    TimelineBucket bucket;
    bucket.timeBucket = day;
    bucket.dateTime = QDateTime(QDate::fromString(day, QStringLiteral("yyyy-MM-dd")));
    bucket.monthYear = DateUtils::monthYearLabel(bucket.dateTime.date());
    bucket.date = QLocale().toString(bucket.dateTime, QStringLiteral("dd.MM.yyyy"));
    bucket.count = count;
    bucket.loaded = false;
    bucket.loading = false;
    return bucket;
}

void TimelineModel::bumpGeneration()
{
    ++m_generation;
    m_bucketQueryInFlight = false;
    m_daysInFlight = false;
    m_refetchPending = false;
    m_pendingDays.clear();
    for (TimelineBucket &bucket : m_buckets) {
        bucket.loading = false;
    }
}

QString TimelineModel::bucketQuerySql(const QString &source) const
{
    return QStringLiteral("SELECT strftime('%Y-%m-%d', created_at, 'localtime') AS d, COUNT(*) FROM (%1) GROUP BY d ORDER BY d %2").arg(source, sortDescending() ? QStringLiteral("DESC") : QStringLiteral("ASC"));
}

QString TimelineModel::dayQuerySql(const QString &source) const
{
    return QStringLiteral(
        "SELECT remote_id, type, created_at, is_favorite, thumb_hash, duration_ms,"
        " stack_id, stack_asset_count, live_photo_video_id, owner_id, local_path, name"
        " FROM (%1)"
        " WHERE created_at >= ? AND created_at < ?"
        " ORDER BY created_at %2")
        .arg(source, sortDescending() ? QStringLiteral("DESC") : QStringLiteral("ASC"));
}

QString TimelineModel::catalogSourceSql(QVariantList &binds) const
{
    static const QString me = QStringLiteral("(SELECT value FROM sync_meta WHERE key = 'current_user_id')");

    const QString dateExpr = m_groupByCreatedAt ? QStringLiteral("COALESCE(%1uploaded_at, %1created_at)") : QStringLiteral("%1created_at");

    const QString remoteCols = QStringLiteral(
        "ra.id AS remote_id, ra.name, ra.type,"
        " %1 AS created_at, ra.duration_ms, ra.is_favorite, ra.thumb_hash, ra.owner_id,"
        " ra.live_photo_video_id, ra.stack_id,"
        " (SELECT COUNT(*) FROM remote_asset s2 WHERE s2.stack_id = ra.stack_id) AS stack_asset_count,"
        " (SELECT la.path FROM local_asset la WHERE la.checksum = ra.checksum LIMIT 1) AS local_path")
        .arg(dateExpr.arg(QStringLiteral("ra.")));

    const QString stackCollapsePredicate = QStringLiteral(
        "(ra.stack_id IS NULL"
        " OR NOT EXISTS (SELECT 1 FROM stack se WHERE se.id = ra.stack_id)"
        " OR ra.id = (SELECT primary_asset_id FROM stack se WHERE se.id = ra.stack_id))");

    QString src;
    if (m_context == QLatin1String("timeline")) {
        src = QStringLiteral(
            "SELECT remote_id, name, type, %1 AS created_at, duration_ms,"
            " is_favorite, thumb_hash, owner_id, live_photo_video_id, stack_id,"
            " stack_asset_count, local_path FROM merged_asset")
            .arg(m_groupByCreatedAt ? QStringLiteral("COALESCE(uploaded_at, created_at)") : QStringLiteral("created_at"));
    } else if (m_context == QLatin1String("favorites")) {
        const QString predicate = QStringLiteral(" AND ") + stackCollapsePredicate;
        src = QStringLiteral("SELECT %1 FROM remote_asset ra WHERE ra.is_favorite = 1 AND ra.deleted_at IS NULL AND ra.owner_id = %2%3").arg(remoteCols, me, predicate);
    } else if (m_context == QLatin1String("archive")) {
        src = QStringLiteral("SELECT %1 FROM remote_asset ra WHERE ra.visibility = 'archive' AND ra.deleted_at IS NULL AND ra.owner_id = %2").arg(remoteCols, me);
    } else if (m_context == QLatin1String("locked")) {
        src = QStringLiteral("SELECT %1 FROM remote_asset ra WHERE ra.visibility = 'locked' AND ra.deleted_at IS NULL AND ra.owner_id = %2").arg(remoteCols, me);
    } else if (m_context == QLatin1String("trash")) {
        src = QStringLiteral("SELECT %1 FROM remote_asset ra WHERE ra.deleted_at IS NOT NULL AND ra.owner_id = %2").arg(remoteCols, me);
    } else if (m_context.startsWith(QLatin1String("person-"))) {
        binds.append(m_context.mid(7));
        const QString faceAssets = QStringLiteral("SELECT asset_id FROM asset_face WHERE person_id = ? AND is_visible = 1");
        QString predicate = QStringLiteral("ra.id IN (%1) AND %2").arg(faceAssets, stackCollapsePredicate);
        src = QStringLiteral("SELECT %1 FROM remote_asset ra WHERE ra.deleted_at IS NULL AND (%3)"
            " AND ((ra.owner_id = %2 AND ra.visibility NOT IN ('locked', 'hidden'))"
            " OR (ra.visibility = 'timeline' AND (ra.owner_id IN (SELECT shared_by_id FROM partner WHERE shared_with_id = %2)"
            " OR ra.id IN (SELECT asset_id FROM album_to_asset))))").arg(remoteCols, me, predicate);
    } else if (m_context.startsWith(QLatin1String("partner-"))) {
        binds.append(m_context.mid(8));
        src = QStringLiteral("SELECT %1 FROM remote_asset ra WHERE ra.deleted_at IS NULL AND ra.owner_id = ?").arg(remoteCols);
    } else if (m_context.startsWith(QLatin1String("album-")) || m_context.startsWith(QLatin1String("shared-")) || m_context.startsWith(QLatin1String("edit-album-"))) {
        const QString albumId = m_queryParams.value(QStringLiteral("albumId")).toString();
        if (albumId.isEmpty()) {
            return QString();
        }
        binds.append(albumId);
        src = QStringLiteral("SELECT %1 FROM album_to_asset ata JOIN remote_asset ra ON ata.asset_id = ra.id WHERE ata.album_id = ? AND ra.deleted_at IS NULL").arg(remoteCols);
    }
    if (src.isEmpty()) {
        return QString();
    }
    if (m_queryParams.value(QStringLiteral("isFavorite")).toBool() && m_context != QLatin1String("favorites")) {
        return QStringLiteral("SELECT * FROM (%1) WHERE is_favorite = 1").arg(src);
    }
    return src;
}

void TimelineModel::onRefreshReady(quint64 gen, const QStringList &days, const QList<int> &counts, const QStringList &loadedDays, const QList<QList<TimelineAsset>> &assets, const QStringList &failedDays, bool ok)
{
    if (gen == m_inflightBucketGen) {
        m_bucketQueryInFlight = false;
    }
    if (gen != m_generation) {
        return;
    }
    if (!ok) {
        qWarning() << "TimelineModel: Catalog bucket query failed";
        setLoading(false);
        emit bucketsLoaded();
        if (m_refetchPending) {
            m_refetchPending = false;
            fetchBuckets();
        }
        return;
    }

    applyRefresh(days, counts, loadedDays, assets, failedDays);
}

static bool applyAssetsToBucket(TimelineBucket &bucket, const QList<TimelineAsset> &assets, QSet<QString> *oldAssetIds)
{
    if (bucket.loaded && bucket.assets == assets) {
        bucket.loading = false;
        bucket.stale = false;
        bucket.count = assets.size();
        return false;
    }
    if (oldAssetIds) {
        for (const TimelineAsset &asset : bucket.assets) {
            oldAssetIds->insert(asset.id);
        }
    }
    bucket.assets = assets;
    bucket.loaded = true;
    bucket.loading = false;
    bucket.stale = false;
    bucket.count = assets.size();
    return true;
}

bool TimelineModel::applyDayAssets(int bucketIndex, const QList<TimelineAsset> &assets, QSet<QString> *oldAssetIds)
{
    const bool changed = applyAssetsToBucket(m_buckets[bucketIndex], assets, oldAssetIds);
    if (changed) {
        invalidateRowCaches(bucketIndex);
    }
    return changed;
}

void TimelineModel::applyRefresh(const QStringList &days, const QList<int> &counts, const QStringList &loadedDays, const QList<QList<TimelineAsset>> &assets, const QStringList &failedDays)
{
    QHash<QString, int> existingByDay;
    for (int i = 0; i < m_buckets.size(); ++i) {
        existingByDay.insert(m_buckets[i].timeBucket, i);
    }
    QHash<QString, int> loadedPos;
    for (int i = 0; i < loadedDays.size(); ++i) {
        loadedPos.insert(loadedDays.at(i), i);
    }

    if (m_pendingScrollBucketIndex >= 0 && m_pendingScrollBucketIndex < m_buckets.size()) {
        m_pendingScrollDay = m_buckets.at(m_pendingScrollBucketIndex).timeBucket;
    }

    bool contentChanged = false;
    bool listChanged = false;
    QSet<QString> oldAssetIds;
    QList<int> freshLoaded;

    QList<TimelineBucket> merged;
    merged.reserve(days.size());
    for (int i = 0; i < days.size(); ++i) {
        const QString &day = days.at(i);
        const int count = counts.value(i);
        const int loadedIdx = loadedPos.value(day, -1);
        const auto it = existingByDay.constFind(day);
        if (it == existingByDay.constEnd()) {
            listChanged = true;
            TimelineBucket bucket = makeBucket(day, count);
            if (loadedIdx >= 0) {
                bucket.assets = assets.at(loadedIdx);
                bucket.count = bucket.assets.size();
                bucket.loaded = true;
                contentChanged = true;
                freshLoaded.append(merged.size());
            }
            merged.append(bucket);
            continue;
        }

        TimelineBucket bucket = m_buckets.at(it.value());
        const int oldIdx = it.value();
        if (oldIdx != merged.size()) {
            listChanged = true;
        }
        if (loadedIdx >= 0) {
            QSet<QString> dropped;
            if (applyAssetsToBucket(bucket, assets.at(loadedIdx), &dropped)) {
                contentChanged = true;
                oldAssetIds.unite(dropped);
            }
            freshLoaded.append(merged.size());
        } else if (bucket.loaded) {
            if (bucket.assets.size() == count) {
                bucket.stale = true;
            } else {
                for (const TimelineAsset &asset : bucket.assets) {
                    oldAssetIds.insert(asset.id);
                }
                bucket.assets.clear();
                bucket.loaded = false;
                bucket.stale = false;
                bucket.count = count;
                contentChanged = true;
            }
        } else if (bucket.count != count) {
            bucket.count = count;
        }
        merged.append(bucket);
    }
    if (merged.size() != m_buckets.size()) {
        listChanged = true;
    }
    const QSet<QString> resultDays = QSet<QString>::fromList(days);
    for (const TimelineBucket &bucket : m_buckets) {
        if (!resultDays.contains(bucket.timeBucket)) {
            for (const TimelineAsset &asset : bucket.assets) {
                oldAssetIds.insert(asset.id);
            }
            if (bucket.loaded) {
                contentChanged = true;
            }
        }
    }
    m_buckets = merged;

    rebuildAssetIndex();
    bool selectionChanged = false;
    for (const QString &id : oldAssetIds) {
        if (!m_assetIndex.contains(id) && m_selectedIds.remove(id)) {
            selectionChanged = true;
        }
    }
    recomputeTotals();
    rebuildRows();
    if (listChanged) {
        emit bucketCountChanged();
    }
    if (selectionChanged) {
        emit selectedCountChanged();
    }
    if (contentChanged || listChanged) {
        bumpDataVersion();
    }

    if (!m_pendingScrollDay.isEmpty()) {
        m_pendingScrollBucketIndex = -1;
        for (int i = 0; i < m_buckets.size(); ++i) {
            if (m_buckets.at(i).timeBucket == m_pendingScrollDay) {
                m_pendingScrollBucketIndex = i;
                break;
            }
        }
    }
    for (int idx : freshLoaded) {
        emit bucketAssetsLoaded(idx);
        resolvePendingScroll(idx);
    }
    for (const QString &day : failedDays) {
        const auto it = std::find_if(m_buckets.begin(), m_buckets.end(), [&day](const TimelineBucket &b) { return b.timeBucket == day; });
        if (it != m_buckets.end()) {
            qWarning() << "TimelineModel: Catalog asset query failed for day" << day;
            markBucketLoadFailed(int(it - m_buckets.begin()));
        }
    }

    setLoading(false);
    emit bucketsLoaded();
    updateHeroIds();
    flushPendingDays();

    if (!m_buckets.isEmpty() && (!m_buckets.at(0).loaded || m_buckets.at(0).stale)) {
        requestBucketLoad(0);
    }
    if (m_refetchPending) {
        m_refetchPending = false;
        fetchBuckets();
    }
}

void TimelineModel::updateHeroIds()
{
    QStringList ids;
    for (const QString &id : m_heroAssetIds) {
        if (m_assetIndex.contains(id)) {
            ids.append(id);
        }
    }
    for (const TimelineBucket &bucket : m_buckets) {
        if (!bucket.loaded || ids.size() >= 5) {
            continue;
        }
        for (const TimelineAsset &asset : bucket.assets) {
            if (ids.size() >= 5) {
                break;
            }
            if (asset.type == QLatin1String("VIDEO") || ids.contains(asset.id)) {
                continue;
            }
            ids.append(asset.id);
        }
    }
    if (ids != m_heroAssetIds) {
        m_heroAssetIds = ids;
        emit heroAssetIdsChanged();
    }
}

void TimelineModel::onDaysReady(quint64 gen, const QStringList &days, const QList<QList<TimelineAsset>> &assets, const QStringList &failedDays)
{
    if (gen == m_inflightDaysGen) {
        m_daysInFlight = false;
    }
    if (gen != m_generation) {
        return;
    }

    for (const QString &day : failedDays) {
        for (int i = 0; i < m_buckets.size(); ++i) {
            if (m_buckets.at(i).timeBucket == day) {
                qWarning() << "TimelineModel: Catalog asset query failed for day" << day;
                markBucketLoadFailed(i);
                break;
            }
        }
    }
    commitDayResults(days, assets);
}

void TimelineModel::commitDayResults(const QStringList &days, const QList<QList<TimelineAsset>> &assets)
{
    QHash<QString, int> dayToBucket;
    for (int i = 0; i < m_buckets.size(); ++i) {
        dayToBucket.insert(m_buckets[i].timeBucket, i);
    }

    QList<int> applied;
    bool changed = false;
    QSet<QString> oldAssetIds;
    const int n = qMin(days.size(), assets.size());
    for (int i = 0; i < n; ++i) {
        const auto it = dayToBucket.constFind(days.at(i));
        if (it == dayToBucket.constEnd()) {
            continue;
        }
        const int idx = it.value();
        if (applyDayAssets(idx, assets.at(i), &oldAssetIds)) {
            changed = true;
        }
        applied.append(idx);
    }
    if (applied.isEmpty()) {
        flushPendingDays();
        return;
    }

    rebuildAssetIndex();
    bool selectionChanged = false;
    for (const QString &id : oldAssetIds) {
        if (!m_assetIndex.contains(id) && m_selectedIds.remove(id)) {
            selectionChanged = true;
        }
    }
    recomputeTotals();
    rebuildRows();
    if (selectionChanged) {
        emit selectedCountChanged();
    }
    if (changed) {
        bumpDataVersion();
    }

    for (int idx : applied) {
        emit bucketAssetsLoaded(idx);
        resolvePendingScroll(idx);
    }
    updateHeroIds();
    flushPendingDays();
}

void TimelineModel::onCatalogChanged(int mask)
{
    if (!m_everFetched || m_context.isEmpty()) {
        return;
    }
    if (mask & catalogChangedMask()) {
        fetchBuckets();
    }
}

int TimelineModel::catalogChangedMask() const
{
    if (m_context == QLatin1String("timeline")) {
        return AssetDatabase::Assets | AssetDatabase::Stacks | AssetDatabase::Partners | AssetDatabase::LocalAssets | AssetDatabase::Users;
    }
    if (m_context == QLatin1String("favorites") || m_context == QLatin1String("archive") || m_context == QLatin1String("locked") || m_context == QLatin1String("trash")) {
        return AssetDatabase::Assets | AssetDatabase::Stacks;
    }
    if (m_context.startsWith(QLatin1String("person-"))) {
        return AssetDatabase::Assets | AssetDatabase::People | AssetDatabase::Stacks;
    }
    if (m_context.startsWith(QLatin1String("partner-"))) {
        return AssetDatabase::Assets | AssetDatabase::Partners;
    }
    if (m_context.startsWith(QLatin1String("album-")) || m_context.startsWith(QLatin1String("shared-")) || m_context.startsWith(QLatin1String("edit-album-"))) {
        return AssetDatabase::Assets | AssetDatabase::Albums | AssetDatabase::AlbumAssets;
    }
    return 0;
}

bool TimelineModel::isBucketLoaded(int bucketIndex) const
{
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return false;
    return m_buckets.at(bucketIndex).loaded;
}

void TimelineModel::requestBucketLoad(int bucketIndex)
{
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size()) {
        return;
    }
    TimelineBucket &bucket = m_buckets[bucketIndex];
    if (bucket.loading || (bucket.loaded && !bucket.stale)) {
        return;
    }
    bucket.loading = true;
    if (!m_pendingDays.contains(bucket.timeBucket)) {
        m_pendingDays.append(bucket.timeBucket);
    }
    QTimer::singleShot(0, this, [this]() {
        flushPendingDays();
    });
}

void TimelineModel::flushPendingDays()
{
    if (!m_worker || m_daysInFlight || m_pendingDays.isEmpty()) {
        return;
    }
    QVariantList binds;
    const QString source = catalogSourceSql(binds);
    if (source.isEmpty()) {
        return;
    }
    QStringList days;
    while (days.size() < 16 && !m_pendingDays.isEmpty()) {
        days.append(m_pendingDays.takeFirst());
    }
    m_daysInFlight = true;
    m_inflightDaysGen = m_generation;
    QMetaObject::invokeMethod(m_worker, "queryDays", Qt::QueuedConnection, Q_ARG(quint64, m_inflightDaysGen), Q_ARG(QString, dayQuerySql(source)), Q_ARG(QVariantList, binds), Q_ARG(QStringList, days));
}

int TimelineModel::getBucketCount() const
{
    return m_buckets.size();
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
        QVariantMap assetMap = assetToVariantMap(asset);
        assetMap[QStringLiteral("assetIndex")] = assetIndex++;
        result.append(assetMap);
    }
    return result;
}

QStringList TimelineModel::getLoadedAssetIds() const
{
    QStringList ids;
    for (const TimelineBucket &bucket : m_buckets) {
        if (!bucket.loaded) continue;
        for (const TimelineAsset &asset : bucket.assets)
            ids.append(asset.id);
    }
    return ids;
}

QString TimelineModel::bucketMonthYear(int bucketIndex) const
{
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return QString();
    return m_buckets.at(bucketIndex).monthYear;
}

QVariantMap TimelineModel::assetToVariantMap(const TimelineAsset &asset) const
{
    QVariantMap assetMap;
    assetMap[QStringLiteral("id")] = asset.id;
    assetMap[QStringLiteral("isFavorite")] = asset.isFavorite;
    assetMap[QStringLiteral("type")] = asset.type;
    assetMap[QStringLiteral("fileName")] = asset.name;
    assetMap[QStringLiteral("thumbhash")] = asset.thumbhash;
    assetMap[QStringLiteral("duration")] = asset.duration;
    assetMap[QStringLiteral("stackId")] = asset.stackId;
    assetMap[QStringLiteral("stackAssetCount")] = asset.stackAssetCount;
    assetMap[QStringLiteral("livePhotoVideoId")] = asset.livePhotoVideoId;
    assetMap[QStringLiteral("ownerId")] = asset.ownerId;
    assetMap[QStringLiteral("isLocal")] = asset.isLocal;
    assetMap[QStringLiteral("localPath")] = asset.localPath;
    assetMap[QStringLiteral("createdAt")] = asset.createdAt.toString(Qt::ISODate);
    return assetMap;
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
    auto it = std::upper_bound(m_bucketOffsets.constBegin(), m_bucketOffsets.constEnd(), assetIndex);
    if (it == m_bucketOffsets.constBegin())
        return -1;
    int b = int(it - m_bucketOffsets.constBegin()) - 1;
    if (assetIndex >= m_bucketOffsets.at(b) + m_buckets.at(b).count)
        return -1;
    return b;
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

void TimelineModel::setSelectionForAssets(const QStringList &assetIds, bool selected)
{
    bool changed = false;
    for (const QString &assetId : assetIds) {
        if (selected) {
            if (!m_selectedIds.contains(assetId)) {
                m_selectedIds.insert(assetId);
                changed = true;
            }
        } else if (m_selectedIds.remove(assetId)) {
            changed = true;
        }
    }
    if (changed) {
        emit selectedCountChanged();
    }
}

bool TimelineModel::areAllAssetsSelected(const QStringList &assetIds) const
{
    if (assetIds.isEmpty()) {
        return false;
    }
    for (const QString &assetId : assetIds) {
        if (!m_selectedIds.contains(assetId)) {
            return false;
        }
    }
    return true;
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

bool TimelineModel::hasSelectedOtherOwner() const
{
    if (m_userId.isEmpty() || m_selectedIds.isEmpty())
        return false;

    for (const QString &assetId : m_selectedIds) {
        auto it = m_assetIndex.find(assetId);
        if (it != m_assetIndex.end()) {
            int bucketIdx = it.value().first;
            int assetIdx = it.value().second;
            if (bucketIdx < m_buckets.size() && assetIdx < m_buckets.at(bucketIdx).assets.size()) {
                const QString &ownerId = m_buckets.at(bucketIdx).assets.at(assetIdx).ownerId;
                if (!ownerId.isEmpty() && ownerId != m_userId)
                    return true;
            }
        }
    }
    return false;
}

void TimelineModel::setUserId(const QString &userId)
{
    m_userId = userId;
}

void TimelineModel::setBackupManager(BackupManager *backupManager)
{
    m_backupManager = backupManager;
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
    return assetToVariantMap(asset);
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

void TimelineModel::scrollToAsset(const QString &assetId)
{
    const auto it = m_assetIndex.constFind(assetId);
    if (it != m_assetIndex.constEnd() && m_buckets.at(it.value().first).loaded) {
        emit scrollToAssetRequested(assetId, it.value().first, it.value().second);
        return;
    }

    QVariantList binds;
    const QString source = catalogSourceSql(binds);
    if (source.isEmpty() || !m_worker) {
        return;
    }
    const QString sql = QStringLiteral(
        "SELECT strftime('%Y-%m-%d', created_at, 'localtime') AS d, remote_id FROM (%1)"
        " WHERE remote_id = ? OR remote_id = (SELECT primary_asset_id FROM stack"
        " WHERE id = (SELECT stack_id FROM remote_asset WHERE id = ?))"
        " ORDER BY (remote_id = ?) DESC LIMIT 1").arg(source);
    binds.append(assetId);
    binds.append(assetId);
    binds.append(assetId);
    QMetaObject::invokeMethod(m_worker, "resolveAssetDay", Qt::QueuedConnection, Q_ARG(quint64, m_generation), Q_ARG(QString, sql), Q_ARG(QVariantList, binds), Q_ARG(QString, assetId));
}

void TimelineModel::onAssetDayResolved(quint64 gen, const QString &requestedId, const QString &resolvedId, const QString &day)
{
    if (gen != m_generation) {
        return;
    }
    int bucketIndex = -1;
    for (int i = 0; i < m_buckets.size(); ++i) {
        if (m_buckets.at(i).timeBucket == day) {
            bucketIndex = i;
            break;
        }
    }
    if (bucketIndex < 0) {
        qWarning() << "TimelineModel: No bucket for asset" << requestedId << "day" << day;
        return;
    }
    const QString targetId = resolvedId.isEmpty() ? requestedId : resolvedId;
    const TimelineBucket &bucket = m_buckets.at(bucketIndex);
    if (bucket.loaded) {
        for (int i = 0; i < bucket.assets.size(); ++i) {
            if (bucket.assets.at(i).id == targetId) {
                emit scrollToAssetRequested(targetId, bucketIndex, i);
                return;
            }
        }
        emit scrollToAssetRequested(targetId, bucketIndex, -1);
        return;
    }
    m_pendingScrollAssetId = targetId;
    m_pendingScrollBucketIndex = bucketIndex;
    m_pendingScrollDay = day;
    requestBucketLoad(bucketIndex);
    emit scrollToAssetRequested(targetId, bucketIndex, -1);
}

void TimelineModel::resolvePendingScroll(int bucketIndex)
{
    if (m_pendingScrollAssetId.isEmpty() || m_pendingScrollBucketIndex != bucketIndex) {
        return;
    }

    QString assetId = m_pendingScrollAssetId;
    m_pendingScrollAssetId.clear();
    m_pendingScrollBucketIndex = -1;
    m_pendingScrollDay.clear();

    // Find asset position in the loaded bucket
    const auto &assets = m_buckets[bucketIndex].assets;
    for (int i = 0; i < assets.size(); i++) {
        if (assets[i].id == assetId) {
            emit scrollToAssetRequested(assetId, bucketIndex, i);
            return;
        }
    }
    // Asset not in bucket, scroll to bucket top
    emit scrollToAssetRequested(assetId, bucketIndex, -1);
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

int TimelineModel::bucketCount() const
{
    return m_buckets.size();
}

QString TimelineModel::context() const
{
    return m_context;
}

void TimelineModel::setContext(const QString &context)
{
    if (m_context != context) {
        m_context = context;
        bumpGeneration();
        emit contextChanged();
    }
}

QVariantMap TimelineModel::queryParams() const
{
    return m_queryParams;
}

void TimelineModel::setQueryParams(const QVariantMap &params)
{
    if (m_queryParams != params) {
        m_queryParams = params;
        bumpGeneration();
        emit queryParamsChanged();
    }
}

void TimelineModel::setGroupByCreatedAt(bool value)
{
    if (m_groupByCreatedAt != value) {
        m_groupByCreatedAt = value;
        bumpGeneration();
        emit groupByCreatedAtChanged();
    }
}

void TimelineModel::fetchBuckets()
{
    if (m_context.isEmpty()) {
        qWarning() << "TimelineModel: Called fetchBuckets without context";
        return;
    }
    m_everFetched = true;
    setLoading(true);
    if (m_bucketQueryInFlight) {
        m_refetchPending = true;
        return;
    }
    QVariantList binds;
    const QString source = catalogSourceSql(binds);
    if (source.isEmpty() || !m_worker) {
        setLoading(false);
        emit bucketsLoaded();
        return;
    }
    QStringList reloadDays;
    const qreal winTop = m_viewportTop - m_viewportHeight;
    const qreal winBottom = m_viewportTop + 2.0 * m_viewportHeight;
    for (int b = 0; b < m_buckets.size(); ++b) {
        const TimelineBucket &bucket = m_buckets.at(b);
        if (!bucket.loaded) {
            continue;
        }
        bool intersect = (b == 0);
        if (!intersect && bucket.rowStart >= 0 && bucket.rowEnd < m_rows.size()) {
            const qreal top = m_rows.at(bucket.rowStart).y;
            const qreal bottom = m_rows.at(bucket.rowEnd).y + m_rows.at(bucket.rowEnd).height;
            intersect = (bottom >= winTop && top <= winBottom);
        }
        if (intersect) {
            reloadDays.append(bucket.timeBucket);
        }
    }
    int preloadBudget = 0;
    if (m_buckets.isEmpty()) {
        preloadBudget = (m_cellSize > 0) ? qMax(60, 2 * m_columns * qCeil(m_viewportHeight / m_cellSize)) : 60;
    }
    m_bucketQueryInFlight = true;
    m_inflightBucketGen = m_generation;
    QMetaObject::invokeMethod(m_worker, "refresh", Qt::QueuedConnection, Q_ARG(quint64, m_inflightBucketGen), Q_ARG(QString, bucketQuerySql(source)), Q_ARG(QString, dayQuerySql(source)), Q_ARG(QVariantList, binds), Q_ARG(QStringList, reloadDays), Q_ARG(int, preloadBudget));
}

void TimelineModel::markBucketLoadFailed(int bucketIndex)
{
    TimelineBucket &bucket = m_buckets[bucketIndex];
    bucket.loading = false;
    if (bucket.assets.isEmpty()) {
        bucket.loaded = false;
    }

    if (m_pendingScrollBucketIndex == bucketIndex) {
        QString assetId = m_pendingScrollAssetId;
        m_pendingScrollAssetId.clear();
        m_pendingScrollBucketIndex = -1;
        m_pendingScrollDay.clear();
        emit scrollToAssetRequested(assetId, bucketIndex, -1);
    }
}

void TimelineModel::clear()
{
    bumpGeneration();
    m_buckets.clear();
    m_selectedIds.clear();
    m_assetIndex.clear();
    m_bucketOffsets.clear();
    m_pendingScrollAssetId.clear();
    m_pendingScrollBucketIndex = -1;
    m_pendingScrollDay.clear();
    m_totalCount = 0;
    rebuildRows();
    emit bucketCountChanged();
    emit totalCountChanged();
    emit selectedCountChanged();
    updateHeroIds();
}

bool TimelineModel::sortDescending() const
{
    return m_queryParams.value(QStringLiteral("order")).toString() != QStringLiteral("asc");
}

void TimelineModel::removeLocalFiles(const QStringList &paths)
{
    for (const QString &path : paths) {
        QFile::remove(path);
        if (m_backupManager) {
            m_backupManager->handleLocalFileDeletion(path);
        }
    }

    AssetDatabase *db = AssetDatabase::instance();
    if (db) {
        QSqlQuery q(db->db());
        q.prepare(QStringLiteral("DELETE FROM local_asset WHERE path = ?"));
        for (const QString &path : paths) {
            q.addBindValue(path);
            q.exec();
            q.finish();
        }
        db->notifyChanged(AssetDatabase::LocalAssets);
    }
}

void TimelineModel::recomputeTotals()
{
    rebuildBucketOffsets();
    int total = 0;
    for (const TimelineBucket &bucket : m_buckets) {
        total += bucket.count;
    }
    if (total != m_totalCount) {
        m_totalCount = total;
        emit totalCountChanged();
    }
}

QStringList TimelineModel::getSelectedLocalPaths() const
{
    QStringList paths;
    for (const QString &id : m_selectedIds) {
        auto it = m_assetIndex.find(id);
        if (it == m_assetIndex.end())
            continue;
        const int b = it.value().first;
        const int a = it.value().second;
        if (b >= 0 && b < m_buckets.size() && a >= 0 && a < m_buckets.at(b).assets.size()) {
            const TimelineAsset &asset = m_buckets.at(b).assets.at(a);
            if (asset.isLocal) {
                paths.append(asset.localPath);
            }
        }
    }
    return paths;
}

QStringList TimelineModel::getSelectedRemoteIds() const
{
    QStringList ids;
    for (const QString &id : m_selectedIds) {
        auto it = m_assetIndex.find(id);
        if (it == m_assetIndex.end()) {
            ids.append(id);
            continue;
        }
        const int b = it.value().first;
        const int a = it.value().second;
        if (b >= 0 && b < m_buckets.size() && a >= 0 && a < m_buckets.at(b).assets.size()) {
            if (!m_buckets.at(b).assets.at(a).isLocal) {
                ids.append(id);
            }
        }
    }
    return ids;
}

bool TimelineModel::hasSelectedLocal() const
{
    for (const QString &id : m_selectedIds) {
        auto it = m_assetIndex.find(id);
        if (it == m_assetIndex.end())
            continue;
        const int b = it.value().first;
        const int a = it.value().second;
        if (b >= 0 && b < m_buckets.size() && a >= 0 && a < m_buckets.at(b).assets.size() && m_buckets.at(b).assets.at(a).isLocal) {
            return true;
        }
    }
    return false;
}

bool TimelineModel::hasSelectedRemote() const
{
    for (const QString &id : m_selectedIds) {
        auto it = m_assetIndex.find(id);
        if (it == m_assetIndex.end()) {
            return true;
        }
        const int b = it.value().first;
        const int a = it.value().second;
        if (b < 0 || b >= m_buckets.size() || a < 0 || a >= m_buckets.at(b).assets.size() || !m_buckets.at(b).assets.at(a).isLocal) {
            return true;
        }
    }
    return false;
}

int TimelineModel::columns() const
{
    return m_columns;
}

qreal TimelineModel::cellSize() const
{
    return m_cellSize;
}

qreal TimelineModel::monthHeaderHeight() const
{
    return m_monthHeaderHeight;
}

qreal TimelineModel::dayHeaderHeight() const
{
    return m_dayHeaderHeight;
}

int TimelineModel::renderRowCount() const
{
    return m_rows.size();
}

qreal TimelineModel::renderContentHeight() const
{
    return m_renderContentHeight;
}

int TimelineModel::layoutVersion() const
{
    return m_layoutVersion;
}

int TimelineModel::dataVersion() const
{
    return m_dataVersion;
}

QStringList TimelineModel::heroAssetIds() const
{
    return m_heroAssetIds;
}

void TimelineModel::setViewport(qreal top, qreal height)
{
    m_viewportTop = top;
    m_viewportHeight = height;
}

int TimelineModel::globalIndexForAssetId(const QString &assetId) const
{
    const auto it = m_assetIndex.constFind(assetId);
    if (it == m_assetIndex.constEnd()) {
        return -1;
    }
    const int b = it.value().first;
    if (b < 0 || b >= m_bucketOffsets.size()) {
        return -1;
    }
    return m_bucketOffsets.at(b) + it.value().second;
}

void TimelineModel::setColumns(int columns)
{
    if (m_columns == columns)
        return;
    m_columns = columns;
    rebuildRows();
}

void TimelineModel::setCellSize(qreal size)
{
    if (qFuzzyCompare(m_cellSize, size))
        return;
    m_cellSize = size;
    rebuildRows();
}

void TimelineModel::setMonthHeaderHeight(qreal height)
{
    if (qFuzzyCompare(m_monthHeaderHeight, height))
        return;
    m_monthHeaderHeight = height;
    rebuildRows();
}

void TimelineModel::setDayHeaderHeight(qreal height)
{
    if (qFuzzyCompare(m_dayHeaderHeight, height))
        return;
    m_dayHeaderHeight = height;
    rebuildRows();
}

void TimelineModel::bumpLayoutVersion()
{
    ++m_layoutVersion;
    emit renderLayoutChanged();
}

void TimelineModel::bumpDataVersion()
{
    ++m_dataVersion;
    emit renderDataChanged();
}

qreal TimelineModel::assetRowsHeight(int count) const
{
    if (count <= 0)
        return 0.0;
    const int cols = qMax(1, m_columns);
    return ((count + cols - 1) / cols) * m_cellSize;
}

void TimelineModel::buildBucketRows(int bucketIndex, QList<RenderRow> &rows, qreal &y, int globalBase, QString &lastMonthKey) const
{
    const TimelineBucket &bucket = m_buckets.at(bucketIndex);
    const QString monthKey = bucket.timeBucket.left(7);

    if (monthKey != lastMonthKey) {
        RenderRow header;
        header.type = RenderRow::MonthHeader;
        header.bucketIndex = bucketIndex;
        header.firstGlobal = globalBase;
        header.label = bucket.monthYear;
        header.day = bucket.timeBucket;
        header.y = y;
        header.height = m_monthHeaderHeight;
        y += header.height;
        rows.append(header);
        lastMonthKey = monthKey;
    }

    if (!bucket.loaded || bucket.assets.isEmpty()) {
        if (bucket.count > 0) {
            RenderRow dayHeader;
            dayHeader.type = RenderRow::DayHeader;
            dayHeader.bucketIndex = bucketIndex;
            dayHeader.firstAsset = 0;
            dayHeader.assetCount = bucket.count;
            dayHeader.firstGlobal = globalBase;
            dayHeader.label = bucket.date;
            dayHeader.day = bucket.timeBucket;
            dayHeader.y = y;
            dayHeader.height = m_dayHeaderHeight;
            y += dayHeader.height;
            rows.append(dayHeader);

            RenderRow ph;
            ph.type = RenderRow::Placeholder;
            ph.bucketIndex = bucketIndex;
            ph.firstGlobal = globalBase;
            ph.day = bucket.timeBucket;
            ph.y = y;
            ph.height = assetRowsHeight(bucket.count);
            y += ph.height;
            rows.append(ph);
        }
        return;
    }

    RenderRow dayHeader;
    dayHeader.type = RenderRow::DayHeader;
    dayHeader.bucketIndex = bucketIndex;
    dayHeader.firstAsset = 0;
    dayHeader.assetCount = bucket.assets.size();
    dayHeader.firstGlobal = globalBase;
    dayHeader.label = bucket.date;
    dayHeader.day = bucket.timeBucket;
    dayHeader.y = y;
    dayHeader.height = m_dayHeaderHeight;
    y += dayHeader.height;
    rows.append(dayHeader);

    const int cols = qMax(1, m_columns);
    const auto &assets = bucket.assets;
    for (int i = 0; i < assets.size(); i += cols) {
        RenderRow assetRow;
        assetRow.type = RenderRow::AssetRow;
        assetRow.bucketIndex = bucketIndex;
        assetRow.firstAsset = i;
        assetRow.assetCount = qMin(cols, assets.size() - i);
        assetRow.firstGlobal = globalBase + i;
        assetRow.day = bucket.timeBucket;
        assetRow.firstAssetId = assets.at(i).id;
        assetRow.y = y;
        assetRow.height = m_cellSize;
        y += assetRow.height;
        rows.append(assetRow);
    }
}

void TimelineModel::rebuildRows()
{
    emit renderLayoutAboutToChange();

    struct Anchor {
        bool valid = false;
        int type = RenderRow::Placeholder;
        QString day;
        QString firstAssetId;
        qreal oldY = 0.0;
        int firstGlobal = 0;
        qreal dayHeaderOldY = 0.0;
    } anchor;
    if (m_viewportTop > 0 && !m_rows.isEmpty()) {
        int r = firstRowAtY(m_viewportTop);
        if (r >= m_rows.size()) {
            r = m_rows.size() - 1;
        }
        if (r >= 0) {
            const RenderRow &row = m_rows.at(r);
            anchor.valid = true;
            anchor.type = row.type;
            anchor.day = row.day;
            anchor.firstAssetId = row.firstAssetId;
            anchor.oldY = row.y;
            anchor.firstGlobal = row.firstGlobal;
            int start = r;
            while (start > 0 && m_rows.at(start - 1).day == row.day) {
                --start;
            }
            for (int i = start; i < m_rows.size() && m_rows.at(i).day == row.day; ++i) {
                if (m_rows.at(i).type == RenderRow::DayHeader) {
                    anchor.dayHeaderOldY = m_rows.at(i).y;
                    break;
                }
            }
        }
    }

    m_rows.clear();
    m_monthEntries.clear();

    qreal y = 0.0;
    QString lastMonthKey;
    const int bucketCount = m_buckets.size();
    m_rows.reserve(bucketCount + m_totalCount / qMax(1, m_columns));

    for (int b = 0; b < bucketCount; ++b) {
        const int rowStart = m_rows.size();
        const int base = m_bucketOffsets.value(b, 0);
        buildBucketRows(b, m_rows, y, base, lastMonthKey);
        TimelineBucket &bucket = m_buckets[b];
        bucket.rowStart = rowStart;
        bucket.rowEnd = m_rows.size() - 1;
    }

    for (const RenderRow &row : m_rows) {
        if (row.type == RenderRow::MonthHeader) {
            m_monthEntries.append({row.y, row.label});
        }
    }

    const qreal newHeight = y;
    if (!qFuzzyCompare(m_renderContentHeight, newHeight)) {
        m_renderContentHeight = newHeight;
        emit renderContentHeightChanged();
    }

    qreal dy = 0.0;
    if (anchor.valid) {
        if (anchor.type == RenderRow::AssetRow && !anchor.firstAssetId.isEmpty()
                && m_assetIndex.contains(anchor.firstAssetId)) {
            const int nr = rowIndexForAssetId(anchor.firstAssetId);
            if (nr >= 0) {
                dy = m_rows.at(nr).y - anchor.oldY;
            }
        } else if (!anchor.day.isEmpty()) {
            bool resolved = false;
            for (const TimelineBucket &bucket : m_buckets) {
                if (bucket.timeBucket != anchor.day) {
                    continue;
                }
                for (int i = bucket.rowStart; i >= 0 && i <= bucket.rowEnd && i < m_rows.size(); ++i) {
                    if (m_rows.at(i).type == RenderRow::DayHeader) {
                        dy = m_rows.at(i).y - anchor.dayHeaderOldY;
                        resolved = true;
                        break;
                    }
                }
                break;
            }
            if (!resolved) {
                const int nr = rowIndexForGlobalAsset(anchor.firstGlobal);
                if (nr >= 0 && nr < m_rows.size()) {
                    dy = m_rows.at(nr).y - anchor.oldY;
                }
            }
        }
    }
    if (qAbs(dy) > 0.5) {
        emit layoutShifted(dy);
    }
    bumpLayoutVersion();
}

void TimelineModel::invalidateRowCaches(int bucketIndex)
{
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return;
    const TimelineBucket &bucket = m_buckets.at(bucketIndex);
    for (int r = bucket.rowStart; r >= 0 && r <= bucket.rowEnd && r < m_rows.size(); ++r) {
        m_rows[r].cachedAssets.clear();
        m_rows[r].contentKeyValid = false;
    }
}

QVariantMap TimelineModel::renderRowAt(int rowIndex) const
{
    QVariantMap result;
    if (rowIndex < 0 || rowIndex >= m_rows.size())
        return result;
    const RenderRow &row = m_rows.at(rowIndex);
    result[QStringLiteral("type")] = row.type;
    result[QStringLiteral("bucketIndex")] = row.bucketIndex;
    result[QStringLiteral("label")] = row.label;
    result[QStringLiteral("y")] = row.y;
    result[QStringLiteral("height")] = row.height;
    result[QStringLiteral("firstAsset")] = row.firstAsset;
    result[QStringLiteral("assetCount")] = row.assetCount;
    result[QStringLiteral("firstGlobal")] = row.firstGlobal;
    if (row.bucketIndex >= 0 && row.bucketIndex < m_buckets.size()) {
        const TimelineBucket &bucket = m_buckets.at(row.bucketIndex);
        result[QStringLiteral("loading")] = !bucket.loaded;
        result[QStringLiteral("inflight")] = bucket.loading;
        result[QStringLiteral("needsLoad")] = !bucket.loaded || bucket.stale;
        result[QStringLiteral("bucketCount")] = bucket.count;
        if (bucket.loaded && (row.type == RenderRow::AssetRow || row.type == RenderRow::DayHeader)) {
            if (!row.contentKeyValid) {
                uint seed = qHash(row.type);
                seed ^= uint(row.firstAsset) + 0x9e3779b9u + (seed << 6) + (seed >> 2);
                seed ^= uint(row.assetCount) + 0x9e3779b9u + (seed << 6) + (seed >> 2);
                const int end = qMin(row.firstAsset + row.assetCount, bucket.assets.size());
                for (int i = row.firstAsset; i < end; ++i) {
                    const uint h = qHash(bucket.assets.at(i));
                    seed ^= h + 0x9e3779b9u + (seed << 6) + (seed >> 2);
                }
                row.contentKey = seed;
                row.contentKeyValid = true;
            }
            result[QStringLiteral("contentKey")] = QString::number(row.contentKey);
        } else {
            result[QStringLiteral("contentKey")] = QString();
        }
    }
    return result;
}

QVariantList TimelineModel::renderRowAssets(int rowIndex) const
{
    QVariantList result;
    if (rowIndex < 0 || rowIndex >= m_rows.size())
        return result;
    const RenderRow &row = m_rows.at(rowIndex);
    if (row.type != RenderRow::AssetRow && row.type != RenderRow::DayHeader)
        return result;
    if (row.bucketIndex < 0 || row.bucketIndex >= m_buckets.size())
        return result;

    const TimelineBucket &bucket = m_buckets.at(row.bucketIndex);
    if (!bucket.loaded)
        return result;
    if (!row.cachedAssets.isEmpty())
        return row.cachedAssets;

    const int end = qMin(row.firstAsset + row.assetCount, bucket.assets.size());
    for (int i = row.firstAsset; i < end; ++i) {
        QVariantMap assetMap = assetToVariantMap(bucket.assets.at(i));
        assetMap[QStringLiteral("assetIndex")] = i;
        result.append(assetMap);
    }
    row.cachedAssets = result;
    return result;
}

int TimelineModel::firstRowAtY(qreal y) const
{
    int lo = 0;
    int hi = m_rows.size() - 1;
    int res = m_rows.size();
    while (lo <= hi) {
        const int mid = (lo + hi) >> 1;
        const RenderRow &row = m_rows.at(mid);
        if (row.y + row.height > y) {
            res = mid;
            hi = mid - 1;
        } else {
            lo = mid + 1;
        }
    }
    return res;
}

int TimelineModel::lastRowAtY(qreal y) const
{
    int lo = 0;
    int hi = m_rows.size() - 1;
    int res = -1;
    while (lo <= hi) {
        const int mid = (lo + hi) >> 1;
        if (m_rows.at(mid).y < y) {
            res = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    return res;
}

int TimelineModel::rowIndexForAsset(int bucketIndex, int assetIndex) const
{
    if (bucketIndex < 0 || bucketIndex >= m_buckets.size())
        return -1;
    const TimelineBucket &bucket = m_buckets.at(bucketIndex);
    if (bucket.rowStart < 0)
        return -1;
    if (assetIndex < 0)
        return bucket.rowStart;

    int lo = bucket.rowStart;
    int hi = bucket.rowEnd;
    int res = -1;
    while (lo <= hi) {
        const int mid = (lo + hi) >> 1;
        const RenderRow &row = m_rows.at(mid);
        if (row.firstAsset <= assetIndex) {
            if (row.type == RenderRow::AssetRow)
                res = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    if (res >= 0 && assetIndex < m_rows.at(res).firstAsset + m_rows.at(res).assetCount)
        return res;
    return bucket.rowStart;
}

int TimelineModel::rowIndexForGlobalAsset(int globalIndex) const
{
    if (m_rows.isEmpty())
        return -1;
    int lo = 0;
    int hi = m_rows.size() - 1;
    int res = 0;
    while (lo <= hi) {
        const int mid = (lo + hi) >> 1;
        if (m_rows.at(mid).firstGlobal <= globalIndex) {
            res = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    return res;
}

int TimelineModel::rowIndexForAssetId(const QString &assetId) const
{
    const auto it = m_assetIndex.constFind(assetId);
    if (it == m_assetIndex.constEnd()) {
        return -1;
    }
    return rowIndexForAsset(it.value().first, it.value().second);
}

QVariantMap TimelineModel::nearestMonthEntry(qreal y) const
{
    QVariantMap result;
    if (m_monthEntries.isEmpty())
        return result;

    int lo = 0;
    int hi = m_monthEntries.size();
    while (lo < hi) {
        const int mid = (lo + hi) >> 1;
        if (m_monthEntries.at(mid).y < y) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }

    int best = -1;
    if (lo < m_monthEntries.size())
        best = lo;
    if (lo > 0 && (best < 0 || (y - m_monthEntries.at(lo - 1).y) <= (m_monthEntries.at(best).y - y)))
        best = lo - 1;
    if (best < 0)
        best = 0;

    result[QStringLiteral("y")] = m_monthEntries.at(best).y;
    result[QStringLiteral("label")] = m_monthEntries.at(best).label;
    return result;
}

static bool runDayQuery(QSqlQuery &q, const QVariantList &binds, const QString &dayKey, QList<TimelineAsset> &out)
{
    const QDate day = QDate::fromString(dayKey.left(10), Qt::ISODate);
    if (!day.isValid()) {
        return false;
    }
    const QDateTime start(day, QTime(0, 0), Qt::LocalTime);
    const QDateTime end = start.addDays(1);

    for (int i = 0; i < binds.size(); ++i) {
        q.bindValue(i, binds.at(i));
    }
    q.bindValue(binds.size(), start.toUTC().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'")));
    q.bindValue(binds.size() + 1, end.toUTC().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'")));

    if (!q.exec()) {
        return false;
    }

    while (q.next()) {
        TimelineAsset asset;
        const bool isLocalRow = q.value(0).isNull();
        const QString localPath = q.value(10).toString();
        if (isLocalRow) {
            asset.id = QStringLiteral("local:") + localPath;
            asset.isLocal = true;
            asset.localPath = localPath;
        } else {
            asset.id = q.value(0).toString();
            asset.localPath = localPath; // uploaded copy that also exists on device
        }
        asset.type = q.value(1).toString();
        asset.createdAt = QDateTime::fromString(q.value(2).toString(), Qt::ISODate);
        asset.isFavorite = q.value(3).toInt() != 0;
        asset.thumbhash = q.value(4).toString();
        const QVariant dur = q.value(5);
        asset.duration = dur.isNull() ? QString() : QString::number(dur.toLongLong());
        asset.stackId = q.value(6).toString();
        asset.stackAssetCount = q.value(7).toInt();
        asset.livePhotoVideoId = q.value(8).toString();
        asset.ownerId = q.value(9).toString();
        asset.name = q.value(11).toString();
        out.append(asset);
    }
    q.finish();
    return true;
}

void CatalogQueryWorker::refresh(quint64 gen, const QString &bucketSql, const QString &daySql, const QVariantList &binds, const QStringList &reloadDays, int preloadBudget)
{
    QStringList days;
    QList<int> counts;
    QStringList loadedDays;
    QList<QList<TimelineAsset>> assets;
    QStringList failedDays;

    AssetDatabase *adb = AssetDatabase::instance();
    QSqlDatabase conn = adb ? adb->db() : QSqlDatabase();
    conn.transaction();

    QSqlQuery q(conn);
    q.prepare(bucketSql);
    for (int i = 0; i < binds.size(); ++i) {
        q.bindValue(i, binds.at(i));
    }
    bool ok = q.exec();
    if (!ok) {
        qWarning() << "CatalogQueryWorker: Bucket query failed:" << q.lastError().text();
        conn.rollback();
        emit refreshReady(gen, days, counts, loadedDays, assets, failedDays, ok);
        return;
    }
    QSet<QString> presentDays;
    while (q.next()) {
        const QString day = q.value(0).toString();
        const int count = q.value(1).toInt();
        if (count > 0 && !day.isEmpty()) {
            days.append(day);
            counts.append(count);
            presentDays.insert(day);
        }
    }
    q.finish();

    q.prepare(daySql);
    const QSet<QString> reloadSet = QSet<QString>::fromList(reloadDays);
    auto loadDay = [&](const QString &day) {
        QList<TimelineAsset> list;
        if (runDayQuery(q, binds, day, list)) {
            loadedDays.append(day);
            assets.append(list);
        } else {
            failedDays.append(day);
        }
    };
    for (const QString &day : reloadDays) {
        if (presentDays.contains(day)) {
            loadDay(day);
        }
    }
    if (preloadBudget > 0) {
        int loaded = 0;
        int loadedDayCount = 0;
        for (int i = 0; i < days.size() && loaded < preloadBudget && loadedDayCount < 16; ++i) {
            const QString &day = days.at(i);
            if (reloadSet.contains(day)) {
                continue;
            }
            loadDay(day);
            loaded += counts.at(i);
            ++loadedDayCount;
        }
    }
    conn.commit();

    emit refreshReady(gen, days, counts, loadedDays, assets, failedDays, ok);
}

void CatalogQueryWorker::queryDays(quint64 gen, const QString &sql, const QVariantList &binds, const QStringList &days)
{
    QStringList doneDays;
    QList<QList<TimelineAsset>> assets;
    QStringList failedDays;

    AssetDatabase *adb = AssetDatabase::instance();
    QSqlDatabase conn = adb ? adb->db() : QSqlDatabase();
    conn.transaction();
    QSqlQuery q(conn);
    q.prepare(sql);

    for (const QString &dayKey : days) {
        QList<TimelineAsset> list;
        if (!runDayQuery(q, binds, dayKey, list)) {
            qWarning() << "CatalogQueryWorker: Day query failed for" << dayKey << ":" << q.lastError().text();
            failedDays.append(dayKey);
            continue;
        }
        doneDays.append(dayKey);
        assets.append(list);
    }
    conn.commit();

    emit daysReady(gen, doneDays, assets, failedDays);
}

void CatalogQueryWorker::resolveAssetDay(quint64 gen, const QString &sql, const QVariantList &binds, const QString &assetId)
{
    QString day;
    QString resolvedId;

    AssetDatabase *adb = AssetDatabase::instance();
    QSqlQuery q(adb ? adb->db() : QSqlDatabase());
    q.prepare(sql);
    for (int i = 0; i < binds.size(); ++i) {
        q.bindValue(i, binds.at(i));
    }
    if (!q.exec()) {
        qWarning() << "CatalogQueryWorker: Asset-day query failed:" << q.lastError().text();
    } else if (q.next()) {
        day = q.value(0).toString();
        resolvedId = q.value(1).toString();
    }
    emit assetDayResolved(gen, assetId, resolvedId, day);
}
