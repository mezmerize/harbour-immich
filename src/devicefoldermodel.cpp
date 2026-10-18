#include "devicefoldermodel.h"
#include "backupmanager.h"
#include "backgroundtasks.h"
#include "dateutils.h"
#include "immichapi.h"
#include <QFileInfo>
#include <QFile>
#include <QCryptographicHash>
#include <QJsonObject>
#include <QJsonValue>
#include <QLocale>
#include <QThreadPool>
#include <QTimer>
#include <QDebug>
#include <algorithm>

DeviceFolderModel::DeviceFolderModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_backupManager(nullptr)
    , m_immichApi(nullptr)
    , m_sortOrder(QStringLiteral("desc"))
    , m_checking(false)
    , m_loading(false)
    , m_columns(4)
    , m_checkHashToken(0)
    , m_checkBatchesPending(0)
    , m_checkBatchesSucceeded(0)
    , m_checkMatched(0)
    , m_checkHadFailures(false)
{
    m_checkToken = QStringLiteral("devicefolder-%1").arg(reinterpret_cast<quintptr>(this));
}

int DeviceFolderModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_rows.size();
}

QVariant DeviceFolderModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size()) {
        return QVariant();
    }
    const Row &r = m_rows.at(index.row());
    switch (role) {
    case RowTypeRole:
        return r.type;
    case TitleRole:
        return r.title;
    case IndicesRole: {
        QVariantList list;
        for (int i : r.indices) list.append(i);
        return list;
    }
    case AllSelectedRole:
        if (r.type != RowDayHeader) return false;
        return dayAllSelected(r.indices);
    case ItemsRole:
        if (r.type != RowAssets) return QVariantList();
        return itemsForRow(r);
    }
    return QVariant();
}

QHash<int, QByteArray> DeviceFolderModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[RowTypeRole] = "rowType";
    roles[TitleRole] = "title";
    roles[IndicesRole] = "indices";
    roles[AllSelectedRole] = "allSelected";
    roles[ItemsRole] = "items";
    return roles;
}

void DeviceFolderModel::init(QObject *backupManager, QObject *immichApi)
{
    BackupManager *bm = qobject_cast<BackupManager*>(backupManager);
    ImmichApi *api = qobject_cast<ImmichApi*>(immichApi);

    if (bm) m_backupManager = bm;
    if (api) m_immichApi = api;

    if (m_immichApi) {
        connect(m_immichApi, &ImmichApi::assetUploaded, this, &DeviceFolderModel::onAssetUploaded, Qt::UniqueConnection);
        connect(m_immichApi, &ImmichApi::bulkUploadCheckCompleted, this, &DeviceFolderModel::onBulkUploadCheckCompleted, Qt::UniqueConnection);
        connect(m_immichApi, &ImmichApi::bulkUploadCheckFailed, this, &DeviceFolderModel::onBulkUploadCheckFailed, Qt::UniqueConnection);
    }
    if (m_backupManager) {
        connect(m_backupManager, &BackupManager::backupStatusChanged, this, &DeviceFolderModel::onBackupStatusChanged, Qt::UniqueConnection);
        connect(m_backupManager, &BackupManager::fileBackedUp, this, [this](const QString &filePath, const QString &remoteAssetId) {
            auto it = m_trackedRecords.find(filePath);
            if (it != m_trackedRecords.end()) {
                it->status = BackupDatabase::BackedUp;
                it->remoteAssetId = remoteAssetId;
            }
            updateStatusForPath(filePath, StatusBackedUp);
        }, Qt::UniqueConnection);
        m_backupManager->ensureMediaTypesFetched();
        connect(m_backupManager, &BackupManager::mediaTypesReadyChanged, this, [this]() {
            if (m_scanPending && !m_folderPath.isEmpty()) {
                refresh();
            }
        }, Qt::UniqueConnection);
    }
}

void DeviceFolderModel::setFolder(const QString &path)
{
    QString clean = path;
    while (clean.size() > 1 && clean.endsWith('/'))
        clean.chop(1);
    if (clean != m_folderPath)
        m_pendingSelection.clear();
    m_folderPath = clean;
    m_folderName = clean.section('/', -1);
    if (m_folderName.isEmpty())
        m_folderName = clean;
    emit folderChanged();
    refresh();
}

