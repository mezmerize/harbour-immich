#ifndef DEVICEFOLDERMODEL_H
#define DEVICEFOLDERMODEL_H

#include "backupdatabase.h"
#include <QAbstractListModel>
#include <QDateTime>
#include <QJsonArray>
#include <QMap>
#include <QSet>
#include <QVector>
#include <QVariantList>
#include <QVariantMap>

class BackupManager;
class ImmichApi;

class DeviceFolderModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectedCountChanged)
    Q_PROPERTY(QString folderPath READ folderPath NOTIFY folderChanged)
    Q_PROPERTY(QString folderName READ folderName NOTIFY folderChanged)
    Q_PROPERTY(QString sortOrder READ sortOrder WRITE setSortOrder NOTIFY sortOrderChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY checkingChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(int columns READ columns WRITE setColumns NOTIFY columnsChanged)

public:
    enum Status {
        StatusUnknown = 0,
        StatusBackedUp = 1,
        StatusNotBackedUp = 2
    };
    Q_ENUM(Status)

    enum RowType {
        RowMonthHeader = 0,
        RowDayHeader = 1,
        RowAssets = 2
    };
    Q_ENUM(RowType)

    enum Roles {
        RowTypeRole = Qt::UserRole + 1,
        TitleRole,
        IndicesRole,
        AllSelectedRole,
        ItemsRole
    };

    explicit DeviceFolderModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Wiring
    Q_INVOKABLE void init(QObject *backupManager, QObject *immichApi);

    // Folder management
    Q_INVOKABLE void setFolder(const QString &path);
    Q_INVOKABLE void refresh();

    // Selection
    Q_INVOKABLE void toggleSelection(int index);
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE QStringList selectedPaths() const;
    Q_INVOKABLE void setIndicesSelected(const QVariantList &indices, bool selected);
    Q_INVOKABLE void selectPaths(const QStringList &paths);

    // Accessors
    Q_INVOKABLE QVariantMap get(int index) const;
    int indexOfPath(const QString &filePath) const;
    Q_INVOKABLE QStringList heroPaths(int max) const;

    // Local file operations
    Q_INVOKABLE void removeLocalFiles(const QStringList &paths);

    // Properties
    int count() const;
    int selectedCount() const;
    QString folderPath() const;
    QString folderName() const;
    QString sortOrder() const;
    void setSortOrder(const QString &order);
    bool checking() const;
    bool loading() const;
    int columns() const;
    void setColumns(int columns);

signals:
    void countChanged();
    void selectedCountChanged();
    void folderChanged();
    void sortOrderChanged();
    void checkingChanged();
    void loadingChanged();
    void columnsChanged();
    void serverCheckFailed();
    void filesRemoved(int removedCount);
    void entryChanged(int index);
    void selectionEdited(const QStringList &selected, const QStringList &deselected);

private slots:
    void onAssetUploaded(const QString &assetId, const QString &filePath, const QString &status);
    void onBackupStatusChanged();
    void onBulkUploadCheckCompleted(const QJsonArray &results, const QString &token);
    void onBulkUploadCheckFailed(const QString &token);
    void onChecksumsDone(quint64 token, const QVariantList &entries);
    void onScanDone(quint64 token, const QVariantList &files);

private:
    struct Entry {
        QString path;
        QString name;
        qint64 size;
        QDateTime modified;
        bool isVideo;
        int status;
        bool selected;
    };

    struct DaySubGroup {
        QString displayDate;
        QList<int> indices;
    };

    struct MonthGroup {
        QString monthYear;
        QList<DaySubGroup> days;
        int count;
    };

    struct Row {
        int type;
        QString title;
        QList<int> indices;
    };

    BackupManager *m_backupManager;
    ImmichApi *m_immichApi;
    QString m_folderPath;
    QString m_folderName;
    QString m_sortOrder;
    QString m_checkToken;
    QString m_folderFingerprint;
    bool m_checking;
    bool m_loading;
    int m_columns;
    QList<Entry> m_entries;
    QHash<QString, int> m_pathIndex;
    QHash<QString, BackupDatabase::FileRecord> m_trackedRecords;
    QList<MonthGroup> m_groups;
    QList<Row> m_rows;
    QVector<int> m_entryAssetRow;
    QVector<int> m_entryDayRow;

    QMap<QString, QString> m_checkDeviceIdToPath;
    QSet<QString> m_checkSeenIds;
    quint64 m_checkHashToken;
    quint64 m_scanToken = 0;
    bool m_scanPending = false;
    QStringList m_pendingSelection;
    int m_checkBatchesPending;
    int m_checkBatchesSucceeded;
    int m_checkMatched;
    bool m_checkHadFailures;

    void rebuildEntries(const QVariantList &files);
    void applySelection(const QStringList &paths);
    void sortEntries();
    void buildGroups();
    void rebuildRows();
    int computeStatus(const Entry &entry) const;
    void recomputeStatuses();
    void runServerCheck();
    void startServerCheck(const QStringList &paths);
    void finishServerCheck();
    void executeAutoCheck();
    QString computeFingerprint() const;
    void setChecking(bool checking);
    void setLoading(bool loading);
    void updateStatusForPath(const QString &path, int status);
    void emitAssetRowsChanged(const QSet<int> &entryIndices);
    void emitDayRowsChanged(const QSet<int> &entryIndices);
    bool dayAllSelected(const QList<int> &indices) const;
    QVariantList itemsForRow(const Row &row) const;
};

#endif
