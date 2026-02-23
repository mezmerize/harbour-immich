#include "settingsmanager.h"

SettingsManager::SettingsManager(QObject *parent)
    : QObject(parent)
{
}

QString SettingsManager::thumbnailQuality() const
{
    return m_settings.value("thumbnailQuality", "thumbnail").toString();
}

void SettingsManager::setThumbnailQuality(const QString &quality)
{
    if (thumbnailQuality() != quality) {
        m_settings.setValue("thumbnailQuality", quality);
        emit thumbnailQualityChanged();
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
    return m_settings.value("memoriesThumbnailSize", 0).toInt();
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
