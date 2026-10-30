#include "immichapi.h"
#include "authmanager.h"
#include "clientcertmanager.h"
#include "settingsmanager.h"
#include "assetdatabase.h"
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QSqlQuery>
#include <QSqlError>
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
#include <QSharedPointer>
#include <algorithm>
#include <QLocale>

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
    , m_networkManager(new TlsNetworkAccessManager(this))
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

void ImmichApi::fetchAlbums(const QString &filter)
{
    qInfo() << "ImmichApi: Fetching albums, filter:" << filter;
    QJsonArray albums = albumsFromCatalog(filter);
    qInfo() << "ImmichApi: Albums from catalog, count:" << albums.size();
    emit albumsReceived(albums);
}

void ImmichApi::fetchAlbumDetails(const QString &albumId)
{
    qInfo() << "ImmichApi: Fetching album details for:" << albumId;
    emit albumDetailsReceived(albumJsonFromCatalog(albumId));
}

void ImmichApi::fetchAlbumsForAsset(const QString &assetId)
{
    qInfo() << "ImmichApi: Fetching albums for asset:" << assetId;
    AssetDatabase *db = AssetDatabase::instance();
    QJsonArray albums;
    QSqlQuery q(db->db());
    q.prepare(QStringLiteral("SELECT DISTINCT album_id FROM album_to_asset WHERE asset_id = ?"));
    q.addBindValue(assetId);
    if (q.exec()) {
        while (q.next()) {
            albums.append(albumJsonFromCatalog(q.value(0).toString()));
        }
    }
    emit assetAlbumsReceived(assetId, albums);
}

void ImmichApi::populateBaseSearchParams(QJsonObject &json, const QVariantMap &searchParams)
{
    // Helper: copy non-empty string param (with optional JSON key rename)
    auto copyString = [&](const QString &key, const QString &jsonKey = QString()) {
        if (searchParams.contains(key) && !searchParams[key].toString().isEmpty()) {
            json[jsonKey.isEmpty() ? key : jsonKey] = searchParams[key].toString();
        }
    };

    // Helper: copy string param that may be empty
    auto copyStringAllowEmpty = [&](const QString &key) {
        if (searchParams.contains(key)) {
            json[key] = searchParams[key].toString();
        }
    };

    // Helper: copy bool param
    auto copyBool = [&](const QString &key) {
        if (searchParams.contains(key))
            json[key] = searchParams[key].toBool();
    };

    // OCR
    copyString("ocr");

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
    copyStringAllowEmpty("state");
    copyStringAllowEmpty("country");
    copyString("city");

    // Camera
    copyStringAllowEmpty("make");
    copyStringAllowEmpty("model");
    copyStringAllowEmpty("lensModel");

    // Date range
    copyString("takenAfter");
    copyString("takenBefore");

    // Media type
    if (searchParams.contains("type") && searchParams["type"].toString() != "all") {
        json["type"] = searchParams["type"].toString().toUpper();
    }

    // Display options
    copyBool("isNotInAlbum");
    copyBool("isFavorite");

    if (searchParams.contains("visibility") && !searchParams["visibility"].toString().isEmpty()) {
        json["visibility"] = searchParams["visibility"].toString();
    } else {
        json["visibility"] = QStringLiteral("timeline");
    }

    // Pagination
    if (searchParams.contains("page")) {
        json["page"] = searchParams["page"].toInt();
    }
    json["size"] = searchParams.contains("size") ? searchParams["size"].toInt() : 250;

    json["withExif"] = searchParams.contains("withExif") ? searchParams["withExif"].toBool() : false;
}

void ImmichApi::searchByParameters(const QVariantMap &searchParams)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/search/metadata"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    populateBaseSearchParams(json, searchParams);

    // Metadata specific fields
    auto copyString = [&](const QString &key) {
        if (searchParams.contains(key) && !searchParams[key].toString().isEmpty()) {
            json[key] = searchParams[key].toString();
        }
    };
    copyString("originalFileName");
    copyString("description");

    // Sort order
    json["order"] = searchParams.contains("order") ? searchParams["order"].toString() : QStringLiteral("desc");

    QJsonDocument doc(json);
    qInfo().noquote() << "ImmichApi: Fetching search for params:" << doc.toJson(QJsonDocument::Compact);
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
        qInfo() << "ImmichApi: Search results received, count:" << results.size();
        emit searchResultsReceived(results);
    } else {
        handleNetworkError(reply);
    }

    reply->deleteLater();
}

void ImmichApi::searchSmartByParameters(const QVariantMap &searchParams)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/search/smart"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    populateBaseSearchParams(json, searchParams);

    // Smart search specific fields
    auto copyString = [&](const QString &key) {
        if (searchParams.contains(key) && !searchParams[key].toString().isEmpty()) {
            json[key] = searchParams[key].toString();
        }
    };
    copyString("query");
    copyString("queryAssetId");

    // Language
    QString lang = QLocale::system().bcp47Name().section('-', 0, 0);
    json["language"] = lang.isEmpty() ? QStringLiteral("en") : lang;

    QJsonDocument doc(json);
    qInfo().noquote() << "ImmichApi: Fetching search (smart) for params:" << doc.toJson(QJsonDocument::Compact);
    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    connect(reply, &QNetworkReply::finished, this, &ImmichApi::onSearchByParametersReplyFinished);
}

