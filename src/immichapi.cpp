#include "immichapi.h"
#include "authmanager.h"
#include "settingsmanager.h"
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <QBuffer>
#include <QUrlQuery>
#include <QFile>
#include <QFileInfo>
#include <QHttpMultiPart>
#include <QHttpPart>
#include <QMimeDatabase>
#include <QUrl>
#include <QStandardPaths>
#include <QDateTime>

ImmichApi::ImmichApi(AuthManager *authManager, QObject *parent)
   : QObject(parent)
   , m_networkManager(new QNetworkAccessManager(this))
   , m_authManager(authManager)
   , m_settingsManager(nullptr)
{
}

void ImmichApi::setSettingsManager(SettingsManager *settingsManager)
{
   m_settingsManager = settingsManager;
}

QNetworkRequest ImmichApi::createAuthenticatedRequest(const QUrl &url) const
{
   QNetworkRequest request(url);
   request.setRawHeader("Authorization", QString("Bearer %1").arg(m_authManager->getAccessToken()).toUtf8());
   request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
   return request;
}

void ImmichApi::fetchAlbums(const QString &shared)
{
   QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums"));
   if (!shared.isEmpty()) {
       QUrlQuery query;
       query.addQueryItem(QStringLiteral("shared"), shared);
       url.setQuery(query);
   }
   QNetworkRequest request = createAuthenticatedRequest(url);
   QNetworkReply *reply = m_networkManager->get(request);
   connectReply(reply, [this](const QByteArray &response) {
       QJsonDocument doc = QJsonDocument::fromJson(response);
       emit albumsReceived(doc.array());
   });
}

void ImmichApi::fetchAlbumDetails(const QString &albumId)
{
   QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums/") + albumId);
   QNetworkRequest request = createAuthenticatedRequest(url);
   QNetworkReply *reply = m_networkManager->get(request);
   connectReply(reply, [this](const QByteArray &response) {
       QJsonDocument doc = QJsonDocument::fromJson(response);
       emit albumDetailsReceived(doc.object());
   });
}

void ImmichApi::searchByParameters(const QVariantMap &searchParams)
{
   QUrl url(m_authManager->serverUrl() + "/api/search/metadata");
   QNetworkRequest request = createAuthenticatedRequest(url);

   QJsonObject json;

   // Context search
   if (searchParams.contains("query") && !searchParams["query"].toString().isEmpty()) {
       json["q"] = searchParams["query"].toString();
   }

   // Filename search
   if (searchParams.contains("originalFileName") && !searchParams["originalFileName"].toString().isEmpty()) {
       json["originalFileName"] = searchParams["originalFileName"].toString();
   }

   // Description search
   if (searchParams.contains("description") && !searchParams["description"].toString().isEmpty()) {
       json["description"] = searchParams["description"].toString();
   }

   // People
   if (searchParams.contains("personIds")) {
       QJsonArray peopleArray;
       QStringList peopleIds = searchParams["personIds"].toStringList();
       for (const QString &id : peopleIds) {
           peopleArray.append(id);
       }
       json["personIds"] = peopleArray;
   }

   // Place
   if (searchParams.contains("state") && !searchParams["state"].toString().isEmpty()) {
       json["state"] = searchParams["state"].toString();
   }
   if (searchParams.contains("country") && !searchParams["country"].toString().isEmpty()) {
       json["country"] = searchParams["country"].toString();
   }
   if (searchParams.contains("city") && !searchParams["city"].toString().isEmpty()) {
       json["city"] = searchParams["city"].toString();
   }

   // Camera
   if (searchParams.contains("make") && !searchParams["make"].toString().isEmpty()) {
       json["make"] = searchParams["make"].toString();
   }
   if (searchParams.contains("model") && !searchParams["model"].toString().isEmpty()) {
       json["model"] = searchParams["model"].toString();
   }
   if (searchParams.contains("lensModel") && !searchParams["lensModel"].toString().isEmpty()) {
       json["lensModel"] = searchParams["lensModel"].toString();
   }

   // Date range
   if (searchParams.contains("takenAfter") && !searchParams["takenAfter"].toString().isEmpty()) {
       json["takenAfter"] = searchParams["takenAfter"].toString();
   }
   if (searchParams.contains("takenBefore") && !searchParams["takenBefore"].toString().isEmpty()) {
       json["takenBefore"] = searchParams["takenBefore"].toString();
   }

   // Media type
   if (searchParams.contains("type") && searchParams["type"].toString() != "all") {
       json["type"] = searchParams["type"].toString().toUpper();
   }

   // Display options
   if (searchParams.contains("withArchived")) {
       json["withArchived"] = searchParams["withArchived"].toBool();
   }
   if (searchParams.contains("isNotInAlbum")) {
       json["isNotInAlbum"] = searchParams["isNotInAlbum"].toBool();
   }
   if (searchParams.contains("isFavorite")) {
       json["isFavorite"] = searchParams["isFavorite"].toBool();
   }

   // Sort order
   if (searchParams.contains("order")) {
       json["order"] = searchParams["order"].toString();
   } else {
       json["order"] = "desc"; // Default to descending
   }

   // Pagination
   if (searchParams.contains("page")) {
       json["page"] = searchParams["page"].toInt();
   }
   if (searchParams.contains("size")) {
       json["size"] = searchParams["size"].toInt();
   } else {
       json["size"] = 100; // Default size
   }

   QJsonDocument doc(json);
   QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
   connect(reply, &QNetworkReply::finished, this, &ImmichApi::onSearchByParametersReplyFinished);
}

