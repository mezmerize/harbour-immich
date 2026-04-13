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
#include <QDir>
#include <QDateTime>
#include <QTimer>
#include <QMediaPlayer>
#include <QMediaContent>

namespace {
QJsonArray toJsonStringArray(const QStringList &values)
{
    QJsonArray array;
    for (const QString &value : values) {
        array.append(value);
    }
    return array;
}

QBuffer *createJsonBuffer(const QJsonObject &json) {
    QBuffer *buffer = new QBuffer();
    buffer->setData(QJsonDocument(json).toJson());
    buffer->open(QIODevice::ReadOnly);
    return buffer;
}
}

ImmichApi::ImmichApi(AuthManager *authManager, QObject *parent)
    : QObject(parent)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_authManager(authManager)
    , m_settingsManager(nullptr)
    , m_uploadIndex(0)
    , m_uploadSuccessCount(0)
    , m_uploadFailCount(0)
    , m_uploadCancelled(false)
    , m_currentUploadReply(nullptr)
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
    qInfo() << "ImmichApi: Fetching albums, shared:" << shared;
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
        qInfo() << "ImmichApi: Albums received, count:" << doc.array().size();
        emit albumsReceived(doc.array());
    });
}

void ImmichApi::fetchAlbumDetails(const QString &albumId)
{
    qInfo() << "ImmichApi: Fetching album details for:" << albumId;
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
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/search/metadata"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;

    // Helper: copy non-empty string param (with optional JSON key rename)
    auto copyString = [&](const QString &key, const QString &jsonKey = QString()) {
        if (searchParams.contains(key) && !searchParams[key].toString().isEmpty()) {
            json[jsonKey.isEmpty() ? key : jsonKey] = searchParams[key].toString();
        }
    };

    // Helper: copy bool param
    auto copyBool = [&](const QString &key) {
        if (searchParams.contains(key))
            json[key] = searchParams[key].toBool();
    };

    // Text search
    copyString("query", "q");
    copyString("originalFileName");
    copyString("description");

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
    copyString("state");
    copyString("country");
    copyString("city");

    // Camera
    copyString("make");
    copyString("model");
    copyString("lensModel");

    // Date range
    copyString("takenAfter");
    copyString("takenBefore");

    // Media type
    if (searchParams.contains("type") && searchParams["type"].toString() != "all") {
        json["type"] = searchParams["type"].toString().toUpper();
    }

    // Display options
    copyBool("withArchived");
    copyBool("isNotInAlbum");
    copyBool("isFavorite");

    // Sort order
    json["order"] = searchParams.contains("order") ? searchParams["order"].toString() : QStringLiteral("desc");

    // Pagination
    if (searchParams.contains("page")) {
        json["page"] = searchParams["page"].toInt();
    }
    json["size"] = searchParams.contains("size") ? searchParams["size"].toInt() : 100;

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
    qInfo() << "ImmichApi: Smart search for:" << assetId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/search/smart"));
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
    qInfo() << "ImmichApi: Fetching people";
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
        qInfo() << "ImmichApi: People received, count:" << people.size();
        emit peopleReceived(people);
    });
}

void ImmichApi::fetchSearchSuggestions(const QString &type)
{
    qInfo() << "ImmichApi: Fetching search suggestions for" << type;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/search/suggestions"));
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
    qInfo() << "ImmichApi: Updating assets, size:" << assetIds.size() << "isFavorite:" << isFavorite;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["ids"] = toJsonStringArray(assetIds);
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
    qInfo() << "ImmichApi: Getting asset info for:" << assetId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets/") + assetId);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        emit assetInfoReceived(doc.object());
    });
}

void ImmichApi::updateAsset(const QString &assetId, const QString &description, double latitude, double longitude, bool updateLocation)
{
    qInfo() << "ImmichApi: Updating asset:" << assetId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets/") + assetId);
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["description"] = description;
    if (updateLocation) {
        json["latitude"] = latitude;
        json["longitude"] = longitude;
    }

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
    QString savedId = assetId;
    QString savedDesc = description;
    double savedLat = latitude;
    double savedLng = longitude;
    connectReply(reply, [this, savedId, savedDesc, savedLat, savedLng](const QByteArray &) {
        emit assetUpdated(savedId, savedDesc, savedLat, savedLng);
    });
}