void ImmichApi::fetchPeople(bool withHidden)
{
    qInfo() << "ImmichApi: Fetching people, withHidden:" << withHidden;
    QJsonArray people = peopleFromCatalog(withHidden);
    qInfo() << "ImmichApi: People from catalog, count:" << people.size();
    emit peopleReceived(people);
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
    const QJsonObject info = assetInfoFromCatalog(assetId);
    if (!info.isEmpty()) {
        emit assetInfoReceived(info);
        return;
    }
    // Fallback - asset not in catalog
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

void ImmichApi::connectReply(QNetworkReply *reply, std::function<void(const QByteArray&)> onSuccess, int timeoutMs, std::function<void()> onFailure)
{
    QTimer *timer = new QTimer(reply);
    timer->setSingleShot(true);
    timer->setInterval(timeoutMs);
    connect(timer, &QTimer::timeout, reply, &QNetworkReply::abort);
    connect(reply, &QNetworkReply::finished, timer, &QTimer::stop);
    timer->start();

    connect(reply, &QNetworkReply::finished, this, [this, reply, onSuccess, onFailure]() {
        if (reply->error() == QNetworkReply::NoError) {
            onSuccess(reply->readAll());
        } else {
            handleNetworkError(reply);
            if (onFailure) onFailure();
        }
        reply->deleteLater();
    });
}

void ImmichApi::uploadAssets(const QStringList &filePaths)
{
    if (filePaths.isEmpty())
        return;

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

    QHttpMultiPart *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

    auto addFormField = [&](const char *name, const QByteArray &value) {
        QHttpPart part;
        part.setHeader(QNetworkRequest::ContentDispositionHeader, QVariant(QStringLiteral("form-data; name=\"%1\"").arg(name)));
        part.setBody(value);
        multiPart->append(part);
    };

    QHttpPart filePart;
    filePart.setHeader(QNetworkRequest::ContentTypeHeader, QVariant(mimeType));
    filePart.setHeader(QNetworkRequest::ContentDispositionHeader, QVariant("form-data; name=\"assetData\"; filename=\"" + fileInfo.fileName() + "\""));
    filePart.setBodyDevice(file);
    file->setParent(multiPart);
    multiPart->append(filePart);

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

void ImmichApi::deleteAssets(const QStringList &assetIds, bool force)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["ids"] = toJsonStringArray(assetIds);
    json["force"] = force;

    QBuffer *buffer = createJsonBuffer(json);

    QNetworkReply *reply = m_networkManager->sendCustomRequest(request, "DELETE", buffer);
    buffer->setParent(reply);
    reply->setProperty("assetIds", assetIds);
    reply->setProperty("force", force);
    connect(reply, &QNetworkReply::finished, this, &ImmichApi::onDeleteReplyFinished);
}

void ImmichApi::onDeleteReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;

    if (reply->error() == QNetworkReply::NoError) {
        QStringList assetIds = reply->property("assetIds").toStringList();
        emit assetsDeleted(assetIds, reply->property("force").toBool());
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
    reply->setProperty("assetIds", assetIds);
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
    QStringList savedAssetIds = assetIds;
    connectReply(reply, [this, savedAlbumId, savedAssetIds](const QByteArray &) {
        emit assetsRemovedFromAlbum(savedAlbumId, savedAssetIds);
    });
}

void ImmichApi::onAddToAlbumReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;

    if (reply->error() == QNetworkReply::NoError) {
        QString albumId = reply->property("albumId").toString();
        QStringList assetIds = reply->property("assetIds").toStringList();

        QStringList applied;
        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        if (doc.isArray()) {
            const QJsonArray results = doc.array();
            for (const QJsonValue &v : results) {
                const QJsonObject r = v.toObject();
                const QString id = r["id"].toString();
                if (r["success"].toBool() || r["error"].toString() == QLatin1String("duplicate")) {
                    applied.append(id);
                }
            }
        } else {
            applied = assetIds;
        }
        emit assetsAddedToAlbum(albumId, applied);
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

QJsonArray ImmichApi::catalogUsers() const
{
    AssetDatabase *db = AssetDatabase::instance();
    QJsonArray users;
    QSqlQuery q(db->db());
    q.exec(QStringLiteral(
        "SELECT id, name, email"
        " FROM sync_user"
        " WHERE deleted_at IS NULL"
        " AND id != (SELECT value FROM sync_meta WHERE key = 'current_user_id')"
        " ORDER BY name"));
    while (q.next()) {
        QJsonObject u;
        u[QStringLiteral("id")] = q.value(0).toString();
        u[QStringLiteral("name")] = q.value(1).toString();
        u[QStringLiteral("email")] = q.value(2).toString();
        users.append(u);
    }
    return users;
}

void ImmichApi::fetchUsers()
{
    qInfo() << "ImmichApi: Fetching users";
    QJsonArray users = catalogUsers();
    qInfo() << "ImmichApi: Users from catalog, count:" << users.size();
    emit usersReceived(users);
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

void ImmichApi::fetchMemories(const QVariantMap &params)
{
    qInfo() << "ImmichApi: Fetching memories";
    QJsonArray memories = memoriesFromCatalog(params);
    qInfo() << "ImmichApi: Memories from catalog, count:" << memories.size();
    emit memoriesReceived(memories, params.value(QStringLiteral("requestTag")).toString());
}

void ImmichApi::updateMemory(const QString &memoryId, const QVariantMap &fields)
{
    qInfo() << "ImmichApi: Updating memory:" << memoryId << "fields:" << fields.keys();
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/memories/") + memoryId);
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json = QJsonObject::fromVariantMap(fields);
    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
    QString savedId = memoryId;
    connectReply(reply, [this, savedId](const QByteArray &response) {
        QJsonObject obj = QJsonDocument::fromJson(response).object();
        const bool isSaved = obj.value(QStringLiteral("isSaved")).toBool();
        emit memoryUpdated(savedId, isSaved);
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

void ImmichApi::removeAlbum(const QString &albumId)
{
    qInfo() << "ImmichApi: Removing album:" << albumId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/albums/") + albumId);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->deleteResource(request);
    QString savedAlbumId = albumId;
    connectReply(reply, [this, savedAlbumId](const QByteArray &) {
        qInfo() << "ImmichApi: Album removed:" << savedAlbumId;
        emit albumRemoved(savedAlbumId);
    });
}

void ImmichApi::bulkUploadCheck(const QJsonArray &assets, const QString &token)
{
    qInfo() << "ImmichApi: Bulk upload check for" << assets.size() << "assets";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets/bulk-upload-check"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["assets"] = assets;

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    connectReply(reply, [this, token](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject obj = doc.object();
        QJsonArray results = obj["results"].toArray();
        qInfo() << "ImmichApi: Bulk upload check returned" << results.size() << "results";
        emit bulkUploadCheckCompleted(results, token);
    }, 120000); // 120s timeout for bulk operations
    connect(reply, &QNetworkReply::finished, this, [this, reply, token]() {
        if (reply->error() != QNetworkReply::NoError) {
            emit bulkUploadCheckFailed(token);
        }
    });
}

void ImmichApi::getStack(const QString &stackId)
{
    qInfo() << "ImmichApi: Getting stack:" << stackId;
    AssetDatabase *db = AssetDatabase::instance();
    QJsonArray assets;
    QSqlQuery q(db->db());
    q.prepare(QStringLiteral(
        "SELECT ra.id, ra.type, ra.name, ra.is_favorite, ra.thumb_hash, ra.created_at,"
        " ra.local_date_time, ra.live_photo_video_id"
        " FROM remote_asset ra"
        " LEFT JOIN stack s ON s.id = ra.stack_id"
        " WHERE ra.stack_id = ? AND ra.deleted_at IS NULL"
        " ORDER BY (ra.id = s.primary_asset_id) DESC, ra.created_at"));
    q.addBindValue(stackId);
    if (q.exec()) {
        while (q.next()) {
            QJsonObject a;
            a[QStringLiteral("id")] = q.value(0).toString();
            a[QStringLiteral("type")] = q.value(1).toString();
            a[QStringLiteral("originalFileName")] = q.value(2).toString();
            a[QStringLiteral("isFavorite")] = q.value(3).toInt() != 0;
            a[QStringLiteral("thumbhash")] = q.value(4).toString();
            a[QStringLiteral("fileCreatedAt")] = q.value(5).toString();
            a[QStringLiteral("localDateTime")] = q.value(6).toString();
            a[QStringLiteral("livePhotoVideoId")] = q.value(7).toString();
            assets.append(a);
        }
    } else {
        qWarning() << "ImmichApi: Failed getStack catalog query:" << q.lastError().text();
    }
    emit stackReceived(stackId, assets);
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
    connectReply(reply, [this, assetIds](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject obj = doc.object();
        QString stackId = obj["id"].toString();
        QString primaryAssetId = obj["primaryAssetId"].toString();
        QStringList stackAssetIds;
        const QJsonArray assets = obj["assets"].toArray();
        for (const QJsonValue &v : assets) {
            stackAssetIds.append(v.toObject()["id"].toString());
        }
        if (stackAssetIds.isEmpty()) {
            stackAssetIds = assetIds;
        }
        if (primaryAssetId.isEmpty() && !stackAssetIds.isEmpty()) {
            primaryAssetId = stackAssetIds.first();
        }
        qInfo() << "ImmichApi: Stack created:" << stackId;
        emit stackCreated(stackId, primaryAssetId, stackAssetIds);
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

void ImmichApi::changeAssetVisibility(const QStringList &assetIds, const QString &visibility)
{
    qInfo() << "ImmichApi: Changing visibility to" << visibility << "for" << assetIds.size() << "assets";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/assets"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["ids"] = toJsonStringArray(assetIds);
    json["visibility"] = visibility;
    QJsonDocument doc(json);

    QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
    QStringList savedIds = assetIds;
    QString savedVisibility = visibility;
    connectReply(reply, [this, savedIds, savedVisibility](const QByteArray &) {
        emit assetVisibilityChanged(savedIds, savedVisibility);
    });
}

void ImmichApi::restoreFromTrash(const QStringList &assetIds)
{
    qInfo() << "ImmichApi: Restoring" << assetIds.size() << "assets from trash";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/trash/restore/assets"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["ids"] = toJsonStringArray(assetIds);
    QJsonDocument doc(json);

    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    QStringList savedIds = assetIds;
    connectReply(reply, [this, savedIds](const QByteArray &) {
        emit trashRestored(savedIds);
    });
}

void ImmichApi::emptyTrash()
{
    qInfo() << "ImmichApi: Emptying trash";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/trash/empty"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->post(request, QByteArray());
    connectReply(reply, [this](const QByteArray &) {
        emit trashEmptied();
    });
}

void ImmichApi::restoreAllTrash()
{
    qInfo() << "ImmichApi: Restoring all trash";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/trash/restore"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->post(request, QByteArray());
    connectReply(reply, [this](const QByteArray &) {
        emit allTrashRestored();
    });
}

void ImmichApi::fetchSharedLinks()
{
    qInfo() << "ImmichApi: Fetching shared links";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/shared-links"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonArray links = doc.array();
        qInfo() << "ImmichApi: Shared links received, count:" << links.size();
        emit sharedLinksReceived(links);
    });
}

void ImmichApi::fetchSharedLink(const QString &id)
{
    qInfo() << "ImmichApi: Fetching shared link" << id;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/shared-links/") + id);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject link = doc.object();
        qInfo() << "ImmichApi: Shared link received:" << link["id"].toString();
        emit sharedLinkReceived(link);
    });
}

void ImmichApi::deleteSharedLink(const QString &id)
{
    qInfo() << "ImmichApi: Deleting shared link:" << id;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/shared-links/") + id);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->deleteResource(request);
    QString savedId = id;
    connectReply(reply, [this, savedId](const QByteArray &) {
        emit sharedLinkDeleted(savedId);
    });
}

void ImmichApi::updateSharedLink(const QString &id, const QString &description, const QString &password, bool changePassword, const QString &expiresAt, bool allowDownload, bool allowUpload, bool showMetadata, const QString &slug)
{
    qInfo() << "ImmichApi: Updating shared link:" << id;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/shared-links/") + id);
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["description"] = description;
    json["allowDownload"] = allowDownload;
    json["allowUpload"] = allowUpload;
    json["showMetadata"] = showMetadata;
    if (changePassword) {
        if (!password.isEmpty()) {
            json["password"] = password;
        } else {
            json["password"] = QJsonValue::Null;
        }
    }
    if (!expiresAt.isEmpty()) {
        json["expiresAt"] = expiresAt;
    } else {
        json["expiresAt"] = QJsonValue::Null;
    }
    if (!slug.isEmpty()) {
        json["slug"] = slug;
    }

    QBuffer *buffer = createJsonBuffer(json);
    QNetworkReply *reply = m_networkManager->sendCustomRequest(request, "PATCH", buffer);
    buffer->setParent(reply);
    QString savedId = id;
    connectReply(reply, [this, savedId](const QByteArray &) {
        emit sharedLinkUpdated(savedId);
    });
}

void ImmichApi::updatePerson(const QString &personId, const QVariantMap &fields)
{
    qInfo() << "ImmichApi: Updating person:" << personId << "fields:" << fields.keys();
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/people/") + personId);
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    for (auto it = fields.constBegin(); it != fields.constEnd(); ++it) {
        if (it.key() == QStringLiteral("birthDate") && it.value().toString().isEmpty()) {
            json[it.key()] = QJsonValue::Null;
        } else {
            json[it.key()] = QJsonValue::fromVariant(it.value());
        }
    }

    QJsonDocument doc(json);
    QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
    QString savedId = personId;
    connectReply(reply, [this, savedId](const QByteArray &) {
        emit personUpdated(savedId);
    });
}

QJsonObject ImmichApi::userPreferences() const
{
    AssetDatabase *db = AssetDatabase::instance();
    QSqlQuery q(db->db());
    q.prepare(QStringLiteral("SELECT value FROM user_metadata WHERE key = 'preferences' AND user_id = (SELECT value FROM sync_meta WHERE key = 'current_user_id')"));
    if (q.exec() && q.next()) {
        return QJsonDocument::fromJson(q.value(0).toString().toUtf8()).object();
    }
    return QJsonObject();
}

QString ImmichApi::personUpdateStrategy() const
{
    const QString strategy = userPreferences().value(QStringLiteral("people")).toObject().value(QStringLiteral("updateStrategy")).toString();
    if (strategy == QLatin1String("self") || strategy == QLatin1String("everyone")) {
        return strategy;
    }
    return QStringLiteral("everyone");
}

void ImmichApi::fetchPersonShares()
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/people/users"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        emit personSharesReceived(QJsonDocument::fromJson(response).array());
    });
}

void ImmichApi::fetchClusterGroupUsers(const QString &groupId)
{
    const QString gid = groupId.isEmpty() ? m_authManager->clusterGroupId() : groupId;
    if (gid.isEmpty()) {
        emit clusterGroupUsersReceived(QJsonArray(), gid);
        return;
    }
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/cluster-groups/") + gid + QStringLiteral("/users"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this, gid](const QByteArray &response) {
        const QString me = m_authManager->userId();
        AssetDatabase *db = AssetDatabase::instance();
        QSqlQuery q(db->db());
        q.prepare(QStringLiteral("SELECT 1 FROM partner WHERE (shared_by_id = ? AND shared_with_id = ?) OR (shared_by_id = ? AND shared_with_id = ?)"));
        QList<QJsonObject> users;
        const QJsonArray arr = QJsonDocument::fromJson(response).array();
        for (const QJsonValue &v : arr) {
            QJsonObject u = v.toObject();
            const QString uid = u.value(QStringLiteral("id")).toString();
            if (uid.isEmpty() || uid == me) {
                continue;
            }
            q.addBindValue(uid);
            q.addBindValue(me);
            q.addBindValue(me);
            q.addBindValue(uid);
            u[QStringLiteral("isPartner")] = q.exec() && q.next();
            users.append(u);
        }
        std::sort(users.begin(), users.end(), [](const QJsonObject &a, const QJsonObject &b) {
            return a.value(QStringLiteral("name")).toString().compare(b.value(QStringLiteral("name")).toString(), Qt::CaseInsensitive) < 0;
        });
        QJsonArray result;
        for (const QJsonObject &u : users) {
            result.append(u);
        }
        emit clusterGroupUsersReceived(result, gid);
    });
}