void DeviceFolderModel::refresh()
{
    if (m_folderPath.isEmpty() || !m_backupManager)
        return;
    setLoading(true);
    m_backupManager->pruneDeletedFilesInFolder(m_folderPath);
    if (m_backupManager->mediaExtensions().isEmpty()) {
        m_scanPending = true;
        return;
    }
    m_scanPending = false;
    const quint64 token = ++m_scanToken;
    auto *task = new MediaScanTask({m_folderPath}, m_backupManager->mediaExtensions(), 0, token);
    connect(task, &MediaScanTask::completed, this, &DeviceFolderModel::onScanDone);
    QThreadPool::globalInstance()->start(task);
}

void DeviceFolderModel::onScanDone(quint64 token, const QVariantList &files)
{
    if (token != m_scanToken)
        return;
    rebuildEntries(files);
    if (!m_pendingSelection.isEmpty()) {
        const QStringList pending = m_pendingSelection;
        m_pendingSelection.clear();
        applySelection(pending);
    }
    setLoading(false);
    emit countChanged();
    emit selectedCountChanged();
    executeAutoCheck();
}

void DeviceFolderModel::rebuildEntries(const QVariantList &files)
{
    beginResetModel();
    QSet<QString> previouslySelected;
    for (const Entry &e : m_entries) {
        if (e.selected)
            previouslySelected.insert(e.path);
    }
    m_entries.clear();
    m_pathIndex.clear();

    BackupDatabase *db = m_backupManager ? m_backupManager->database() : nullptr;
    m_trackedRecords = db ? db->recordsWithPrefix(m_folderPath + QLatin1Char('/')) : QHash<QString, BackupDatabase::FileRecord>();

    for (const QVariant &v : files) {
        const QVariantMap f = v.toMap();
        const QString path = f.value(QStringLiteral("path")).toString();
        if (path.isEmpty())
            continue;
        Entry e;
        e.path = path;
        e.name = path.section(QLatin1Char('/'), -1);
        e.size = f.value(QStringLiteral("size")).toLongLong();
        e.modified = QDateTime::fromMSecsSinceEpoch(f.value(QStringLiteral("modified")).toLongLong());
        e.isVideo = m_backupManager->isVideoFilePath(path);
        e.selected = previouslySelected.contains(path);
        e.status = computeStatus(e);
        m_entries.append(e);
    }

    sortEntries();
    buildGroups();
    rebuildRows();
    endResetModel();
    m_folderFingerprint = computeFingerprint();
}

void DeviceFolderModel::sortEntries()
{
    const bool ascending = (m_sortOrder == QStringLiteral("asc"));
    std::sort(m_entries.begin(), m_entries.end(), [ascending](const Entry &a, const Entry &b) {
        if (a.modified == b.modified) {
            return ascending ? (a.name < b.name) : (a.name > b.name);
        }
        return ascending ? (a.modified < b.modified) : (a.modified > b.modified);
    });
    m_pathIndex.clear();
    m_pathIndex.reserve(m_entries.size());
    for (int i = 0; i < m_entries.size(); ++i) {
        m_pathIndex.insert(m_entries[i].path, i);
    }
}

int DeviceFolderModel::computeStatus(const Entry &entry) const
{
    if (!m_backupManager)
        return StatusUnknown;
    auto it = m_trackedRecords.constFind(entry.path);
    if (it != m_trackedRecords.constEnd()) {
        const BackupDatabase::FileRecord &rec = it.value();
        const bool unchanged = entry.size == rec.size && entry.modified.toMSecsSinceEpoch() == rec.modified;
        if (rec.status == BackupDatabase::BackedUp && unchanged) {
            return StatusBackedUp;
        }
    }
    int overrideStatus = m_backupManager->deviceFileStatusOverride(entry.path);
    if (overrideStatus == StatusBackedUp || overrideStatus == StatusNotBackedUp) {
        return overrideStatus;
    }
    if (it != m_trackedRecords.constEnd()) {
        return StatusNotBackedUp;
    }
    return StatusUnknown;
}

void DeviceFolderModel::recomputeStatuses()
{
    if (m_entries.isEmpty())
        return;
    if (m_backupManager) {
        m_trackedRecords = m_backupManager->database()->recordsWithPrefix(m_folderPath + QLatin1Char('/'));
    }
    QSet<int> changed;
    for (int i = 0; i < m_entries.size(); i++) {
        Entry &e = m_entries[i];
        int newStatus = computeStatus(e);
        if (newStatus != e.status) {
            e.status = newStatus;
            changed.insert(i);
            emit entryChanged(i);
        }
    }
    if (!changed.isEmpty())
        emitAssetRowsChanged(changed);
}