QString ImmichApi::serverUrl() const
{
    return m_authManager->serverUrl();
}

void ImmichApi::createSharedLink(const QString &type, const QVariant &ids, const QString &password, const QString &expiresAt, bool allowDownload, bool allowUpload, bool showMetadata, const QString &description, const QString &slug)
{
    qInfo() << "ImmichApi: Creating shared link";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/shared-links"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["type"] = type;
    json["allowDownload"] = showMetadata ? allowDownload : false;
    json["allowUpload"] = allowUpload;
    json["showMetadata"] = showMetadata;

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
            json["assetIds"] = toJsonStringArray(assetIds);
        }
    }

    if (!password.isEmpty()) {
        json["password"] = password;
    }

    if (!expiresAt.isEmpty()) {
        json["expiresAt"] = expiresAt;
    }

    if (!description.isEmpty()) {
        json["description"] = description;
    }

    if (!slug.isEmpty()) {
        json["slug"] = slug;
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

    qWarning() << "ImmichApi: Network error:" << errorString;
    emit errorOccurred(errorString);
}

void ImmichApi::connectReply(QNetworkReply *reply, std::function<void(const QByteArray&)> onSuccess, int timeoutMs)
{
    QTimer *timer = new QTimer(reply);
    timer->setSingleShot(true);
    timer->setInterval(timeoutMs);
    connect(timer, &QTimer::timeout, reply, &QNetworkReply::abort);
    connect(reply, &QNetworkReply::finished, timer, &QTimer::stop);
    timer->start();

    connect(reply, &QNetworkReply::finished, this, [this, reply, onSuccess]() {
        if (reply->error() == QNetworkReply::NoError) {
            onSuccess(reply->readAll());
        } else {
            handleNetworkError(reply);
        }
        reply->deleteLater();
    });
}

void ImmichApi::uploadAssets(const QStringList &filePaths)
{
    if (filePaths.isEmpty()) return;

    qInfo() << "ImmichApi: Starting upload of" << filePaths.size() << "files";
    m_uploadQueue = filePaths;
    m_uploadIndex = 0;
    m_uploadSuccessCount = 0;
    m_uploadFailCount = 0;
    m_uploadCancelled = false;
    m_currentUploadReply = nullptr;

    uploadNextFile();
}

void ImmichApi::cancelUpload()
{
    qInfo() << "ImmichApi: Upload cancelled";
    m_uploadCancelled = true;
    if (m_currentUploadReply && !m_currentUploadReply->isFinished()) {
        m_currentUploadReply->abort();
    }
}

QHttpMultiPart* ImmichApi::buildUploadMultiPart(QFile *file, const QFileInfo &fileInfo)
{
    QMimeDatabase mimeDb;
    QString mimeType = mimeDb.mimeTypeForFile(fileInfo).name();
    QString isoDate = fileInfo.lastModified().toUTC().toString(Qt::ISODate);
    QString deviceAssetId = QString("%1-%2").arg(fileInfo.fileName()).arg(fileInfo.lastModified().toMSecsSinceEpoch());

    QHttpMultiPart *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

    auto addFormField = [&](const char *name, const QByteArray &value) {
        QHttpPart part;
        part.setHeader(QNetworkRequest::ContentDispositionHeader, QVariant(QStringLiteral("form-data; name=\"%1\"").arg(name)));
        part.setBody(value);
        multiPart->append(part);
    };

    // assetData
    QHttpPart filePart;
    filePart.setHeader(QNetworkRequest::ContentTypeHeader, QVariant(mimeType));
    filePart.setHeader(QNetworkRequest::ContentDispositionHeader, QVariant("form-data; name=\"assetData\"; filename=\"" + fileInfo.fileName() + "\""));
    filePart.setBodyDevice(file);
    file->setParent(multiPart);
    multiPart->append(filePart);

    addFormField("deviceAssetId", deviceAssetId.toUtf8());
    addFormField("deviceId", "harbour-immich");
    addFormField("fileCreatedAt", isoDate.toUtf8());
    addFormField("fileModifiedAt", isoDate.toUtf8());
    addFormField("isFavorite", "false");

    return multiPart;
}