void ImmichApi::fetchClusterGroupRequests()
{
    qInfo() << "ImmichApi: Fetching received cluster group requests";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/cluster-groups/requests"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        emit clusterGroupRequestsReceived(QJsonDocument::fromJson(response).array());
    });
}

void ImmichApi::fetchClusterGroupSentRequests()
{
    qInfo() << "ImmichApi: Fetching sent cluster group requests";
    const QString groupId = m_authManager->clusterGroupId();
    if (groupId.isEmpty()) {
        emit clusterGroupSentRequestsReceived(QJsonArray());
        return;
    }
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/cluster-groups/") + groupId + QStringLiteral("/requests"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        emit clusterGroupSentRequestsReceived(QJsonDocument::fromJson(response).array());
    });
}

void ImmichApi::inviteToClusterGroup(const QStringList &userIds)
{
    if (userIds.isEmpty()) {
        return;
    }
    qInfo() << "ImmichApi: Inviting" << userIds.size() << "users to cluster group";
    const QString groupId = m_authManager->clusterGroupId();
    if (groupId.isEmpty()) {
        emit clusterGroupInvitesSent();
        return;
    }
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/cluster-groups/") + groupId + QStringLiteral("/requests"));
    QSharedPointer<int> remaining(new int(userIds.size()));
    for (const QString &userId : userIds) {
        QNetworkRequest request = createAuthenticatedRequest(url);
        QJsonObject json;
        json[QStringLiteral("userId")] = userId;
        QNetworkReply *reply = m_networkManager->put(request, QJsonDocument(json).toJson());
        auto done = [this, remaining]() {
            *remaining -= 1;
            if (*remaining == 0) {
                emit clusterGroupInvitesSent();
            }
        };
        connectReply(reply, [done](const QByteArray &) {
            done();
        }, 30000, done);
    }
}