void ImmichApi::onSearchByParametersReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   if (reply->error() == QNetworkReply::NoError) {
       QByteArray response = reply->readAll();
       QJsonDocument doc = QJsonDocument::fromJson(response);
       QJsonObject obj = doc.object();

       QJsonArray results;
       if (obj.contains("assets")) {
           QJsonObject assetsObj = obj["assets"].toObject();
           if (assetsObj.contains("items")) {
               results = assetsObj["items"].toArray();
           }
       }
       emit searchResultsReceived(results);
   } else {
       handleNetworkError(reply);
   }

   reply->deleteLater();
}

void ImmichApi::smartSearch(const QString &assetId)
{
    QUrl url(m_authManager->serverUrl() + "/api/search/smart");
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["queryAssetId"] = assetId;
    json["size"] = 100;

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    connect(reply, &QNetworkReply::finished, this, &ImmichApi::onSearchByParametersReplyFinished);
}

void ImmichApi::fetchPeople()
{
   QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/people"));
   QNetworkRequest request = createAuthenticatedRequest(url);
   QNetworkReply *reply = m_networkManager->get(request);
   connectReply(reply, [this](const QByteArray &response) {
       QJsonDocument doc = QJsonDocument::fromJson(response);
       QJsonObject obj = doc.object();

       QJsonArray people;
       if (obj.contains(QStringLiteral("people"))) {
           people = obj[QStringLiteral("people")].toArray();
       } else if (doc.isArray()) {
           people = doc.array();
       }
       emit peopleReceived(people);
   });
}

void ImmichApi::fetchSearchSuggestions(const QString &type)
{
   QUrl url(m_authManager->serverUrl() + "/api/search/suggestions");
   QUrlQuery query;
   query.addQueryItem("type", type);
   if (type == "state" || type == "country" || type == "camera-make" || type == "camera-model" || type == "camera-lens-model") {
       query.addQueryItem("includeNull", "true");
   }
   url.setQuery(query);

   QNetworkRequest request = createAuthenticatedRequest(url);
   QNetworkReply *reply = m_networkManager->get(request);
   reply->setProperty("suggestionType", type);
   connect(reply, &QNetworkReply::finished, this, &ImmichApi::onSearchSuggestionsReplyFinished);
}

void ImmichApi::onSearchSuggestionsReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   if (reply->error() == QNetworkReply::NoError) {
       QByteArray response = reply->readAll();
       QJsonDocument doc = QJsonDocument::fromJson(response);
       QJsonArray suggestions = doc.array();
       QString type = reply->property("suggestionType").toString();
       emit searchSuggestionsReceived(type, suggestions);
   } else {
       handleNetworkError(reply);
   }

   reply->deleteLater();
}

void ImmichApi::toggleFavorite(const QStringList &assetIds, bool isFavorite)
{
   QUrl url(m_authManager->serverUrl() + "/api/assets");
   QNetworkRequest request = createAuthenticatedRequest(url);

   QJsonObject json;
   QJsonArray idsArray;
   for (const QString &id : assetIds) {
       idsArray.append(id);
   }
   json["ids"] = idsArray;
   json["isFavorite"] = isFavorite;
   QJsonDocument doc(json);

   QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
   reply->setProperty("assetIds", assetIds);
   reply->setProperty("isFavorite", isFavorite);
   connect(reply, &QNetworkReply::finished, this, &ImmichApi::onFavoriteReplyFinished);
}