void ImmichApi::uploadNextFile()
{
    if (m_uploadCancelled || m_uploadIndex >= m_uploadQueue.size()) {
        qInfo() << "ImmichApi: Upload batch complete -" << m_uploadSuccessCount << "succeeded," << m_uploadFailCount << "failed";
        emit uploadAllComplete(m_uploadSuccessCount, m_uploadFailCount);
        m_currentUploadReply = nullptr;
        return;
    }

    QString filePath = m_uploadQueue.at(m_uploadIndex);
    QFileInfo fileInfo(filePath);

    QFile *file = new QFile(filePath);
    if (!file->open(QIODevice::ReadOnly)) {
        qWarning() << "ImmichApi: Could not open file:" << filePath;
        emit uploadFailed(filePath, "Could not open file");
        m_uploadFailCount++;
        m_uploadIndex++;
        uploadNextFile();
        delete file;
        return;
    }

    QHttpMultiPart *multiPart = buildUploadMultiPart(file, fileInfo);

    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets"));
    QNetworkRequest request(url);
    request.setRawHeader("Authorization", QString("Bearer %1").arg(m_authManager->getAccessToken()).toUtf8());

    qInfo() << "ImmichApi: Uploading file" << (m_uploadIndex + 1) << "/" << m_uploadQueue.size() << "-" << fileInfo.fileName();

    QNetworkReply *reply = m_networkManager->post(request, multiPart);
    multiPart->setParent(reply);
    m_currentUploadReply = reply;

    int currentFileIndex = m_uploadIndex;
    int totalFiles = m_uploadQueue.size();

    connect(reply, &QNetworkReply::uploadProgress, this, [this, currentFileIndex, totalFiles](qint64 bytesSent, qint64 bytesTotal) {
        emit uploadFileProgress(currentFileIndex, totalFiles, bytesSent, bytesTotal);
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply, filePath]() {
        m_currentUploadReply = nullptr;

        if (reply->error() == QNetworkReply::NoError) {
            QByteArray response = reply->readAll();
            QJsonDocument doc = QJsonDocument::fromJson(response);
            QJsonObject obj = doc.object();
            QString assetId = obj["id"].toString();
            QString status = obj["status"].toString();
            if (status == QStringLiteral("duplicate")) {
                qInfo() << "ImmichApi: Asset already exists (duplicate):" << filePath;
            } else if (status == QStringLiteral("replaced")) {
                qInfo() << "ImmichApi: Asset replaced:" << filePath;
            } else {
                qInfo() << "ImmichApi: Asset created:" << filePath;
            }
            m_uploadSuccessCount++;
            emit assetUploaded(assetId, filePath, status);
        } else if (reply->error() != QNetworkReply::OperationCanceledError) {
            QString errorMsg = reply->errorString();
            qWarning() << "ImmichApi: Upload failed for" << filePath << ":" << errorMsg;
            m_uploadFailCount++;
            emit uploadFailed(filePath, errorMsg);
        }

        reply->deleteLater();
        m_uploadIndex++;
        uploadNextFile();
    });
}

void ImmichApi::deleteAssets(const QStringList &assetIds)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["ids"] = toJsonStringArray(assetIds);

    QBuffer *buffer = createJsonBuffer(json);

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

void ImmichApi::downloadAsset(const QString &assetId)
{
    qInfo() << "ImmichApi: Downloading asset:" << assetId;

    // First fetch asset info to get the original filename
    QUrl infoUrl(m_authManager->serverUrl() + QStringLiteral("/api/assets/") + assetId);
    QNetworkRequest infoRequest = createAuthenticatedRequest(infoUrl);
    QNetworkReply *infoReply = m_networkManager->get(infoRequest);

    connectReply(infoReply, [this, assetId](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QString originalName = doc.object()["originalFileName"].toString();
        if (originalName.isEmpty()) {
            originalName = assetId;
        }
        startAssetDownload(assetId, originalName);
    });
}