void ImmichApi::acceptClusterGroupRequest(const QString &requestId)
{
    qInfo() << "ImmichApi: Accepting cluster group request:" << requestId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/cluster-groups/requests/") + requestId + QStringLiteral("/accept"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->post(request, QByteArray());
    connectReply(reply, [this](const QByteArray &) {
        m_authManager->fetchCurrentUser();
        emit clusterGroupJoined();
    });
}

void ImmichApi::declineClusterGroupRequest(const QString &requestId)
{
    qInfo() << "ImmichApi: Deleting cluster group request:" << requestId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/cluster-groups/requests/") + requestId);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->deleteResource(request);
    connectReply(reply, [this, requestId](const QByteArray &) {
        emit clusterGroupRequestDeleted(requestId);
    });
}

void ImmichApi::leaveClusterGroup()
{
    qInfo() << "ImmichApi: Leaving cluster group";
    const QString groupId = m_authManager->clusterGroupId();
    if (groupId.isEmpty()) {
        return;
    }
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/cluster-groups/") + groupId + QStringLiteral("/leave"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->post(request, QByteArray());
    connectReply(reply, [this](const QByteArray &) {
        m_authManager->fetchCurrentUser();
        emit clusterGroupLeft();
    });
}

void ImmichApi::regenerateClusterGroupPeople()
{
    qInfo() << "ImmichApi: Regenerating cluster group people";
    const QString groupId = m_authManager->clusterGroupId();
    if (groupId.isEmpty()) {
        return;
    }
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/cluster-groups/") + groupId + QStringLiteral("/regenerate-people"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->post(request, QByteArray());
    connectReply(reply, [this](const QByteArray &) {
        emit clusterGroupPeopleRegenerated();
    });
}

void ImmichApi::sharePeople(const QStringList &personIds, const QStringList &userIds)
{
    qInfo() << "ImmichApi: Sharing" << personIds.size() << "people with" << userIds.size() << "users";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/people/users"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json[QStringLiteral("personIds")] = toJsonStringArray(personIds);
    json[QStringLiteral("sharedWithIds")] = toJsonStringArray(userIds);
    json[QStringLiteral("role")] = QStringLiteral("admin");

    QNetworkReply *reply = m_networkManager->put(request, QJsonDocument(json).toJson());
    connectReply(reply, [this, personIds](const QByteArray &) {
        emit peopleShared(personIds);
    });
}