void DeviceFolderModel::toggleSelection(int index)
{
    if (index < 0 || index >= m_entries.size())
        return;
    m_entries[index].selected = !m_entries[index].selected;
    QSet<int> changed;
    changed.insert(index);
    emitAssetRowsChanged(changed);
    emitDayRowsChanged(changed);
    emit selectedCountChanged();
    if (m_entries[index].selected) {
        emit selectionEdited({m_entries[index].path}, {});
    } else {
        emit selectionEdited({}, {m_entries[index].path});
    }
}

void DeviceFolderModel::clearSelection()
{
    QSet<int> changed;
    QStringList deselected;
    for (int i = 0; i < m_entries.size(); i++) {
        if (m_entries[i].selected) {
            m_entries[i].selected = false;
            changed.insert(i);
            deselected.append(m_entries[i].path);
        }
    }
    if (!changed.isEmpty()) {
        emitAssetRowsChanged(changed);
        emitDayRowsChanged(changed);
        emit selectedCountChanged();
        emit selectionEdited({}, deselected);
    }
}

QStringList DeviceFolderModel::selectedPaths() const
{
    QStringList paths;
    for (const Entry &e : m_entries) {
        if (e.selected)
            paths.append(e.path);
    }
    return paths;
}

void DeviceFolderModel::setIndicesSelected(const QVariantList &indices, bool selected)
{
    QSet<int> changed;
    QStringList editedPaths;
    for (const QVariant &v : indices) {
        int idx = v.toInt();
        if (idx < 0 || idx >= m_entries.size())
            continue;
        if (m_entries.at(idx).selected != selected) {
            m_entries[idx].selected = selected;
            changed.insert(idx);
            editedPaths.append(m_entries[idx].path);
        }
    }
    if (!changed.isEmpty()) {
        emitAssetRowsChanged(changed);
        emitDayRowsChanged(changed);
        emit selectedCountChanged();
        if (selected) {
            emit selectionEdited(editedPaths, {});
        } else {
            emit selectionEdited({}, editedPaths);
        }
    }
}

void DeviceFolderModel::selectPaths(const QStringList &paths)
{
    if (m_loading) {
        m_pendingSelection = paths;
        return;
    }
    applySelection(paths);
}

void DeviceFolderModel::applySelection(const QStringList &paths)
{
    QSet<int> changed;
    for (const QString &path : paths) {
        const int idx = m_pathIndex.value(path, -1);
        if (idx < 0 || m_entries.at(idx).selected)
            continue;
        m_entries[idx].selected = true;
        changed.insert(idx);
    }
    if (!changed.isEmpty()) {
        emitAssetRowsChanged(changed);
        emitDayRowsChanged(changed);
        emit selectedCountChanged();
    }
}

QVariantMap DeviceFolderModel::get(int index) const
{
    QVariantMap map;
    if (index < 0 || index >= m_entries.size())
        return map;
    const Entry &e = m_entries.at(index);
    map["filePath"] = e.path;
    map["fileName"] = e.name;
    map["fileSize"] = e.size;
    map["lastModified"] = e.modified;
    map["isVideo"] = e.isVideo;
    map["backupStatus"] = e.status;
    map["remoteAssetId"] = (e.status == StatusBackedUp) ? m_trackedRecords.value(e.path).remoteAssetId : QString();
    map["index"] = index;
    return map;
}

int DeviceFolderModel::indexOfPath(const QString &filePath) const
{
    return m_pathIndex.value(filePath, -1);
}

QStringList DeviceFolderModel::heroPaths(int max) const
{
    QStringList paths;
    for (const Entry &e : m_entries) {
        if (paths.size() >= max)
            break;
        paths.append(e.path);
    }
    return paths;
}

void DeviceFolderModel::runServerCheck()
{
    if (!m_backupManager)
        return;
    QStringList toCheck;
    for (const Entry &e : m_entries) {
        if (computeStatus(e) != StatusBackedUp) {
            toCheck.append(e.path);
        }
    }
    startServerCheck(toCheck);
}

void DeviceFolderModel::startServerCheck(const QStringList &paths)
{
    if (m_checking) {
        qInfo() << "DeviceFolderModel: Check already in progress";
        return;
    }
    if (!m_immichApi) {
        return;
    }
    if (paths.isEmpty()) {
        // All files already backed up
        m_backupManager->setDeviceFolderCheckFingerprint(m_folderPath, m_folderFingerprint);
        return;
    }

    setChecking(true);
    m_checkDeviceIdToPath.clear();
    m_checkSeenIds.clear();
    m_checkMatched = 0;
    m_checkBatchesPending = 0;
    m_checkBatchesSucceeded = 0;
    m_checkHadFailures = false;

    const quint64 token = ++m_checkHashToken;
    auto *task = new ChecksumTask(paths, token);
    connect(task, &ChecksumTask::completed, this, &DeviceFolderModel::onChecksumsDone);
    QThreadPool::globalInstance()->start(task);
}

