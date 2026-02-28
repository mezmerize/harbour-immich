#ifndef IMMICHAPI_H
#define IMMICHAPI_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonArray>
#include <QJsonObject>
#include <QHttpMultiPart>
#include <functional>
#include "authmanager.h"

class SettingsManager;

class ImmichApi : public QObject
{
    Q_OBJECT

public:
    explicit ImmichApi(AuthManager *authManager, QObject *parent = nullptr);
    void setSettingsManager(SettingsManager *settingsManager);

    Q_INVOKABLE void fetchAlbums(const QString &shared = QString());
    Q_INVOKABLE void fetchAlbumDetails(const QString &albumId);
    Q_INVOKABLE void searchByParameters(const QVariantMap &searchParams);
    Q_INVOKABLE void smartSearch(const QString &assetId);
    Q_INVOKABLE void fetchPeople();
    Q_INVOKABLE void fetchSearchSuggestions(const QString &type);
    Q_INVOKABLE void toggleFavorite(const QStringList &assetIds, bool isFavorite);
    Q_INVOKABLE void getAssetInfo(const QString &assetId);
    Q_INVOKABLE void updateAssetDescription(const QString &assetId, const QString &description);
    Q_INVOKABLE void uploadAsset(const QString &filePath);
    Q_INVOKABLE void deleteAssets(const QStringList &assetIds);
    Q_INVOKABLE void downloadAsset(const QString &assetId, const QString &fileName);
    Q_INVOKABLE void addAssetsToAlbum(const QString &albumId, const QStringList &assetIds);
    Q_INVOKABLE void createSharedLink(const QString &type, const QVariant &ids, const QString &password, const QString &expiresAt, bool allowDownload, bool allowUpload);
    Q_INVOKABLE void fetchMemories();
    Q_INVOKABLE void fetchServerStatistics();
    Q_INVOKABLE void fetchServerAbout();
    Q_INVOKABLE void createAlbum(const QString &albumName, const QString &description);
    Q_INVOKABLE void updateAlbum(const QString &albumId, const QString &albumName, const QString &description);
    Q_INVOKABLE void fetchTimelineBuckets(bool isFavorite = false, const QString &order = QStringLiteral("desc"));
    Q_INVOKABLE void fetchTimelineBucket(const QString &timeBucket, bool isFavorite = false);
    Q_INVOKABLE QString serverUrl() const;

signals:
    void albumsReceived(const QJsonArray &albums);
    void albumDetailsReceived(const QJsonObject &details);
    void searchResultsReceived(const QJsonArray &results);
    void peopleReceived(const QJsonArray &people);
    void searchSuggestionsReceived(const QString &type, const QJsonArray &suggestions);
    void assetInfoReceived(const QJsonObject &info);
    void assetDescriptionUpdated(const QString &assetId, const QString &description);
    void favoritesToggled(const QStringList &assetIds, bool isFavorite);
    void assetUploaded(const QString &assetId);
    void uploadProgress(int current, int total);
    void uploadFailed(const QString &error);
    void assetsDeleted(const QStringList &assetIds);
    void assetDownloaded(const QString &assetId, const QString &filePath);
    void assetsAddedToAlbum(const QString &albumId);
    void sharedLinkCreated(const QString &shareKey);
    void memoriesReceived(const QJsonArray &memories);
    void serverStatisticsReceived(const QJsonObject &stats);
    void serverAboutReceived(const QJsonObject &about);
    void albumCreated(const QString &albumId, const QString &albumName);
    void albumUpdated(const QString &albumId, const QString &albumName, const QString &description);
    void timelineBucketsReceived(const QJsonArray &buckets);
    void timelineBucketReceived(const QString &timeBucket, const QJsonObject &bucketData);
    void errorOccurred(const QString &error);
    void authenticationRequired();

private slots:
    void onSearchByParametersReplyFinished();
    void onSearchSuggestionsReplyFinished();
    void onFavoriteReplyFinished();
    void onUploadReplyFinished();
    void onUploadProgress(qint64 bytesSent, qint64 bytesTotal);
    void onDeleteReplyFinished();
    void onDownloadReplyFinished();
    void onAddToAlbumReplyFinished();
    void onSharedLinkReplyFinished();

private:
    QNetworkAccessManager *m_networkManager;
    AuthManager *m_authManager;
    SettingsManager *m_settingsManager;

    QNetworkRequest createAuthenticatedRequest(const QUrl &url) const;
    void handleNetworkError(QNetworkReply *reply);

    // Generic reply handler
    void connectReply(QNetworkReply *reply, std::function<void(const QByteArray&)> onSuccess);
};

#endif