void ImmichApi::sharePeopleWithEveryone(const QStringList &userIds)
{
    qInfo() << "ImmichApi: Sharing all people with" << userIds.size() << "users";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/people/users"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json[QStringLiteral("type")] = QStringLiteral("everyone");
    json[QStringLiteral("sharedWithIds")] = toJsonStringArray(userIds);
    json[QStringLiteral("role")] = QStringLiteral("admin");

    QNetworkReply *reply = m_networkManager->put(request, QJsonDocument(json).toJson());
    connectReply(reply, [this](const QByteArray &) {
        emit peopleShared(QStringList());
    });
}

QNetworkReply *ImmichApi::sendPeopleUsersDeleteRequest(const QJsonArray &items)
{
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/people/users"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    const QByteArray payload = QJsonDocument(items).toJson(QJsonDocument::Compact);
    auto *buffer = new QBuffer();
    buffer->setData(payload);
    buffer->open(QIODevice::ReadOnly);
    QNetworkReply *reply = m_networkManager->sendCustomRequest(request, "DELETE", buffer);
    buffer->setParent(reply);
    return reply;
}

void ImmichApi::unsharePerson(const QString &personId, const QString &userId)
{
    qInfo() << "ImmichApi: Unsharing person" << personId << "from" << userId;
    QJsonObject item;
    item[QStringLiteral("personId")] = personId;
    item[QStringLiteral("sharedWithId")] = userId;
    QNetworkReply *reply = sendPeopleUsersDeleteRequest(QJsonArray{item});
    connectReply(reply, [this, personId, userId](const QByteArray &) {
        emit personUnshared(personId, userId);
    });
}

void ImmichApi::unsharePeople(const QStringList &personIds, const QString &userId)
{
    if (personIds.isEmpty()) {
        return;
    }
    qInfo() << "ImmichApi: Unsharing" << personIds.size() << "people from" << userId;
    QJsonArray items;
    for (const QString &personId : personIds) {
        QJsonObject item;
        item[QStringLiteral("personId")] = personId;
        item[QStringLiteral("sharedWithId")] = userId;
        items.append(item);
    }
    QNetworkReply *reply = sendPeopleUsersDeleteRequest(items);
    connectReply(reply, [this, personIds, userId](const QByteArray &) {
        emit peopleUnshared(personIds, userId);
    });
}

QJsonArray ImmichApi::ownPeople() const
{
    return peopleFromCatalog(true, AssetDatabase::instance()->metaValue(QStringLiteral("current_user_id")));
}

QString ImmichApi::currentUserName() const
{
    AssetDatabase *db = AssetDatabase::instance();
    QSqlQuery q(db->db());
    q.exec(QStringLiteral("SELECT name FROM sync_user WHERE id = (SELECT value FROM sync_meta WHERE key = 'current_user_id')"));
    if (q.next()) {
        return q.value(0).toString();
    }
    return QString();
}

void ImmichApi::fetchCities()
{
    qInfo() << "ImmichApi: Fetching cities";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/search/cities"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonArray cities = doc.array();
        qInfo() << "ImmichApi: Cities received, count:" << cities.size();
        emit citiesReceived(cities);
    });
}

void ImmichApi::fetchUniqueFolderPaths()
{
    qInfo() << "ImmichApi: Fetching unique folder paths";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/view/folder/unique-paths"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonArray paths = doc.array();
        qInfo() << "ImmichApi: Unique folder paths received, count:" << paths.size();
        emit uniqueFolderPathsReceived(paths);
    });
}

void ImmichApi::fetchServerFolders(const QString &path)
{
    qInfo() << "ImmichApi: Fetching server folder assets, path:" << path;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/view/folder"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("path"), path);
    url.setQuery(query);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    QString savedPath = path;
    connectReply(reply, [this, savedPath](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonArray items;
        if (doc.isArray()) {
            items = doc.array();
        } else if (doc.isObject()) {
            items.append(doc.object());
        }
        emit serverFoldersReceived(savedPath, items);
    });
}

void ImmichApi::fetchPartners(const QString &direction)
{
    qInfo() << "ImmichApi: Fetching partners, direction:" << direction;
    AssetDatabase *db = AssetDatabase::instance();
    QString me = db->metaValue(QStringLiteral("current_user_id"));
    if (me.isEmpty()) {
        me = m_authManager->userId();
    }
    const QString otherCol = direction == QLatin1String("shared-by") ? QStringLiteral("shared_with_id") : QStringLiteral("shared_by_id");
    const QString meCol = direction == QLatin1String("shared-by") ? QStringLiteral("shared_by_id") : QStringLiteral("shared_with_id");
    QJsonArray partners;
    QSqlQuery q(db->db());
    q.prepare(QStringLiteral("SELECT p.%1, p.in_timeline, COALESCE(su.name, au.name), COALESCE(su.email, au.email) FROM partner p LEFT JOIN sync_user su ON su.id = p.%1 LEFT JOIN auth_user au ON au.id = p.%1 WHERE p.%2 = ?").arg(otherCol, meCol));
    q.addBindValue(me);
    if (q.exec()) {
        while (q.next()) {
            QJsonObject p;
            p[QStringLiteral("id")] = q.value(0).toString();
            p[QStringLiteral("inTimeline")] = q.value(1).toInt() != 0;
            p[QStringLiteral("name")] = q.value(2).toString();
            p[QStringLiteral("email")] = q.value(3).toString();
            partners.append(p);
        }
    }
    emit partnersReceived(direction, partners);
}

void ImmichApi::createPartner(const QString &userId)
{
    qInfo() << "ImmichApi: Creating partner:" << userId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/partners"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json[QStringLiteral("sharedWithId")] = userId;
    QNetworkReply *reply = m_networkManager->post(request, QJsonDocument(json).toJson());
    QString savedId = userId;
    connectReply(reply, [this, savedId](const QByteArray &) {
        emit partnerCreated(savedId);
    });
}

void ImmichApi::removePartner(const QString &userId)
{
    qInfo() << "ImmichApi: Removing partner:" << userId;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/partners/") + userId);
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->deleteResource(request);
    QString savedId = userId;
    connectReply(reply, [this, savedId](const QByteArray &) {
        emit partnerRemoved(savedId);
    });
}