void ImmichApi::startAssetDownload(const QString &assetId, const QString &fileName)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets/") + assetId + QStringLiteral("/original"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    request.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);

    QString downloadPath = m_settingsManager ? m_settingsManager->downloadFolder() : QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    QDir().mkdir(downloadPath);
    QString tempPath = downloadPath + "/.download_" + assetId;

    QFile *file = new QFile(tempPath);
    if (!file->open(QIODevice::WriteOnly)) {
        emit errorOccurred("Failed to create file: " + tempPath);
        delete file;
        return;
    }

    QNetworkReply *reply = m_networkManager->get(request);
    reply->setProperty("assetId", assetId);

    // Stream data to disk as it arrives instead of buffering in RAM
    connect(reply, &QNetworkReply::readyRead, this, [reply, file]() {
        file->write(reply->readAll());
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply, file, tempPath, downloadPath, fileName]() {
        QString assetId = reply->property("assetId").toString();

        if (reply->error() == QNetworkReply::NoError) {
            file->write(reply->readAll());
            file->close();

            QString finalPath = downloadPath + "/" + fileName;
            // Avoid overwriting existing files
            if (QFile::exists(finalPath)) {
                QFileInfo fi(fileName);
                QString base = fi.completeBaseName();
                QString ext = fi.suffix();
                int counter = 1;
                do {
                    finalPath = downloadPath + "/" + base + "_" + QString::number(counter) + (ext.isEmpty() ? "" : "." + ext);
                    counter++;
                } while (QFile::exists(finalPath));
            }

            if (!QFile::rename(tempPath, finalPath)) {
                file->remove();
                delete file;
                emit errorOccurred(QStringLiteral("Failed to finalize download: %1").arg(finalPath));
                reply->deleteLater();
                return;
            }
            delete file;
            qInfo() << "ImmichApi: Download complete:" << finalPath;
            emit assetDownloaded(assetId, finalPath);
        } else {
            file->close();
            file->remove();
            delete file;
            handleNetworkError(reply);
        }
        reply->deleteLater();
    });
}

void ImmichApi::addAssetsToAlbum(const QString &albumId, const QStringList &assetIds)
{
    qInfo() << "ImmichApi: Adding" << assetIds.size() << "assets to album:" << albumId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums/") + albumId + QStringLiteral("/assets"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["ids"] = toJsonStringArray(assetIds);
    QJsonDocument doc(json);

    QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
    reply->setProperty("albumId", albumId);
    connect(reply, &QNetworkReply::finished, this, &ImmichApi::onAddToAlbumReplyFinished);
}

void ImmichApi::removeAssetsFromAlbum(const QString &albumId, const QStringList &assetIds)
{
    qInfo() << "ImmichApi: Removing" << assetIds.size() << "assets from album:" << albumId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums/") + albumId + QStringLiteral("/assets"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["ids"] = toJsonStringArray(assetIds);

    QBuffer *buffer = createJsonBuffer(json);

    QNetworkReply *reply = m_networkManager->sendCustomRequest(request, "DELETE", buffer);
    buffer->setParent(reply);
    QString savedAlbumId = albumId;
    connectReply(reply, [this, savedAlbumId](const QByteArray &) {
        emit assetsRemovedFromAlbum(savedAlbumId);
    });
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

        QString shareKey = obj["slug"].toString();
        bool isSlug = !shareKey.isEmpty();
        if (shareKey.isEmpty()) {
            shareKey = obj["key"].toString();
        }
        emit sharedLinkCreated(QUrl::toPercentEncoding(shareKey), isSlug);
    } else {
        handleNetworkError(reply);
    }

    reply->deleteLater();
}

void ImmichApi::fetchUsers()
{
    qInfo() << "ImmichApi: Fetching users";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/users"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonArray users = doc.isArray() ? doc.array() : QJsonArray();
        qInfo() << "ImmichApi: Users received, count:" << users.size();
        emit usersReceived(users);
    });
}

void ImmichApi::addUsersToAlbum(const QString &albumId, const QStringList &userIds, const QString &role)
{
    qInfo() << "ImmichApi: Adding" << userIds.size() << "users to album:" << albumId << "role:" << role;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums/") + albumId + QStringLiteral("/users"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonArray albumUsers;
    for (const QString &userId : userIds) {
        QJsonObject userObj;
        userObj["userId"] = userId;
        userObj["role"] = role;
        albumUsers.append(userObj);
    }
    QJsonObject json;
    json["albumUsers"] = albumUsers;

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
    QString savedAlbumId = albumId;
    connectReply(reply, [this, savedAlbumId](const QByteArray &) {
        emit usersAddedToAlbum(savedAlbumId);
    });
}