void DeviceFolderModel::onChecksumsDone(quint64 token, const QVariantList &entries)
{
    if (token != m_checkHashToken || !m_checking)
        return;

    QJsonArray allAssets;
    for (const QVariant &v : entries) {
        const QVariantMap e = v.toMap();
        const QString path = e[QStringLiteral("path")].toString();
        const QString checksum = e[QStringLiteral("checksum")].toString();
        if (checksum.isEmpty())
            continue;
        const QString deviceAssetId = BackupDatabase::makeDeviceAssetId(QFileInfo(path).fileName(), e[QStringLiteral("modified")].toLongLong());
        m_checkDeviceIdToPath.insert(deviceAssetId, path);

        QJsonObject asset;
        asset["id"] = deviceAssetId;
        asset["checksum"] = checksum;
        allAssets.append(asset);
    }

    if (allAssets.isEmpty()) {
        setChecking(false);
        m_backupManager->setDeviceFolderCheckFingerprint(m_folderPath, m_folderFingerprint);
        return;
    }

    static const int BATCH_SIZE = 500;
    for (int i = 0; i < allAssets.size(); i += BATCH_SIZE) {
        QJsonArray batch;
        for (int j = i; j < qMin(i + BATCH_SIZE, allAssets.size()); j++) {
            batch.append(allAssets[j]);
        }
        m_checkBatchesPending++;
        m_immichApi->bulkUploadCheck(batch, m_checkToken);
    }
}

void DeviceFolderModel::onBulkUploadCheckCompleted(const QJsonArray &results, const QString &token)
{
    if (token != m_checkToken || !m_checking)
        return;

    for (const QJsonValue &val : results) {
        QJsonObject result = val.toObject();
        QString deviceAssetId = result["id"].toString();
        QString action = result["action"].toString();
        QString remoteAssetId = result["assetId"].toString();
        m_checkSeenIds.insert(deviceAssetId);

        if (action == QStringLiteral("reject")) {
            QString path = m_checkDeviceIdToPath.value(deviceAssetId);
            if (!path.isEmpty()) {
                if (m_backupManager) {
                    m_backupManager->markDeviceFileBackedUp(path, remoteAssetId);
                    m_backupManager->setDeviceFileStatusOverride(path, StatusBackedUp);
                }
                updateStatusForPath(path, StatusBackedUp);
                m_checkMatched++;
            }
        }
    }

    m_checkBatchesSucceeded++;
    m_checkBatchesPending--;
    if (m_checkBatchesPending <= 0) {
        finishServerCheck();
    }
}

void DeviceFolderModel::onBulkUploadCheckFailed(const QString &token)
{
    if (token != m_checkToken || !m_checking)
        return;

    qWarning() << "DeviceFolderModel: Bulk upload check batch failed";
    m_checkHadFailures = true;
    m_checkBatchesPending--;
    if (m_checkBatchesPending <= 0) {
        finishServerCheck();
    }
}

void DeviceFolderModel::finishServerCheck()
{
    int notBackedUp = 0;
    QSet<int> changed;

    if (m_checkBatchesSucceeded > 0) {
        for (auto it = m_checkDeviceIdToPath.constBegin(); it != m_checkDeviceIdToPath.constEnd(); ++it) {
            if (!m_checkSeenIds.contains(it.key()))
                continue;
            const QString &path = it.value();
            int idx = indexOfPath(path);
            if (idx < 0)
                continue;
            if (m_entries.at(idx).status == StatusBackedUp)
                continue;
            notBackedUp++;
            if (m_backupManager) m_backupManager->setDeviceFileStatusOverride(path, StatusNotBackedUp);
            if (m_entries[idx].status != StatusNotBackedUp) {
                m_entries[idx].status = StatusNotBackedUp;
                changed.insert(idx);
            }
        }
    }

    m_checkDeviceIdToPath.clear();
    m_checkSeenIds.clear();
    setChecking(false);

    if (m_checkBatchesSucceeded > 0) {
        if (!m_checkHadFailures) {
            m_backupManager->setDeviceFolderCheckFingerprint(m_folderPath, m_folderFingerprint);
        }
        if (!changed.isEmpty()) {
            for (int idx : changed)
                emit entryChanged(idx);
            emitAssetRowsChanged(changed);
        }
    } else {
        emit serverCheckFailed();
    }
}