void ImmichApi::updatePartner(const QString &userId, bool inTimeline)
{
    qInfo() << "ImmichApi: Updating partner:" << userId << "inTimeline:" << inTimeline;
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/partners/") + userId);
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["inTimeline"] = inTimeline;
    QJsonDocument doc(json);

    QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
    QString savedId = userId;
    connectReply(reply, [this, savedId, inTimeline](const QByteArray &) {
        emit partnerUpdated(savedId, inTimeline);
    });
}

void ImmichApi::createPinCode(const QString &pin)
{
    qInfo() << "ImmichApi: Creating PIN code";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/auth/pin-code"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["pinCode"] = pin;
    QJsonDocument doc(json);

    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    connectReply(reply, [this](const QByteArray &) {
        emit pinCodeCreated();
    });
}

void ImmichApi::changePinCode(const QString &newPin, const QString &currentPin, const QString &password)
{
    qInfo() << "ImmichApi: Changing PIN code";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/auth/pin-code"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["newPinCode"] = newPin;
    if (!currentPin.isEmpty()) {
        json["pinCode"] = currentPin;
    } else {
        json["password"] = password;
    }
    QJsonDocument doc(json);

    QNetworkReply *reply = m_networkManager->put(request, doc.toJson());
    connectReply(reply, [this](const QByteArray &) {
        emit pinCodeChanged();
    });
}

void ImmichApi::resetPinCode(const QString &currentPin, const QString &password)
{
    qInfo() << "ImmichApi: Resetting PIN code";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/auth/pin-code"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    if (!currentPin.isEmpty()) {
        json["pinCode"] = currentPin;
    } else {
        json["password"] = password;
    }
    auto *buffer = createJsonBuffer(json);
    QNetworkReply *reply = m_networkManager->sendCustomRequest(request, "DELETE", buffer);
    buffer->setParent(reply);
    connectReply(reply, [this](const QByteArray &) {
        emit pinCodeReset();
    });
}

void ImmichApi::verifyPinCode(const QString &pin)
{
    qInfo() << "ImmichApi: Unlocking session with PIN code";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/auth/session/unlock"));
    QNetworkRequest request = createAuthenticatedRequest(url);

    QJsonObject json;
    json["pinCode"] = pin;
    QJsonDocument doc(json);

    QNetworkReply *reply = m_networkManager->post(request, doc.toJson());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        bool success = reply->error() == QNetworkReply::NoError;
        if (!success) {
            handleNetworkError(reply);
        }
        emit pinCodeVerified(success);
        reply->deleteLater();
    });
}

void ImmichApi::fetchAuthStatus()
{
    qInfo() << "ImmichApi: Fetching auth status";
    QUrl url(m_authManager->serverUrl() + QStringLiteral("/api/auth/status"));
    QNetworkRequest request = createAuthenticatedRequest(url);
    QNetworkReply *reply = m_networkManager->get(request);
    connectReply(reply, [this](const QByteArray &response) {
        QJsonDocument doc = QJsonDocument::fromJson(response);
        QJsonObject obj = doc.object();
        bool pinCodeExists = obj.value("pinCode").toBool(false);
        bool hasPassword = obj.value("password").toBool(false);
        qInfo() << "ImmichApi: Auth status - pinCode exists:" << pinCodeExists;
        emit authStatusReceived(pinCodeExists, hasPassword);
    });
}

QJsonObject ImmichApi::albumJsonFromCatalog(const QString &albumId) const
{
    AssetDatabase *db = AssetDatabase::instance();
    const QString me = db->metaValue(QStringLiteral("current_user_id"));
    QJsonObject album;
    QSqlQuery q(db->db());

    q.prepare(QStringLiteral(
        "SELECT a.id, a.name, a.description, a.created_at, a.updated_at,"
        " a.thumbnail_asset_id, a.is_activity_enabled,"
        " (SELECT COUNT(*) FROM album_to_asset ata WHERE ata.album_id = a.id) AS asset_count,"
        " (SELECT u.user_id FROM album_user u WHERE u.album_id = a.id AND u.role = 'owner' LIMIT 1) AS owner_id"
        " FROM album a WHERE a.id = ?"));
    q.addBindValue(albumId);
    if (!q.exec() || !q.next()) {
        return album;
    }

    const QString ownerId = q.value(8).toString();
    album[QStringLiteral("id")] = q.value(0).toString();
    album[QStringLiteral("ownerId")] = ownerId;
    album[QStringLiteral("albumName")] = q.value(1).toString();
    album[QStringLiteral("description")] = q.value(2).toString();
    album[QStringLiteral("createdAt")] = q.value(3).toString();
    album[QStringLiteral("updatedAt")] = q.value(4).toString();
    album[QStringLiteral("albumThumbnailAssetId")] = q.value(5).toString();
    album[QStringLiteral("isActivityEnabled")] = q.value(6).toInt() != 0;
    album[QStringLiteral("assetCount")] = q.value(7).toInt();

    // Date range for album assets
    QSqlQuery range(db->db());
    range.prepare(QStringLiteral("SELECT MIN(ra.created_at), MAX(ra.created_at) FROM album_to_asset x JOIN remote_asset ra ON ra.id = x.asset_id WHERE x.album_id = ?"));
    range.addBindValue(albumId);
    if (range.exec() && range.next()) {
        album[QStringLiteral("startDate")] = range.value(0).toString();
        album[QStringLiteral("endDate")] = range.value(1).toString();
    }

    // Album users
    QJsonArray albumUsers;
    QSqlQuery uq(db->db());
    uq.prepare(QStringLiteral("SELECT u.role, u.user_id, su.name, su.email FROM album_user u LEFT JOIN sync_user su ON su.id = u.user_id WHERE u.album_id = ?"));
    uq.addBindValue(albumId);
    if (uq.exec()) {
        while (uq.next()) {
            QJsonObject user;
            user[QStringLiteral("id")] = uq.value(1).toString();
            user[QStringLiteral("name")] = uq.value(2).toString();
            user[QStringLiteral("email")] = uq.value(3).toString();
            QJsonObject entry;
            entry[QStringLiteral("role")] = uq.value(0).toString();
            entry[QStringLiteral("user")] = user;
            albumUsers.append(entry);
        }
    }
    album[QStringLiteral("albumUsers")] = albumUsers;
    album[QStringLiteral("shared")] = (ownerId != me) || albumUsers.size() > 1;

    return album;
}

