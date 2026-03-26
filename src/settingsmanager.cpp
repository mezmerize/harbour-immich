#include "settingsmanager.h"
#include <QCoreApplication>
#include <QStandardPaths>
#include <QDir>
#include <QDateTime>

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
    , m_settings(QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation) + "/" + QCoreApplication::applicationName() + ".conf", QSettings::IniFormat)
{
}

QString SettingsManager::detailQuality() const
{
    return m_settings.value("detailQuality", "preview").toString();
}

void SettingsManager::setDetailQuality(const QString &quality)
{
    if (detailQuality() != quality) {
        m_settings.setValue("detailQuality", quality);
        emit detailQualityChanged();
    }
}

int SettingsManager::assetsPerRow() const
{
    return m_settings.value("assetsPerRow", 4).toInt();
}

void SettingsManager::setAssetsPerRow(int count)
{
    if (assetsPerRow() != count) {
        m_settings.setValue("assetsPerRow", count);
        emit assetsPerRowChanged();
    }
}

int SettingsManager::memoriesThumbnailSize() const
{
    return m_settings.value("memoriesThumbnailSize", 1).toInt();
}

void SettingsManager::setMemoriesThumbnailSize(int size)
{
    if (memoriesThumbnailSize() != size) {
        m_settings.setValue("memoriesThumbnailSize", size);
        emit memoriesThumbnailSizeChanged();
    }
}

bool SettingsManager::showMemoriesBar() const
{
    return m_settings.value("showMemoriesBar", true).toBool();
}

void SettingsManager::setShowMemoriesBar(bool show)
{
    if (showMemoriesBar() != show) {
        m_settings.setValue("showMemoriesBar", show);
        emit showMemoriesBarChanged();
    }
}

QString SettingsManager::scrollToTopPosition() const
{
    return m_settings.value("scrollToTopPosition", "right").toString();
}

void SettingsManager::setScrollToTopPosition(const QString &position)
{
    if (scrollToTopPosition() != position) {
        m_settings.setValue("scrollToTopPosition", position);
        emit scrollToTopPositionChanged();
    }
}

bool SettingsManager::backupEnabled() const
{
   return m_settings.value("backup/enabled", false).toBool();
}

void SettingsManager::setBackupEnabled(bool enabled)
{
   if (backupEnabled() != enabled) {
       m_settings.setValue("backup/enabled", enabled);
       emit backupEnabledChanged();
   }
}

QStringList SettingsManager::backupFolders() const
{
   return m_settings.value("backup/folders", QStringList()).toStringList();
}

void SettingsManager::setBackupFolders(const QStringList &folders)
{
    if (backupFolders() != folders) {
        m_settings.setValue("backup/folders", folders);
        emit backupFoldersChanged();
    }
}

void SettingsManager::addBackupFolder(const QString &folder)
{
   QStringList folders = backupFolders();
   if (!folders.contains(folder)) {
       folders.append(folder);
       setBackupFolders(folders);
   }
}

void SettingsManager::removeBackupFolder(const QString &folder)
{
   QStringList folders = backupFolders();
   if (folders.removeOne(folder)) {
       setBackupFolders(folders);
   }
}

bool SettingsManager::backupPhotosOnCellular() const
{
   return m_settings.value("backup/photosOnCellular", false).toBool();
}

void SettingsManager::setBackupPhotosOnCellular(bool allow)
{
   if (backupPhotosOnCellular() != allow) {
       m_settings.setValue("backup/photosOnCellular", allow);
       emit backupPhotosOnCellularChanged();
   }
}

bool SettingsManager::backupVideosOnCellular() const
{
   return m_settings.value("backup/videosOnCellular", false).toBool();
}

void SettingsManager::setBackupVideosOnCellular(bool allow)
{
   if (backupVideosOnCellular() != allow) {
       m_settings.setValue("backup/videosOnCellular", allow);
       emit backupVideosOnCellularChanged();
   }
}