void ImmichApi::onFavoriteReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   if (reply->error() == QNetworkReply::NoError) {
       QStringList assetIds = reply->property("assetIds").toStringList();
       bool isFavorite = reply->property("isFavorite").toBool();
       emit favoritesToggled(assetIds, isFavorite);
   } else {
       handleNetworkError(reply);
   }

   reply->deleteLater();
}

void ImmichApi::getAssetInfo(const QString &assetId)
{
   QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets/") + assetId);
   QNetworkRequest request = createAuthenticatedRequest(url);
   QNetworkReply *reply = m_networkManager->get(request);
   connectReply(reply, [this](const QByteArray &response) {
       QJsonDocument doc = QJsonDocument::fromJson(response);
       emit assetInfoReceived(doc.object());
   });
}

void ImmichApi::updateAssetDescription(const QString &assetId, const QString &description)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets/") + assetId);
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["description"] = description;

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
    QString savedId = assetId;
    QString savedDesc = description;
    connectReply(reply, [this, savedId, savedDesc](const QByteArray &) {
        emit assetDescriptionUpdated(savedId, savedDesc);
    });
}

QString ImmichApi::serverUrl() const
{
   return m_authManager->serverUrl();
}

void ImmichApi::createSharedLink(const QString &type, const QVariant &ids, const QString &password, const QString &expiresAt, bool allowDownload, bool allowUpload)
{
   QUrl url(m_authManager->serverUrl() + "/api/shared-links");
   QNetworkRequest request = createAuthenticatedRequest(url);

   QJsonObject json;
   json["type"] = type;
   json["allowDownload"] = allowDownload;
   json["allowUpload"] = allowUpload;

   if (type == "ALBUM") {
       // For album sharing, ids is a single albumId string
       QString albumId = ids.toString();
       if (!albumId.isEmpty()) {
           json["albumId"] = albumId;
       }
   } else {
       // For individual asset sharing, ids is a QStringList
       QStringList assetIds = ids.toStringList();
       if (!assetIds.isEmpty()) {
           QJsonArray assetsArray;
           for (const QString &id : assetIds) {
               assetsArray.append(id);
           }
           json["assetIds"] = assetsArray;
       }
   }

   if (!password.isEmpty()) {
       json["password"] = password;
   }

   if (!expiresAt.isEmpty()) {
       json["expiresAt"] = expiresAt;
   }

   QJsonDocument doc(json);
   QByteArray data = doc.toJson();

   QNetworkReply *reply = m_networkManager->post(request, data);
   connect(reply, &QNetworkReply::finished, this, &ImmichApi::onSharedLinkReplyFinished);
}

void ImmichApi::handleNetworkError(QNetworkReply *reply)
{
   int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();

   // Check HTTP 401
   if (statusCode == 401) {
       emit authenticationRequired();
       m_authManager->reloginWithStoredCredentials();
       return;
   }
   QString errorString = reply->errorString();
   QByteArray response = reply->readAll();
   QJsonDocument doc = QJsonDocument::fromJson(response);

   if (!doc.isNull()) {
       QJsonObject obj = doc.object();
       if (obj.contains(QStringLiteral("message"))) {
           errorString = obj[QStringLiteral("message")].toString();
       }
   }

   emit errorOccurred(errorString);
}

void ImmichApi::connectReply(QNetworkReply *reply, std::function<void(const QByteArray&)> onSuccess)
{
   connect(reply, &QNetworkReply::finished, this, [this, reply, onSuccess]() {
       if (reply->error() == QNetworkReply::NoError) {
           onSuccess(reply->readAll());
       } else {
           handleNetworkError(reply);
       }
       reply->deleteLater();
   });
}