QJsonArray ImmichApi::albumsFromCatalog(const QString &filter) const
{
    static const QString me = QStringLiteral("(SELECT value FROM sync_meta WHERE key = 'current_user_id')");

    AssetDatabase *db = AssetDatabase::instance();
    QJsonArray albums;
    QSqlQuery q(db->db());
    QString where;
    if (filter == QLatin1String("shared")) {
        where = QStringLiteral(" WHERE shared");
    } else if (filter == QLatin1String("sharedWithMe")) {
        where = QStringLiteral(" WHERE owner_id IS NOT %1").arg(me);
    } else if (filter == QLatin1String("mine")) {
        where = QStringLiteral(" WHERE owner_id = %1 AND NOT shared").arg(me);
    }
    const QString sql = QStringLiteral(
        "SELECT * FROM ("
        " SELECT a.id, a.name, a.description, a.created_at, a.updated_at, a.thumbnail_asset_id,"
        " (SELECT COUNT(*) FROM album_to_asset x WHERE x.album_id = a.id) AS asset_count,"
        " (SELECT MIN(ra.created_at) FROM album_to_asset x JOIN remote_asset ra ON ra.id = x.asset_id WHERE x.album_id = a.id) AS start_date,"
        " (SELECT MAX(ra.created_at) FROM album_to_asset x JOIN remote_asset ra ON ra.id = x.asset_id WHERE x.album_id = a.id) AS end_date,"
        " o.user_id AS owner_id,"
        " COALESCE(NULLIF(su.name, ''), su.email) AS owner_name,"
        " (o.user_id IS NOT %1 OR (SELECT COUNT(*) FROM album_user u WHERE u.album_id = a.id) > 1) AS shared"
        " FROM album a"
        " LEFT JOIN album_user o ON o.album_id = a.id AND o.role = 'owner'"
        " LEFT JOIN sync_user su ON su.id = o.user_id"
        ")%2 ORDER BY name").arg(me, where);
    if (!q.exec(sql)) {
        qWarning() << "ImmichApi: Failed albums catalog query:" << q.lastError().text();
        return albums;
    }
    while (q.next()) {
        QJsonObject album;
        album[QStringLiteral("id")] = q.value(0).toString();
        album[QStringLiteral("albumName")] = q.value(1).toString();
        album[QStringLiteral("description")] = q.value(2).toString();
        album[QStringLiteral("createdAt")] = q.value(3).toString();
        album[QStringLiteral("updatedAt")] = q.value(4).toString();
        album[QStringLiteral("albumThumbnailAssetId")] = q.value(5).toString();
        album[QStringLiteral("assetCount")] = q.value(6).toInt();
        album[QStringLiteral("startDate")] = q.value(7).toString();
        album[QStringLiteral("endDate")] = q.value(8).toString();
        album[QStringLiteral("ownerId")] = q.value(9).toString();
        album[QStringLiteral("ownerName")] = q.value(10).toString();
        album[QStringLiteral("shared")] = q.value(11).toInt() != 0;
        albums.append(album);
    }
    return albums;
}

QJsonArray ImmichApi::peopleFromCatalog(bool withHidden, const QString &ownerId) const
{
    AssetDatabase *db = AssetDatabase::instance();
    QJsonArray people;
    QSqlQuery q(db->db());
    int minFaces = userPreferences().value(QStringLiteral("people")).toObject().value(QStringLiteral("minimumFaces")).toInt(3);
    if (minFaces <= 0) {
        minFaces = 3;
    }
    QString sql = QStringLiteral(
        "SELECT p.id, p.name, p.birth_date, p.is_favorite, p.is_hidden, p.updated_at, p.face_asset_id"
        " FROM person p"
        " JOIN asset_face af ON af.person_id = p.id AND af.is_visible = 1 AND af.deleted_at IS NULL"
        " JOIN remote_asset ra ON ra.id = af.asset_id AND ra.visibility = 'timeline' AND ra.deleted_at IS NULL");
    QStringList where;
    if (!withHidden) {
        where.append(QStringLiteral("p.is_hidden = 0"));
    }
    if (!ownerId.isEmpty()) {
        where.append(QStringLiteral("p.owner_id = ?"));
    }
    if (!where.isEmpty()) {
        sql += QStringLiteral(" WHERE ") + where.join(QStringLiteral(" AND "));
    }
    sql += QStringLiteral(" GROUP BY p.id HAVING COALESCE(p.name, '') != '' OR COUNT(DISTINCT ra.id) >= ? ORDER BY p.name");
    q.prepare(sql);
    if (!ownerId.isEmpty()) {
        q.addBindValue(ownerId);
    }
    q.addBindValue(minFaces);
    if (!q.exec()) {
        qWarning() << "ImmichApi: Failed people catalog query:" << q.lastError().text();
        return people;
    }
    while (q.next()) {
        QJsonObject p;
        p[QStringLiteral("id")] = q.value(0).toString();
        p[QStringLiteral("name")] = q.value(1).toString();
        p[QStringLiteral("birthDate")] = q.value(2).toString();
        p[QStringLiteral("isFavorite")] = q.value(3).toInt() != 0;
        p[QStringLiteral("isHidden")] = q.value(4).toInt() != 0;
        p[QStringLiteral("updatedAt")] = q.value(5).toString();
        p[QStringLiteral("hasThumbnail")] = !q.value(6).toString().isEmpty();
        people.append(p);
    }
    return people;
}