void DeviceFolderModel::executeAutoCheck()
{
    if (!m_backupManager || m_checking || m_folderPath.isEmpty() || m_folderFingerprint.isEmpty()) {
        return;
    }
    if (m_backupManager->deviceFolderCheckFingerprint(m_folderPath) == m_folderFingerprint) {
        return;
    }
    QTimer::singleShot(0, this, [this]() {
        runServerCheck();
    });
}

QString DeviceFolderModel::computeFingerprint() const
{
    QStringList parts;
    parts.reserve(m_entries.size());
    for (const Entry &e : m_entries) {
        const QString rel = e.path.startsWith(m_folderPath + QLatin1Char('/')) ? e.path.mid(m_folderPath.size() + 1) : e.path;
        parts.append(QStringLiteral("%1|%2|%3").arg(rel).arg(e.size).arg(e.modified.toMSecsSinceEpoch()));
    }
    parts.sort();
    return QString::fromLatin1(QCryptographicHash::hash(parts.join(QLatin1Char('\n')).toUtf8(), QCryptographicHash::Sha1).toHex());
}

void DeviceFolderModel::onAssetUploaded(const QString &assetId, const QString &filePath, const QString &status)
{
    Q_UNUSED(status)
    int idx = indexOfPath(filePath);
    if (idx < 0)
        return;
    if (m_backupManager) {
        m_backupManager->markDeviceFileBackedUp(filePath, assetId);
        m_backupManager->setDeviceFileStatusOverride(filePath, StatusBackedUp);
    }
    updateStatusForPath(filePath, StatusBackedUp);
}

void DeviceFolderModel::onBackupStatusChanged()
{
    if (m_checking) return;
    recomputeStatuses();
}

void DeviceFolderModel::updateStatusForPath(const QString &path, int status)
{
    int idx = indexOfPath(path);
    if (idx < 0)
        return;
    if (m_entries.at(idx).status == status) return;
    m_entries[idx].status = status;
    emit entryChanged(idx);
    QSet<int> changed;
    changed.insert(idx);
    emitAssetRowsChanged(changed);
}

void DeviceFolderModel::removeLocalFiles(const QStringList &paths)
{
    int removed = 0;
    for (const QString &path : paths) {
        if (QFile::remove(path)) {
            removed++;
        }
        if (m_backupManager) m_backupManager->handleLocalFileDeletion(path);
    }
    if (removed > 0) {
        refresh();
        emit filesRemoved(removed);
    }
}

void DeviceFolderModel::setChecking(bool checking)
{
    if (m_checking != checking) {
        m_checking = checking;
        emit checkingChanged();
    }
}

void DeviceFolderModel::setLoading(bool loading)
{
    if (m_loading != loading) {
        m_loading = loading;
        emit loadingChanged();
    }
}

int DeviceFolderModel::count() const
{
    return m_entries.size();
}

int DeviceFolderModel::selectedCount() const
{
    int n = 0;
    for (const Entry &e : m_entries) {
        if (e.selected) n++;
    }
    return n;
}

QString DeviceFolderModel::folderPath() const
{
    return m_folderPath;
}

QString DeviceFolderModel::folderName() const
{
    return m_folderName;
}

QString DeviceFolderModel::sortOrder() const
{
    return m_sortOrder;
}

void DeviceFolderModel::setSortOrder(const QString &order)
{
    QString normalized = (order == QStringLiteral("asc")) ? QStringLiteral("asc") : QStringLiteral("desc");
    if (m_sortOrder != normalized) {
        m_sortOrder = normalized;
        emit sortOrderChanged();
        beginResetModel();
        sortEntries();
        buildGroups();
        rebuildRows();
        endResetModel();
    }
}

bool DeviceFolderModel::checking() const
{
    return m_checking;
}

bool DeviceFolderModel::loading() const
{
    return m_loading;
}

int DeviceFolderModel::columns() const
{
    return m_columns;
}

void DeviceFolderModel::setColumns(int columns)
{
    int normalized = qMax(1, columns);
    if (m_columns != normalized) {
        m_columns = normalized;
        emit columnsChanged();
        beginResetModel();
        rebuildRows();
        endResetModel();
    }
}

