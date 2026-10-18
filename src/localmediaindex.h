#ifndef LOCALMEDIAINDEX_H
#define LOCALMEDIAINDEX_H

#include <QObject>
#include <QVariantList>
#include <QStringList>
#include <QSet>

class BackupManager;
class SettingsManager;
class AssetDatabase;

class LocalMediaIndex : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)

public:
    LocalMediaIndex(BackupManager *backupManager, SettingsManager *settings, AssetDatabase *db, QObject *parent = nullptr);

    Q_INVOKABLE void scan();
    bool scanning() const { return m_scanning; }

signals:
    void scanningChanged();

private slots:
    void onScanDone(quint64 token, const QVariantList &files);
    void onHashesDone(quint64 token, const QVariantList &entries);

private:
    void applyScan(const QVariantList &files);
    void hashNextBatch();
    void finishScan();

    BackupManager *m_backup;
    SettingsManager *m_settings;
    AssetDatabase *m_db;

    quint64 m_scanToken = 0;
    quint64 m_hashToken = 0;
    bool m_scanning = false;
    bool m_scanQueued = false;
    QStringList m_pendingHash;
    bool m_indexDirty = false;
};

#endif // LOCALMEDIAINDEX_H
