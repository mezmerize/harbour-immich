#ifndef SETTINGSMANAGER_H
#define SETTINGSMANAGER_H

#include <QObject>
#include <QSettings>

class SettingsManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString detailQuality READ detailQuality WRITE setDetailQuality NOTIFY detailQualityChanged)
    Q_PROPERTY(int assetsPerRow READ assetsPerRow WRITE setAssetsPerRow NOTIFY assetsPerRowChanged)
    Q_PROPERTY(int memoriesThumbnailSize READ memoriesThumbnailSize WRITE setMemoriesThumbnailSize NOTIFY memoriesThumbnailSizeChanged)
    Q_PROPERTY(bool showMemoriesBar READ showMemoriesBar WRITE setShowMemoriesBar NOTIFY showMemoriesBarChanged)
    Q_PROPERTY(QString scrollToTopPosition READ scrollToTopPosition WRITE setScrollToTopPosition NOTIFY scrollToTopPositionChanged)

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

signals:
    void detailQualityChanged();
    void assetsPerRowChanged();
    void memoriesThumbnailSizeChanged();
    void showMemoriesBarChanged();
    void scrollToTopPositionChanged();

private:
    QSettings m_settings;
};

#endif