void DeviceFolderModel::buildGroups()
{
    m_groups.clear();

    QString curMonthKey;
    QString curDayKey;
    MonthGroup *month = nullptr;
    DaySubGroup *day = nullptr;

    for (int i = 0; i < m_entries.size(); i++) {
        const QDateTime &dt = m_entries.at(i).modified;
        const QDate d = dt.date();
        const QString monthKey = d.toString(QStringLiteral("yyyy-MM"));
        const QString dayKey = d.toString(Qt::ISODate);

        if (monthKey != curMonthKey || month == nullptr) {
            MonthGroup mg;
            mg.monthYear = DateUtils::monthYearLabel(dt.date());
            mg.count = 0;
            m_groups.append(mg);
            month = &m_groups.last();
            curMonthKey = monthKey;
            curDayKey.clear();
            day = nullptr;
        }

        if (dayKey != curDayKey || day == nullptr) {
            DaySubGroup ds;
            ds.displayDate = QLocale().toString(dt, QStringLiteral("dd.MM.yyyy"));
            month->days.append(ds);
            day = &month->days.last();
            curDayKey = dayKey;
        }

        day->indices.append(i);
        month->count++;
    }
}

void DeviceFolderModel::rebuildRows()
{
    m_rows.clear();
    m_entryAssetRow = QVector<int>(m_entries.size(), -1);
    m_entryDayRow = QVector<int>(m_entries.size(), -1);
    const int columns = qMax(1, m_columns);

    for (const MonthGroup &mg : m_groups) {
        Row monthRow;
        monthRow.type = RowMonthHeader;
        monthRow.title = mg.monthYear;
        m_rows.append(monthRow);

        for (const DaySubGroup &ds : mg.days) {
            Row dayRow;
            dayRow.type = RowDayHeader;
            dayRow.title = ds.displayDate;
            dayRow.indices = ds.indices;
            const int dayRowIndex = m_rows.size();
            m_rows.append(dayRow);
            for (int idx : ds.indices)
                m_entryDayRow[idx] = dayRowIndex;

            for (int i = 0; i < ds.indices.size(); i += columns) {
                Row assetRow;
                assetRow.type = RowAssets;
                const int assetRowIndex = m_rows.size();
                for (int j = i; j < qMin(i + columns, ds.indices.size()); j++) {
                    int idx = ds.indices.at(j);
                    assetRow.indices.append(idx);
                    m_entryAssetRow[idx] = assetRowIndex;
                }
                m_rows.append(assetRow);
            }
        }
    }
}

void DeviceFolderModel::emitAssetRowsChanged(const QSet<int> &entryIndices)
{
    QSet<int> rows;
    for (int idx : entryIndices) {
        if (idx >= 0 && idx < m_entryAssetRow.size() && m_entryAssetRow.at(idx) >= 0) {
            rows.insert(m_entryAssetRow.at(idx));
        }
    }
    for (int row : rows) {
        emit dataChanged(index(row, 0), index(row, 0), QVector<int>() << ItemsRole);
    }
}

void DeviceFolderModel::emitDayRowsChanged(const QSet<int> &entryIndices)
{
    QSet<int> rows;
    for (int idx : entryIndices) {
        if (idx >= 0 && idx < m_entryDayRow.size() && m_entryDayRow.at(idx) >= 0) {
            rows.insert(m_entryDayRow.at(idx));
        }
    }
    for (int row : rows) {
        emit dataChanged(index(row, 0), index(row, 0), QVector<int>() << AllSelectedRole);
    }
}

bool DeviceFolderModel::dayAllSelected(const QList<int> &indices) const
{
    if (indices.isEmpty())
        return false;
    for (int idx : indices) {
        if (idx < 0 || idx >= m_entries.size() || !m_entries.at(idx).selected)
            return false;
    }
    return true;
}

QVariantList DeviceFolderModel::itemsForRow(const Row &row) const
{
    QVariantList items;
    for (int idx : row.indices) {
        if (idx < 0 || idx >= m_entries.size())
            continue;
        const Entry &e = m_entries.at(idx);
        QVariantMap item;
        item[QStringLiteral("index")] = idx;
        item[QStringLiteral("filePath")] = e.path;
        item[QStringLiteral("isVideo")] = e.isVideo;
        item[QStringLiteral("status")] = e.status;
        item[QStringLiteral("selected")] = e.selected;
        item[QStringLiteral("remoteAssetId")] = (e.status == StatusBackedUp) ? m_trackedRecords.value(e.path).remoteAssetId : QString();
        items.append(item);
    }
    return items;
}
