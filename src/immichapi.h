#ifndef IMMICHAPI_H
#define IMMICHAPI_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonArray>
#include <QJsonObject>
#include <QHttpMultiPart>
#include <QFile>
#include <QFileInfo>
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
    Q_INVOKABLE void updateAsset(const QString &assetId, const QString &description, double latitude = 0, double longitude = 0, bool updateLocation = false);
    Q_INVOKABLE void uploadAssets(const QStringList &filePaths);
    Q_INVOKABLE void cancelUpload();
    Q_INVOKABLE void deleteAssets(const QStringList &assetIds);
    Q_INVOKABLE void downloadAsset(const QString &assetId);
    Q_INVOKABLE void addAssetsToAlbum(const QString &albumId, const QStringList &assetIds);
    Q_INVOKABLE void removeAssetsFromAlbum(const QString &albumId, const QStringList &assetIds);
    Q_INVOKABLE void createSharedLink(const QString &type, const QVariant &ids, const QString &password, const QString &expiresAt, bool allowDownload, bool allowUpload, bool showMetadata = true, const QString &description = QString(), const QString &slug = QString());
    Q_INVOKABLE void fetchUsers();
    Q_INVOKABLE void addUsersToAlbum(const QString &albumId, const QStringList &userIds, const QString &role = QStringLiteral("editor"));
    Q_INVOKABLE void updateAlbumUserRole(const QString &albumId, const QString &userId, const QString &role);
    Q_INVOKABLE void removeAlbumUser(const QString &albumId, const QString &userId);
    Q_INVOKABLE void fetchMemories();
    Q_INVOKABLE void fetchServerStatistics();
    Q_INVOKABLE void fetchServerAbout();
    Q_INVOKABLE void createAlbum(const QString &albumName, const QString &description);
    Q_INVOKABLE void updateAlbum(const QString &albumId, const QString &albumName, const QString &description, bool isActivityEnabled = true, const QString &albumThumbnailAssetId = QString());
    Q_INVOKABLE void fetchTimelineBuckets(const QString &context, const QVariantMap &params);
    Q_INVOKABLE void fetchTimelineBucket(const QString &context, const QString &timeBucket, const QVariantMap &params);
    Q_INVOKABLE QString serverUrl() const;
    Q_INVOKABLE void setVideoSource(QObject *videoItem, const QString &assetId);
    Q_INVOKABLE void checkExistingAssets(const QStringList &deviceAssetIds);
    Q_INVOKABLE void bulkUploadCheck(const QJsonArray &assets);
    Q_INVOKABLE void getStack(const QString &stackId);
    Q_INVOKABLE void createStack(const QStringList &assetIds);
    Q_INVOKABLE void deleteStack(const QString &stackId);

    // Shared upload multipart builder
    static QHttpMultiPart* buildUploadMultiPart(QFile *file, const QFileInfo &fileInfo);

signals:
    void albumsReceived(const QJsonArray &albums);
    void albumDetailsReceived(const QJsonObject &details);
    void searchResultsReceived(const QJsonArray &results);
    void peopleReceived(const QJsonArray &people);
    void searchSuggestionsReceived(const QString &type, const QJsonArray &suggestions);
    void assetInfoReceived(const QJsonObject &info);
    void assetUpdated(const QString &assetId, const QString &description, double latitude, double longitude);
    void favoritesToggled(const QStringList &assetIds, bool isFavorite);
    void assetUploaded(const QString &assetId, const QString &filePath, const QString &status);
    void uploadFileProgress(int fileIndex, int totalFiles, qint64 bytesSent, qint64 bytesTotal);
    void uploadAllComplete(int successCount, int failCount);
    void uploadFailed(const QString &filePath, const QString &error);
    void assetsDeleted(const QStringList &assetIds);
    void assetDownloaded(const QString &assetId, const QString &filePath);
    void assetsAddedToAlbum(const QString &albumId);
    void assetsRemovedFromAlbum(const QString &albumId);
    void sharedLinkCreated(const QString &shareKey, bool isSlug);
    void usersReceived(const QJsonArray &users);
    void usersAddedToAlbum(const QString &albumId);
    void albumUserRoleUpdated(const QString &albumId);
    void albumUserRemoved(const QString &albumId);
    void memoriesReceived(const QJsonArray &memories);
    void serverStatisticsReceived(const QJsonObject &stats);
    void serverAboutReceived(const QJsonObject &about);
    void albumCreated(const QString &albumId, const QString &albumName);
    void albumUpdated(const QString &albumId, const QString &albumName, const QString &description, bool isActivityEnabled, const QString &albumThumbnailAssetId);
    void timelineBucketsReceived(const QString &context, const QJsonArray &buckets);
    void timelineBucketReceived(const QString &context, const QString &timeBucket, const QJsonObject &bucketData);
    void errorOccurred(const QString &error);
    void existingAssetsChecked(const QStringList &existingIds);
    void bulkUploadCheckCompleted(const QJsonArray &results);
    void stackReceived(const QString &stackId, const QJsonArray &assets);
    void stackCreated(const QString &stackId);
    void stackDeleted(const QString &stackId);
    void authenticationRequired();

private slots:
    void onSearchByParametersReplyFinished();
    void onSearchSuggestionsReplyFinished();
    void onFavoriteReplyFinished();
    void onDeleteReplyFinished();
    void onAddToAlbumReplyFinished();
    void onSharedLinkReplyFinished();

private:
    QNetworkAccessManager *m_networkManager;
    AuthManager *m_authManager;
    SettingsManager *m_settingsManager;

    QNetworkRequest createAuthenticatedRequest(const QUrl &url) const;
    void handleNetworkError(QNetworkReply *reply);
    void uploadNextFile();
    void startAssetDownload(const QString &assetId, const QString &fileName);

    // Generic reply handler
    void connectReply(QNetworkReply *reply, std::function<void(const QByteArray&)> onSuccess, int timeoutMs = 30000);

    // Upload queue state
    QStringList m_uploadQueue;
    int m_uploadIndex;
    int m_uploadSuccessCount;
    int m_uploadFailCount;
    bool m_uploadCancelled;
    QNetworkReply *m_currentUploadReply;
};

#endif