QJsonArray ImmichApi::memoriesFromCatalog(const QVariantMap &params) const
{
    AssetDatabase *db = AssetDatabase::instance();
    QJsonArray memories;
    QSqlQuery q(db->db());
    const QString now = QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'"));
    const bool upcoming = params.value(QStringLiteral("isUpcoming")).toString() == QLatin1String("true");
    const bool today = params.value(QStringLiteral("scope")).toString() == QLatin1String("today");

    QString sql = QStringLiteral("SELECT id, type, data, is_saved, memory_at FROM memory WHERE deleted_at IS NULL");
    if (params.value(QStringLiteral("isSaved")).toString() == QLatin1String("true")) {
        sql += QStringLiteral(" AND is_saved = 1");
    }
    if (upcoming) {
        sql += QStringLiteral(" AND show_at > ?");
    } else {
        sql += QStringLiteral(" AND (show_at IS NULL OR show_at <= ?)");
    }
    if (today) {
        sql += QStringLiteral(" AND (hide_at IS NULL OR hide_at > ?)");
    }
    const QString ord = params.value(QStringLiteral("order")).toString() == QLatin1String("asc") ? QStringLiteral("ASC") : QStringLiteral("DESC");
    if (today) {
        sql += QStringLiteral(" ORDER BY (type = 'birthday') DESC, memory_at %1").arg(ord);
    } else {
        sql += QStringLiteral(" ORDER BY memory_at %1").arg(ord);
    }
    q.prepare(sql);
    q.addBindValue(now);
    if (today) {
        q.addBindValue(now);
    }
    if (!q.exec()) {
        return memories;
    }
    while (q.next()) {
        QJsonObject m;
        const QString memoryId = q.value(0).toString();
        m[QStringLiteral("id")] = memoryId;
        m[QStringLiteral("type")] = q.value(1).toString();
        const QString dataText = q.value(2).toString();
        QJsonObject data = QJsonDocument::fromJson(dataText.toUtf8()).object();
        m[QStringLiteral("data")] = data;
        m[QStringLiteral("isSaved")] = q.value(3).toInt() != 0;
        m[QStringLiteral("memoryAt")] = q.value(4).toString();

        QJsonArray assets;
        QSqlQuery aq(db->db());
        aq.prepare(QStringLiteral(
            "SELECT ra.id, ra.thumb_hash, ra.type, ra.live_photo_video_id,"
            " ra.local_date_time, ra.created_at"
            " FROM memory_to_asset mta"
            " JOIN remote_asset ra ON mta.asset_id = ra.id"
            " WHERE mta.memory_id = ? AND ra.deleted_at IS NULL"
            " ORDER BY ra.created_at"));
        aq.addBindValue(memoryId);
        if (aq.exec()) {
            while (aq.next()) {
                QJsonObject a;
                a[QStringLiteral("id")] = aq.value(0).toString();
                a[QStringLiteral("thumbhash")] = aq.value(1).toString();
                a[QStringLiteral("type")] = aq.value(2).toString();
                const QString liveId = aq.value(3).toString();
                if (!liveId.isEmpty()) a[QStringLiteral("livePhotoVideoId")] = liveId;
                a[QStringLiteral("localDateTime")] = aq.value(4).toString();
                a[QStringLiteral("fileCreatedAt")] = aq.value(5).toString();
                assets.append(a);
            }
        }
        m[QStringLiteral("assets")] = assets;
        memories.append(m);
    }
    return memories;
}

QJsonObject ImmichApi::assetInfoFromCatalog(const QString &assetId) const
{
    AssetDatabase *db = AssetDatabase::instance();
    QJsonObject info;
    QSqlQuery q(db->db());
    q.prepare(QStringLiteral(
        "SELECT id, type, name, owner_id, created_at, updated_at, local_date_time,"
        " thumb_hash, is_favorite, live_photo_video_id"
        " FROM remote_asset WHERE id = ?"));
    q.addBindValue(assetId);
    if (!q.exec() || !q.next()) {
        return info;
    }

    info[QStringLiteral("id")] = q.value(0).toString();
    info[QStringLiteral("type")] = q.value(1).toString();
    info[QStringLiteral("originalFileName")] = q.value(2).toString();
    const QString ownerId = q.value(3).toString();
    info[QStringLiteral("ownerId")] = ownerId;
    info[QStringLiteral("fileCreatedAt")] = q.value(4).toString();
    info[QStringLiteral("fileModifiedAt")] = q.value(5).toString();
    info[QStringLiteral("localDateTime")] = q.value(6).toString();
    info[QStringLiteral("thumbhash")] = q.value(7).toString();
    info[QStringLiteral("isFavorite")] = q.value(8).toInt() != 0;
    info[QStringLiteral("livePhotoVideoId")] = q.value(9).toString();

    QSqlQuery uq(db->db());
    uq.prepare(QStringLiteral("SELECT id, name, email FROM sync_user WHERE id = ? UNION ALL SELECT id, name, email FROM auth_user WHERE id = ? LIMIT 1"));
    uq.addBindValue(ownerId);
    uq.addBindValue(ownerId);
    if (uq.exec() && uq.next()) {
        QJsonObject owner;
        owner[QStringLiteral("id")] = uq.value(0).toString();
        owner[QStringLiteral("name")] = uq.value(1).toString();
        owner[QStringLiteral("email")] = uq.value(2).toString();
        info[QStringLiteral("owner")] = owner;
    }

    // EXIF
    QSqlQuery eq(db->db());
    eq.prepare(QStringLiteral(
        "SELECT description, exif_image_width, exif_image_height, file_size, latitude, longitude,"
        " city, country, make, model, f_number, focal_length, iso, exposure_time"
        " FROM remote_asset_exif WHERE asset_id = ?"));
    eq.addBindValue(assetId);
    if (eq.exec() && eq.next()) {
        QJsonObject exif;
        exif[QStringLiteral("description")] = eq.value(0).toString();
        if (!eq.value(1).isNull()) exif[QStringLiteral("exifImageWidth")] = eq.value(1).toInt();
        if (!eq.value(2).isNull()) exif[QStringLiteral("exifImageHeight")] = eq.value(2).toInt();
        if (!eq.value(3).isNull()) exif[QStringLiteral("fileSizeInByte")] = eq.value(3).toLongLong();
        if (!eq.value(4).isNull()) exif[QStringLiteral("latitude")] = eq.value(4).toDouble();
        if (!eq.value(5).isNull()) exif[QStringLiteral("longitude")] = eq.value(5).toDouble();
        exif[QStringLiteral("city")] = eq.value(6).toString();
        exif[QStringLiteral("country")] = eq.value(7).toString();
        exif[QStringLiteral("make")] = eq.value(8).toString();
        exif[QStringLiteral("model")] = eq.value(9).toString();
        if (!eq.value(10).isNull()) exif[QStringLiteral("fNumber")] = eq.value(10).toDouble();
        if (!eq.value(11).isNull()) exif[QStringLiteral("focalLength")] = eq.value(11).toDouble();
        if (!eq.value(12).isNull()) exif[QStringLiteral("iso")] = eq.value(12).toInt();
        exif[QStringLiteral("exposureTime")] = eq.value(13).toString();
        info[QStringLiteral("exifInfo")] = exif;
    }

    // People
    QJsonArray people;
    QSqlQuery pq(db->db());
    pq.prepare(QStringLiteral("SELECT DISTINCT p.id, p.name FROM asset_face af JOIN person p ON af.person_id = p.id WHERE af.asset_id = ? AND af.is_visible = 1"));
    pq.addBindValue(assetId);
    if (pq.exec()) {
        while (pq.next()) {
            QJsonObject p;
            p[QStringLiteral("id")] = pq.value(0).toString();
            p[QStringLiteral("name")] = pq.value(1).toString();
            people.append(p);
        }
    }
    info[QStringLiteral("people")] = people;

    return info;
}