bool SettingsManager::backupOnlyWhileCharging() const
{
   return m_settings.value("backup/onlyWhileCharging", false).toBool();
}

void SettingsManager::setBackupOnlyWhileCharging(bool only)
{
   if (backupOnlyWhileCharging() != only) {
       m_settings.setValue("backup/onlyWhileCharging", only);
       emit backupOnlyWhileChargingChanged();
   }
}

bool SettingsManager::backupDeleteAfter() const
{
   return m_settings.value("backup/deleteAfter", false).toBool();
}

QString SettingsManager::homePath() const
{
   return QDir::homePath();
}

void SettingsManager::setBackupDeleteAfter(bool deleteAfter)
{
   if (backupDeleteAfter() != deleteAfter) {
       m_settings.setValue("backup/deleteAfter", deleteAfter);
       emit backupDeleteAfterChanged();
   }
}

QString SettingsManager::backupFromDate() const
{
    return m_settings.value("backup/fromDate", "").toString();
}

void SettingsManager::setBackupFromDate(const QString &date)
{
    if (backupFromDate() != date) {
        m_settings.setValue("backup/fromDate", date);
        emit backupFromDateChanged();
    }
}

int SettingsManager::backupScanInterval() const
{
    return m_settings.value("backup/scanInterval", 60).toInt();
}

void SettingsManager::setBackupScanInterval(int minutes)
{
    if (backupScanInterval() != minutes) {
        m_settings.setValue("backup/scanInterval", minutes);
        emit backupScanIntervalChanged();
    }
}

bool SettingsManager::backupAutoDisable() const
{
    return m_settings.value("backup/autoDisable", false).toBool();
}

void SettingsManager::setBackupAutoDisable(bool autoDisable)
{
    if (backupAutoDisable() != autoDisable) {
        m_settings.setValue("backup/autoDisable", autoDisable);
        emit backupAutoDisableChanged();
    }
}

bool SettingsManager::backupSkipVerification() const
{
    return m_settings.value("backup/skipVerification", false).toBool();
}

void SettingsManager::setBackupSkipVerification(bool skip)
{
    if (backupSkipVerification() != skip) {
        m_settings.setValue("backup/skipVerification", skip);
        emit backupSkipVerificationChanged();
    }
}

QString SettingsManager::backupServerUrl() const
{
    return m_settings.value("backup/serverUrl", "").toString();
}

void SettingsManager::setBackupServerUrl(const QString &url)
{
    if (backupServerUrl() != url) {
        m_settings.setValue("backup/serverUrl", url);
    }
}

qint64 SettingsManager::backupFromDateMs() const
{
    QString dateStr = backupFromDate();
    if (dateStr.isEmpty()) return 0;
    QDateTime dt = QDateTime::fromString(dateStr, Qt::ISODate);
    if (!dt.isValid()) return 0;
    return dt.toMSecsSinceEpoch();
}

bool SettingsManager::coverShowAssets() const
{
    return m_settings.value("cover/showAssets", false).toBool();
}

void SettingsManager::setCoverShowAssets(bool show)
{
    if (coverShowAssets() != show) {
        m_settings.setValue("cover/showAssets", show);
        emit coverShowAssetsChanged();
    }
}

bool SettingsManager::coverSlideshow() const
{
    return m_settings.value("cover/slideshow", false).toBool();
}

void SettingsManager::setCoverSlideshow(bool enabled)
{
    if (coverSlideshow() != enabled) {
        m_settings.setValue("cover/slideshow", enabled);
        emit coverSlideshowChanged();
    }
}

QString SettingsManager::downloadFolder() const
{
    return m_settings.value("downloadFolder", QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)).toString();
}

void SettingsManager::setDownloadFolder(const QString &folder)
{
    if (downloadFolder() != folder) {
        m_settings.setValue("downloadFolder", folder);
        emit downloadFolderChanged();
    }
}