void ImmichApi::updateAlbumUserRole(const QString &albumId, const QString &userId, const QString &role)
{
    qInfo() << "ImmichApi: Updating user" << userId << "role to" << role << "in album:" << albumId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums/") + albumId + QStringLiteral("/user/") + userId);
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["role"] = role;

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
    QString savedAlbumId = albumId;
    connectReply(reply, [this, savedAlbumId](const QByteArray &) {
        emit albumUserRoleUpdated(savedAlbumId);
    });
}

void ImmichApi::removeAlbumUser(const QString &albumId, const QString &userId)
{
    qInfo() << "ImmichApi: Removing user" << userId << "from album:" << albumId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums/") + albumId + QStringLiteral("/user/") + userId);
    QNetworkRequest request = createAuthenticatedRequest(url);

    QNetworkReply *reply = m_networkManager->deleteResource(request);
    QString savedAlbumId = albumId;
    connectReply(reply, [this, savedAlbumId](const QByteArray &) {
        emit albumUserRemoved(savedAlbumId);
    });
}

void ImmichApi::fetchMemories()
{
    qInfo() << "ImmichApi: Fetching memories";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/memories"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("for"), QDateTime::currentDateTime().toString(Qt::ISODate));
    url.setQuery(query);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        qInfo() << "ImmichApi: Memories received, count:" << doc.array().size();
        emit memoriesReceived(doc.array());
    });
}

void ImmichApi::fetchServerStatistics()
{
    qInfo() << "ImmichApi: Fetching server statistics";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/server/statistics"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        qInfo() << "ImmichApi: Server statistics received";
        emit serverStatisticsReceived(doc.object());
    });
}