void ImmichApi::uploadAsset(const QString &filePath)
{
   QFile *file = new QFile(filePath);
   if (!file->open(QIODevice::ReadOnly)) {
       emit uploadFailed("Could not open file: " + filePath);
       delete file;
       return;
   }

   QFileInfo fileInfo(filePath);
   QMimeDatabase mimeDb;
   QString mimeType = mimeDb.mimeTypeForFile(fileInfo).name();

   QHttpMultiPart *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

   QHttpPart filePart;
   filePart.setHeader(QNetworkRequest::ContentTypeHeader, QVariant(mimeType));
   filePart.setHeader(QNetworkRequest::ContentDispositionHeader,
       QVariant("form-data; name=\"assetData\"; filename=\"" + fileInfo.fileName() + "\""));
   filePart.setBodyDevice(file);
   file->setParent(multiPart);

   multiPart->append(filePart);

   QUrl url(m_authManager->serverUrl() + "/api/assets/upload");
   QNetworkRequest request(url);
   request.setRawHeader("Authorization", QString("Bearer %1").arg(m_authManager->getAccessToken()).toUtf8());

   QNetworkReply *reply = m_networkManager->post(request, multiPart);
   multiPart->setParent(reply);

   connect(reply, &QNetworkReply::finished, this, &ImmichApi::onUploadReplyFinished);
   connect(reply, &QNetworkReply::uploadProgress, this, &ImmichApi::onUploadProgress);
}

void ImmichApi::onUploadReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;


   if (reply->error() == QNetworkReply::NoError) {
       QByteArray response = reply->readAll();
       QJsonDocument doc = QJsonDocument::fromJson(response);
       QJsonObject obj = doc.object();
       QString assetId = obj["id"].toString();
       emit assetUploaded(assetId);
   } else {
       QString errorMsg = reply->errorString();
       emit uploadFailed(errorMsg);
       emit errorOccurred(errorMsg);
   }

   reply->deleteLater();
}


void ImmichApi::onUploadProgress(qint64 bytesSent, qint64 bytesTotal)
{
   if (bytesTotal > 0) {
       int progress = (bytesSent * 100) / bytesTotal;
       emit uploadProgress(progress, 100);
   }
}

void ImmichApi::deleteAssets(const QStringList &assetIds)
{
   QUrl url(m_authManager->serverUrl() + "/api/assets");
   QNetworkRequest request = createAuthenticatedRequest(url);


   QJsonObject json;
   QJsonArray idsArray;
   for (const QString &id : assetIds) {
       idsArray.append(id);
   }
   json["ids"] = idsArray;
   QJsonDocument doc(json);

   QByteArray data = doc.toJson();
   QBuffer *buffer = new QBuffer();
   buffer->setData(data);
   buffer->open(QIODevice::ReadOnly);


   QNetworkReply *reply = m_networkManager->sendCustomRequest(request, "DELETE", buffer);
   buffer->setParent(reply);
   reply->setProperty("assetIds", assetIds);
   connect(reply, &QNetworkReply::finished, this, &ImmichApi::onDeleteReplyFinished);
}

void ImmichApi::onDeleteReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   if (reply->error() == QNetworkReply::NoError) {
       QStringList assetIds = reply->property("assetIds").toStringList();
       emit assetsDeleted(assetIds);
   } else {
       handleNetworkError(reply);
   }

   reply->deleteLater();
}

void ImmichApi::downloadAsset(const QString &assetId, const QString &fileName)
{
   QUrl url(m_authManager->serverUrl() + "/api/assets/" + assetId + "/original");
   QNetworkRequest request = createAuthenticatedRequest(url);

   QNetworkReply *reply = m_networkManager->get(request);
   reply->setProperty("assetId", assetId);
   reply->setProperty("fileName", fileName);
   connect(reply, &QNetworkReply::finished, this, &ImmichApi::onDownloadReplyFinished);
}

void ImmichApi::onDownloadReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   if (reply->error() == QNetworkReply::NoError) {
       QString assetId = reply->property("assetId").toString();
       QString fileName = reply->property("fileName").toString();

       QString downloadPath = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
       QString filePath = downloadPath + "/" + fileName;

       QFile file(filePath);
       if (file.open(QIODevice::WriteOnly)) {
           file.write(reply->readAll());
           file.close();
           emit assetDownloaded(assetId, filePath);
       } else {
           emit errorOccurred("Failed to save file: " + filePath);
       }
   } else {
       handleNetworkError(reply);
   }

   reply->deleteLater();
}

void ImmichApi::addAssetsToAlbum(const QString &albumId, const QStringList &assetIds)
{
   QUrl url(m_authManager->serverUrl() + "/api/albums/" + albumId + "/assets");
   QNetworkRequest request = createAuthenticatedRequest(url);

   QJsonObject json;
   QJsonArray idsArray;
   for (const QString &id : assetIds) {
       idsArray.append(id);
   }
   json["ids"] = idsArray;
   QJsonDocument doc(json);

   QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
   reply->setProperty("albumId", albumId);
   connect(reply, &QNetworkReply::finished, this, &ImmichApi::onAddToAlbumReplyFinished);
}

