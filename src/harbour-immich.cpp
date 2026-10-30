#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTranslator>
#include <QLocalServer>
#include <QLocalSocket>
#include <QTimer>
#include <QDateTime>
#include <QElapsedTimer>
#include <QJsonArray>
#include <QLocale>
#ifndef HARBOUR_BUILD
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusMessage>
#endif
#include <QtQml>
#include "authmanager.h"
#include "oauthmanager.h"
#ifndef HARBOUR_BUILD
#include "appactivationadaptor.h"
#endif
#include "immichapi.h"
#include "albummodel.h"
#include "timelinemodel.h"
#include "settingsmanager.h"
#include "securestorage.h"
#include "clientcertmanager.h"
#include "imageprovider.h"
#include "localthumbnailprovider.h"
#include "thumbhashprovider.h"
#include "logmanager.h"
#include "backupmanager.h"
#include "assetdatabase.h"
#include "syncengine.h"
#include "localmediaindex.h"
#include "memoriesmodel.h"
#include "peoplemodel.h"
#include "videocontroller.h"
#include "devicefoldermodel.h"

#ifndef HARBOUR_BUILD
static void forwardActivationUrl(const QString &serviceName, const QString &url)
{
    QStringList uris;
    if (!url.isEmpty())
        uris.append(url);

    QDBusMessage call = QDBusMessage::createMethodCall(serviceName, QStringLiteral("/mezmerize/harbour_immich"), QStringLiteral("mezmerize.harbour_immich"), QStringLiteral("openUrl"));
    call.setArguments(QVariantList() << QVariant::fromValue(uris));
    QDBusConnection::sessionBus().call(call, QDBus::Block, 1000);
}
#endif