void ImmichApi::fetchServerAbout()
{
    qInfo() << "ImmichApi: Fetching server about";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/server/about"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        qInfo() << "ImmichApi: Server about received";
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

void ImmichApi::updateAlbum(const QString &albumId, const QString &albumName, const QString &description, bool isActivityEnabled, const QString &albumThumbnailAssetId)
{
    qInfo() << "ImmichApi: Updating album information";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums/") + albumId);
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["albumName"] = albumName;
    json["description"] = description;
    json["isActivityEnabled"] = isActivityEnabled;
    if (!albumThumbnailAssetId.isEmpty()) {
        json["albumThumbnailAssetId"] = albumThumbnailAssetId;
    }

    QBuffer *buffer = createJsonBuffer(json);

    QNetworkReply *reply = m_networkManager->sendCustomRequest(request, "PATCH", buffer);
    buffer->setParent(reply);
    QString savedAlbumId = albumId;
    QString savedAlbumName = albumName;
    QString savedDescription = description;
    bool savedIsActivityEnabled = isActivityEnabled;
    QString savedAlbumThumbnailAssetId = albumThumbnailAssetId;
    connectReply(reply, [this, savedAlbumId, savedAlbumName, savedDescription, savedIsActivityEnabled, savedAlbumThumbnailAssetId](const QByteArray &) {
        emit albumUpdated(savedAlbumId, savedAlbumName, savedDescription, savedIsActivityEnabled, savedAlbumThumbnailAssetId);
    });
}

void ImmichApi::fetchTimelineBuckets(const QString &context, const QVariantMap &params)
{
    qInfo().noquote().nospace() << "ImmichApi: Fetching timeline buckets, context: \"" << context << "\" params: " << QJsonDocument::fromVariant(params).toJson(QJsonDocument::Compact);
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/timeline/buckets"));
    QUrlQuery query;
    for (auto it = params.constBegin(); it != params.constEnd(); ++it) {
        query.addQueryItem(it.key(), it.value().toString());
    }
    url.setQuery(query);

    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    QString savedContext = context;

    connectReply(reply, [this, savedContext](const QByteArray &response) {
        QJsonArray buckets = QJsonDocument::fromJson(response).array();
        qInfo() << "ImmichApi: Context buckets for" << savedContext << "count:" << buckets.size();
        emit timelineBucketsReceived(savedContext, buckets);
    });
}

void ImmichApi::fetchTimelineBucket(const QString &context, const QString &timeBucket, const QVariantMap &params)
{
    qInfo().noquote().nospace() << "ImmichApi: Fetching timeline bucket: \"" << timeBucket << "\" context: " << QJsonDocument::fromVariant(params).toJson(QJsonDocument::Compact);
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/timeline/bucket"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("timeBucket"), timeBucket);
    for (auto it = params.constBegin(); it != params.constEnd(); ++it) {
        query.addQueryItem(it.key(), it.value().toString());
    }
    url.setQuery(query);

    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    QString savedContext = context;
    QString savedTimeBucket = timeBucket;

    connectReply(reply, [this, savedContext, savedTimeBucket](const QByteArray &response) {
        QJsonObject data = QJsonDocument::fromJson(response).object();
        emit timelineBucketReceived(savedContext, savedTimeBucket, data);
    });
}

void ImmichApi::setVideoSource(QObject *videoItem, const QString &assetId)
{
    if (!videoItem) {
        qWarning() << "ImmichApi: Value of videoItem is null";
        return;
    }

    QMediaPlayer *player = videoItem->findChild<QMediaPlayer*>();
    if (!player) {
        qWarning() << "ImmichApi: Could not find QMediaPlayer in video item";
        return;
    }

    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets/") + assetId + QStringLiteral("/video/playback"));
    QNetworkRequest request(url);
    request.setRawHeader("Authorization", QString("Bearer %1").arg(m_authManager->getAccessToken()).toUtf8());

    qDebug() << "ImmichApi: Setting video source to" << url.toString();
    player->setMedia(QMediaContent(request));
}

void ImmichApi::checkExistingAssets(const QStringList &deviceAssetIds)
{
    qInfo() << "ImmichApi: Checking" << deviceAssetIds.size() << "assets against server";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets/exist"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["deviceAssetIds"] = toJsonStringArray(deviceAssetIds);
    json["deviceId"] = QStringLiteral("harbour-immich");

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject obj = doc.object();
        QJsonArray existingArray = obj["existingIds"].toArray();
        QStringList existingIds;
        for (const QJsonValue &val : existingArray) {
            existingIds.append(val.toString());
        }
        qInfo() << "ImmichApi: Server reports" << existingIds.size() << "existing assets";
        emit existingAssetsChecked(existingIds);
    });
}

void ImmichApi::bulkUploadCheck(const QJsonArray &assets)
{
    qInfo() << "ImmichApi: Bulk upload check for" << assets.size() << "assets";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets/bulk-upload-check"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["assets"] = assets;

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject obj = doc.object();
        QJsonArray results = obj["results"].toArray();
        qInfo() << "ImmichApi: Bulk upload check returned" << results.size() << "results";
        emit bulkUploadCheckCompleted(results);
    }, 120000); // 120s timeout for bulk operations
}

void ImmichApi::getStack(const QString &stackId)
{
    qInfo() << "ImmichApi: Getting stack:" << stackId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/stacks/") + stackId);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    QString savedStackId = stackId;
    connectReply(reply, [this, savedStackId](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject obj = doc.object();
        QJsonArray assets = obj["assets"].toArray();
        qInfo() << "ImmichApi: Stack received with" << assets.size() << "assets";
        emit stackReceived(savedStackId, assets);
    });
}

void ImmichApi::createStack(const QStringList &assetIds)
{
    qInfo() << "ImmichApi: Creating stack with" << assetIds.size() << "assets";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/stacks"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["assetIds"] = toJsonStringArray(assetIds);

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject obj = doc.object();
        QString stackId = obj["id"].toString();
        qInfo() << "ImmichApi: Stack created:" << stackId;
        emit stackCreated(stackId);
    });
}

void ImmichApi::deleteStack(const QString &stackId)
{
    qInfo() << "ImmichApi: Deleting stack:" << stackId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/stacks/") + stackId);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->deleteResource(request);
    QString savedStackId = stackId;
    connectReply(reply, [this, savedStackId](const QByteArray &) {
        qInfo() << "ImmichApi: Stack deleted:" << savedStackId;
        emit stackDeleted(savedStackId);
    });
}
