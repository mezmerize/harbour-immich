#ifndef SETTINGSMANAGER_H
#define SETTINGSMANAGER_H

#include <QObject>
#include <QSettings>
#include <QStringList>

class SettingsManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString detailQuality READ detailQuality WRITE setDetailQuality NOTIFY detailQualityChanged)
    Q_PROPERTY(int assetsPerRow READ assetsPerRow WRITE setAssetsPerRow NOTIFY assetsPerRowChanged)
    Q_PROPERTY(int memoriesThumbnailSize READ memoriesThumbnailSize WRITE setMemoriesThumbnailSize NOTIFY memoriesThumbnailSizeChanged)
    Q_PROPERTY(bool showMemoriesBar READ showMemoriesBar WRITE setShowMemoriesBar NOTIFY showMemoriesBarChanged)
    Q_PROPERTY(QString scrollToTopPosition READ scrollToTopPosition WRITE setScrollToTopPosition NOTIFY scrollToTopPositionChanged)
    Q_PROPERTY(bool backupEnabled READ backupEnabled WRITE setBackupEnabled NOTIFY backupEnabledChanged)
    Q_PROPERTY(QStringList backupFolders READ backupFolders WRITE setBackupFolders NOTIFY backupFoldersChanged)
    Q_PROPERTY(bool backupPhotosOnCellular READ backupPhotosOnCellular WRITE setBackupPhotosOnCellular NOTIFY backupPhotosOnCellularChanged)
    Q_PROPERTY(bool backupVideosOnCellular READ backupVideosOnCellular WRITE setBackupVideosOnCellular NOTIFY backupVideosOnCellularChanged)
    Q_PROPERTY(bool backupOnlyWhileCharging READ backupOnlyWhileCharging WRITE setBackupOnlyWhileCharging NOTIFY backupOnlyWhileChargingChanged)
    Q_PROPERTY(bool backupDeleteAfter READ backupDeleteAfter WRITE setBackupDeleteAfter NOTIFY backupDeleteAfterChanged)
    Q_PROPERTY(QString backupFromDate READ backupFromDate WRITE setBackupFromDate NOTIFY backupFromDateChanged)
    Q_PROPERTY(int backupScanInterval READ backupScanInterval WRITE setBackupScanInterval NOTIFY backupScanIntervalChanged)
    Q_PROPERTY(bool backupAutoDisable READ backupAutoDisable WRITE setBackupAutoDisable NOTIFY backupAutoDisableChanged)
    Q_PROPERTY(bool backupSkipVerification READ backupSkipVerification WRITE setBackupSkipVerification NOTIFY backupSkipVerificationChanged)
    Q_PROPERTY(bool coverShowAssets READ coverShowAssets WRITE setCoverShowAssets NOTIFY coverShowAssetsChanged)
    Q_PROPERTY(bool coverSlideshow READ coverSlideshow WRITE setCoverSlideshow NOTIFY coverSlideshowChanged)
    Q_PROPERTY(QString downloadFolder READ downloadFolder WRITE setDownloadFolder NOTIFY downloadFolderChanged)
    Q_PROPERTY(QStringList customBrowseFolders READ customBrowseFolders WRITE setCustomBrowseFolders NOTIFY customBrowseFoldersChanged)

public:
    explicit SettingsManager(QObject *parent = nullptr);

    QString detailQuality() const;
    void setDetailQuality(const QString &quality);

    int assetsPerRow() const;
    void setAssetsPerRow(int count);

    int memoriesThumbnailSize() const;
    void setMemoriesThumbnailSize(int size);

    bool showMemoriesBar() const;
    void setShowMemoriesBar(bool show);

    QString scrollToTopPosition() const;
    void setScrollToTopPosition(const QString &position);

    bool backupEnabled() const;
    void setBackupEnabled(bool enabled);

    QStringList backupFolders() const;
    void setBackupFolders(const QStringList &folders);
    Q_INVOKABLE void addBackupFolder(const QString &folder);
    Q_INVOKABLE void removeBackupFolder(const QString &folder);

    bool backupPhotosOnCellular() const;
    void setBackupPhotosOnCellular(bool allow);

    bool backupVideosOnCellular() const;
    void setBackupVideosOnCellular(bool allow);

    bool backupOnlyWhileCharging() const;
    void setBackupOnlyWhileCharging(bool only);

    bool backupDeleteAfter() const;
    void setBackupDeleteAfter(bool deleteAfter);

    QString backupFromDate() const;
    void setBackupFromDate(const QString &date);
    Q_INVOKABLE qint64 backupFromDateMs() const;

    int backupScanInterval() const;
    void setBackupScanInterval(int minutes);

    bool backupAutoDisable() const;
    void setBackupAutoDisable(bool autoDisable);

    bool backupSkipVerification() const;
    void setBackupSkipVerification(bool skip);

    QString backupServerUrl() const;
    void setBackupServerUrl(const QString &url);

    bool coverShowAssets() const;
    void setCoverShowAssets(bool show);

    bool coverSlideshow() const;
    void setCoverSlideshow(bool enabled);

    QString downloadFolder() const;
    void setDownloadFolder(const QString &folder);

    QStringList customBrowseFolders() const;
    void setCustomBrowseFolders(const QStringList &folders);
    Q_INVOKABLE void addCustomBrowseFolder(const QString &folder);
    Q_INVOKABLE void removeCustomBrowseFolder(const QString &folder);
    Q_INVOKABLE QStringList validCustomBrowseFolders();

    Q_INVOKABLE QString homePath() const;
    Q_INVOKABLE bool folderExists(const QString &path) const;

signals:
    void detailQualityChanged();
    void assetsPerRowChanged();
    void memoriesThumbnailSizeChanged();
    void showMemoriesBarChanged();
    void scrollToTopPositionChanged();
    void backupEnabledChanged();
    void backupFoldersChanged();
    void backupPhotosOnCellularChanged();
    void backupVideosOnCellularChanged();
    void backupOnlyWhileChargingChanged();
    void backupDeleteAfterChanged();
    void backupFromDateChanged();
    void backupScanIntervalChanged();
    void backupAutoDisableChanged();
    void backupSkipVerificationChanged();
    void coverShowAssetsChanged();
    void coverSlideshowChanged();
    void downloadFolderChanged();
    void customBrowseFoldersChanged();

private:
    QSettings m_settings;
};

#endif