int main(int argc, char *argv[])
{
    // Hacky way to fix video streaming issues on HTTP
    constexpr int gstPlayFlagBuffering = 0x100;
    qputenv("QT_GSTREAMER_PLAYBIN_FLAGS", QByteArray::number(qgetenv("QT_GSTREAMER_PLAYBIN_FLAGS").toInt() | gstPlayFlagBuffering));
    QGuiApplication *app = SailfishApp::application(argc, argv);
    app->setOrganizationName("mezmerize");
    app->setApplicationName("harbour-immich");

#ifndef HARBOUR_BUILD
    // Check for URL scheme activation argument (app.immich:///oauth-callback?...)
    QString activationUrl;
    for (int i = 1; i < argc; ++i) {
        QString arg = QString::fromUtf8(argv[i]);
        if (arg.startsWith(QStringLiteral("app.immich"))) {
            activationUrl = arg;
            break;
        }
    }

    const QString serviceName = QStringLiteral("mezmerize.harbour-immich");
    QDBusConnection sessionBus = QDBusConnection::sessionBus();
    if (sessionBus.isConnected() && sessionBus.interface()->isServiceRegistered(serviceName)) {
        forwardActivationUrl(serviceName, activationUrl);
        return 0;
    }
#endif

    LogManager *logManager = new LogManager(app);
    qInstallMessageHandler(LogManager::messageHandler);

    QQuickView *view = SailfishApp::createView();

    SettingsManager *settingsManager = new SettingsManager(app);

    // App locale
    const QString language = settingsManager->language();
    const QLocale appLocale = language.isEmpty() ? QLocale::system() : QLocale(language);
    QLocale::setDefault(appLocale);

    // Translator
    QTranslator *translator = new QTranslator(app);
    const QString translationsDir = SailfishApp::pathTo("translations").toLocalFile();
    if (!translator->load(appLocale, "harbour-immich", "-", translationsDir)) {
        translator->load("harbour-immich-en", translationsDir);
    }
    app->installTranslator(translator);

    SecureStorage *secureStorage = new SecureStorage(app);
    ClientCertManager *clientCertManager = new ClientCertManager(secureStorage, app);

    QObject::connect(secureStorage, &SecureStorage::initialized, clientCertManager, [clientCertManager]() {
        clientCertManager->applyStoredCertificate();
    });

    AuthManager *authManager = new AuthManager(secureStorage, app);
    QObject::connect(authManager, &AuthManager::serverUrlChanged, clientCertManager, [clientCertManager, authManager]() {
        clientCertManager->setServerUrl(authManager->serverUrl());
    });
    OAuthManager *oauthManager = new OAuthManager(authManager, app);

#ifndef HARBOUR_BUILD
    new MaemoActivationAdaptor(oauthManager);
    new FreedesktopApplicationAdaptor(oauthManager);
    if (sessionBus.isConnected()) {
        sessionBus.registerObject(QStringLiteral("/mezmerize/harbour_immich"), oauthManager, QDBusConnection::ExportAdaptors);
        if (!sessionBus.registerService(serviceName)) {
            if (sessionBus.interface()->isServiceRegistered(serviceName)) {
                forwardActivationUrl(serviceName, activationUrl);
                return 0;
            }
            qWarning() << "Failed to register D-Bus service mezmerize.harbour-immich:" << sessionBus.lastError().message();
        }
    } else {
        qWarning() << "No session bus connection, URL activation unavailable";
    }

    if (!activationUrl.isEmpty()) {
        QTimer::singleShot(0, [oauthManager, activationUrl]() {
            oauthManager->handleCallbackUrl(activationUrl);
        });
    }
#endif
    qmlRegisterType<DeviceFolderModel>("harbour.immich.models", 1, 0, "DeviceFolderModel");
    qmlRegisterType<MemoriesModel>("harbour.immich.models", 1, 0, "MemoriesModel");
    qmlRegisterType<PeopleModel>("harbour.immich.models", 1, 0, "PeopleModel");
    qmlRegisterType<TimelineModel>("harbour.immich.models", 1, 0, "TimelineModel");
    qmlRegisterType<VideoController>("harbour.immich.media", 1, 0, "VideoController");

    AssetDatabase *assetDatabase = new AssetDatabase(app);
    assetDatabase->initialize();

    ImmichApi *immichApi = new ImmichApi(authManager, app);
    AlbumModel *albumModel = new AlbumModel(authManager, app);
    TimelineModel *timelineModel = new TimelineModel(app);

    immichApi->setSettingsManager(settingsManager);

    BackupManager *backupManager = new BackupManager(authManager, settingsManager, immichApi, app);
    backupManager->initialize();

    SyncEngine *syncEngine = new SyncEngine(authManager, assetDatabase, app);
    QObject::connect(authManager, &AuthManager::loginSucceeded, syncEngine, &SyncEngine::sync);
    QObject::connect(authManager, &AuthManager::isAuthenticatedChanged, assetDatabase, [authManager, assetDatabase, albumModel]() {
        if (!authManager->isAuthenticated()) {
            assetDatabase->clearSyncedData();
            albumModel->loadAlbums(QJsonArray());
        }
    });

    LocalMediaIndex *localMediaIndex = new LocalMediaIndex(backupManager, settingsManager, assetDatabase, app);
    QObject::connect(syncEngine, &SyncEngine::syncFinished, localMediaIndex, [localMediaIndex](bool ok) {
        if (ok) {
            localMediaIndex->scan();
        }
    });
    QObject::connect(syncEngine, &SyncEngine::syncFinished, backupManager, [backupManager, assetDatabase, syncEngine, authManager](bool ok) {
        if (ok && authManager->isAuthenticated()) {
            backupManager->reconcileWithServer(assetDatabase->ownRemoteAssetIds(), syncEngine->syncStartedAtMs());
        }
    });
    QObject::connect(settingsManager, &SettingsManager::backupFoldersChanged, localMediaIndex, &LocalMediaIndex::scan);
    QObject::connect(settingsManager, &SettingsManager::showDeviceMediaOnTimelineChanged, localMediaIndex, &LocalMediaIndex::scan);
    QObject::connect(backupManager, &BackupManager::localMediaChanged, localMediaIndex, &LocalMediaIndex::scan);
    QObject::connect(immichApi, &ImmichApi::favoritesToggled, assetDatabase, [assetDatabase](const QStringList &ids, bool fav) {
        assetDatabase->patchRemoteAssets(ids, QStringLiteral("is_favorite"), fav ? 1 : 0);
    });
    QObject::connect(immichApi, &ImmichApi::assetVisibilityChanged, assetDatabase, [assetDatabase](const QStringList &ids, const QString &visibility) {
        assetDatabase->patchRemoteAssets(ids, QStringLiteral("visibility"), visibility);
    });
    QObject::connect(immichApi, &ImmichApi::assetsDeleted, assetDatabase, [assetDatabase](const QStringList &ids, bool force) {
        if (force) {
            assetDatabase->deleteRemoteAssets(ids);
        } else {
            assetDatabase->patchRemoteAssets(ids, QStringLiteral("deleted_at"), QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy-MM-dd'T'HH:mm:ss.zzz'Z'")));
        }
    });
    QObject::connect(immichApi, &ImmichApi::trashRestored, assetDatabase, [assetDatabase](const QStringList &ids) {
        assetDatabase->patchRemoteAssets(ids, QStringLiteral("deleted_at"), QVariant());
    });
    QObject::connect(immichApi, &ImmichApi::allTrashRestored, assetDatabase, [assetDatabase]() {
        assetDatabase->restoreAllTrashedRemoteAssets();
    });
    QObject::connect(immichApi, &ImmichApi::trashEmptied, assetDatabase, [assetDatabase]() {
        assetDatabase->clearTrashedRemoteAssets();
    });
    QObject::connect(immichApi, &ImmichApi::assetsAddedToAlbum, assetDatabase, [assetDatabase](const QString &albumId, const QStringList &ids) {
        assetDatabase->addAlbumAssets(albumId, ids);
    });
    QObject::connect(immichApi, &ImmichApi::assetsRemovedFromAlbum, assetDatabase, [assetDatabase](const QString &albumId, const QStringList &ids) {
        assetDatabase->removeAlbumAssets(albumId, ids);
    });
    QObject::connect(immichApi, &ImmichApi::partnerCreated, assetDatabase, [assetDatabase](const QString &userId) {
        assetDatabase->upsertPartner(assetDatabase->metaValue(QStringLiteral("current_user_id")), userId, false);
    });
    QObject::connect(immichApi, &ImmichApi::partnerRemoved, assetDatabase, [assetDatabase](const QString &userId) {
        assetDatabase->removePartner(assetDatabase->metaValue(QStringLiteral("current_user_id")), userId);
    });
    QObject::connect(immichApi, &ImmichApi::partnerUpdated, assetDatabase, [assetDatabase](const QString &userId, bool inTimeline) {
        assetDatabase->upsertPartner(userId, assetDatabase->metaValue(QStringLiteral("current_user_id")), inTimeline);
    });

    auto *resyncTimer = new QTimer(app);
    resyncTimer->setSingleShot(true);
    resyncTimer->setInterval(1500);
    auto *resyncPendingSince = new QElapsedTimer();
    QObject::connect(resyncTimer, &QTimer::timeout, syncEngine, [syncEngine, resyncPendingSince]() {
        resyncPendingSince->invalidate();
        syncEngine->sync();
    });
    auto queueResync = [resyncTimer, resyncPendingSince, syncEngine]() {
        if (!resyncPendingSince->isValid()) {
            resyncPendingSince->start();
        } else if (resyncPendingSince->elapsed() >= 10000) {
            resyncTimer->stop();
            resyncPendingSince->invalidate();
            syncEngine->sync();
            return;
        }
        resyncTimer->start();
    };
    QObject::connect(immichApi, &ImmichApi::assetsAddedToAlbum, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::assetsRemovedFromAlbum, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::albumCreated, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::albumUpdated, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::albumRemoved, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::memoryUpdated, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::uploadAllComplete, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::favoritesToggled, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::assetVisibilityChanged, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::assetsDeleted, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::trashRestored, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::allTrashRestored, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::trashEmptied, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::assetUpdated, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::personUpdated, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::partnerCreated, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::partnerRemoved, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::partnerUpdated, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::usersAddedToAlbum, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::albumUserRoleUpdated, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::albumUserRemoved, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::stackCreated, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::stackDeleted, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::clusterGroupJoined, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::clusterGroupLeft, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::clusterGroupPeopleRegenerated, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::peopleUnshared, resyncTimer, queueResync);
    QObject::connect(backupManager, &BackupManager::fileBackedUp, resyncTimer, queueResync);
    QObject::connect(immichApi, &ImmichApi::stackCreated, assetDatabase, &AssetDatabase::applyStack);
    QObject::connect(immichApi, &ImmichApi::stackDeleted, assetDatabase, &AssetDatabase::removeStack);
    QObject::connect(app, &QGuiApplication::applicationStateChanged, syncEngine, [syncEngine, localMediaIndex](Qt::ApplicationState state) {
        if (state == Qt::ApplicationActive) {
            syncEngine->sync();
            localMediaIndex->scan();
        }
    });
    QObject::connect(immichApi, &ImmichApi::assetUploaded, [backupManager](const QString &assetId, const QString &filePath, const QString &) {
        backupManager->registerManualUpload(filePath, assetId);
    });
    QObject::connect(syncEngine, &SyncEngine::remoteAssetsDeleted, backupManager, &BackupManager::handleServerDeletions);

    // Register custom image provider for authenticated image loading
    view->engine()->addImageProvider(QLatin1String("immich"), new ImmichImageProvider(authManager, settingsManager));
    view->engine()->addImageProvider(QLatin1String("thumbhash"), new ThumbhashProvider());
    view->engine()->addImageProvider(QLatin1String("localthumbnail"), new LocalThumbnailProvider());

    QObject::connect(immichApi, &ImmichApi::albumsReceived, albumModel, &AlbumModel::loadAlbums);

    // Timeline model connections
    timelineModel->setUserId(authManager->userId());
    timelineModel->setContext(QStringLiteral("timeline"));
    timelineModel->setBackupManager(backupManager);
    QObject::connect(authManager, &AuthManager::userIdChanged, [authManager, timelineModel]() {
        timelineModel->setUserId(authManager->userId());
    });

    view->rootContext()->setContextProperty("authManager", authManager);
    view->rootContext()->setContextProperty("oauthManager", oauthManager);
    view->rootContext()->setContextProperty("immichApi", immichApi);
    view->rootContext()->setContextProperty("albumModel", albumModel);
    view->rootContext()->setContextProperty("timelineModel", timelineModel);
    view->rootContext()->setContextProperty("settingsManager", settingsManager);
    view->rootContext()->setContextProperty("secureStorage", secureStorage);
    view->rootContext()->setContextProperty("clientCertManager", clientCertManager);
    view->rootContext()->setContextProperty("logManager", logManager);
    view->rootContext()->setContextProperty("backupManager", backupManager);
    view->rootContext()->setContextProperty("syncEngine", syncEngine);
    view->rootContext()->setContextProperty("assetDatabase", assetDatabase);

    view->setSource(SailfishApp::pathTo("qml/harbour-immich.qml"));
    view->show();

    secureStorage->initialize();

    return app->exec();
}