void ImmichApi::onAddToAlbumReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   if (reply->error() == QNetworkReply::NoError) {
       QString albumId = reply->property("albumId").toString();
       emit assetsAddedToAlbum(albumId);
   } else {
       handleNetworkError(reply);
   }

   reply->deleteLater();
}

void ImmichApi::onSharedLinkReplyFinished()
{
   QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
   if (!reply) return;

   if (reply->error() == QNetworkReply::NoError) {
       QByteArray response = reply->readAll();
       QJsonDocument doc = QJsonDocument::fromJson(response);
       QJsonObject obj = doc.object();

       QString shareKey = obj["key"].toString();
       emit sharedLinkCreated(shareKey);
   } else {
       handleNetworkError(reply);
   }

   reply->deleteLater();
}

void ImmichApi::fetchMemories()
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/memories"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("for"), QDateTime::currentDateTime().toString(Qt::ISODate));
    url.setQuery(query);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
       QJsonDocument doc = QJsonDocument::fromJson(response);
       emit memoriesReceived(doc.array());
    });
}

void ImmichApi::fetchServerStatistics()
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/server/statistics"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
       QJsonDocument doc = QJsonDocument::fromJson(response);
       emit serverStatisticsReceived(doc.object());
    });
}

void ImmichApi::fetchServerAbout()
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/server/about"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
       QJsonDocument doc = QJsonDocument::fromJson(response);
       emit serverAboutReceived(doc.object());
    });
}

void ImmichApi::createAlbum(const QString &albumName, const QString &description)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["albumName"] = albumName;
    if (!description.isEmpty()) {
        json["description"] = description;
    }

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    connectReply(reply, [this](const QByteArray &response) {
       QJsonDocument doc = QJsonDocument::fromJson(response);
       QJsonObject obj = doc.object();
       QString albumId = obj["id"].toString();
       QString albumName = obj["albumName"].toString();
       emit albumCreated(albumId, albumName);
    });
}

void ImmichApi::updateAlbum(const QString &albumId, const QString &albumName, const QString &description)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums/") + albumId);
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["albumName"] = albumName;
    json["description"] = description;

    QJsonDocument doc(json);
    QByteArray data = doc.toJson();
    QBuffer *buffer = new QBuffer();
    buffer->setData(data);
    buffer->open(QIODevice::ReadOnly);

    QNetworkReply *reply = m_networkManager->sendCustomRequest(request, "PATCH", buffer);
    buffer->setParent(reply);
    QString savedAlbumId = albumId;
    QString savedAlbumName = albumName;
    QString savedDescription = description;
    connectReply(reply, [this, savedAlbumId, savedAlbumName, savedDescription](const QByteArray &) {
        emit albumUpdated(savedAlbumId, savedAlbumName, savedDescription);
    });
}

void ImmichApi::fetchTimelineBuckets(bool isFavorite, const QString &order)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/timeline/buckets"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("visibility"), QStringLiteral("timeline"));
    query.addQueryItem(QStringLiteral("withStacked"), QStringLiteral("true"));
    query.addQueryItem(QStringLiteral("order"), order);
    if (isFavorite) {
        query.addQueryItem(QStringLiteral("isFavorite"), QStringLiteral("true"));
    } else {
        query.addQueryItem(QStringLiteral("withPartners"), QStringLiteral("true"));
    }
    url.setQuery(query);

    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
       QJsonDocument doc = QJsonDocument::fromJson(response);
       emit timelineBucketsReceived(doc.array());
    });
}

void ImmichApi::fetchTimelineBucket(const QString &timeBucket, bool isFavorite)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/timeline/bucket"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("timeBucket"), timeBucket);
    query.addQueryItem(QStringLiteral("visibility"), QStringLiteral("timeline"));
    query.addQueryItem(QStringLiteral("withStacked"), QStringLiteral("true"));
    if (isFavorite) {
        query.addQueryItem(QStringLiteral("isFavorite"), QStringLiteral("true"));
    } else {
        query.addQueryItem(QStringLiteral("withPartners"), QStringLiteral("true"));
    }
    url.setQuery(query);

    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    QString originalTimeBucket = timeBucket;
    connectReply(reply, [this, originalTimeBucket](const QByteArray &response) {
       QJsonDocument doc = QJsonDocument::fromJson(response);
       emit timelineBucketReceived(originalTimeBucket, doc.object());
    });
}
