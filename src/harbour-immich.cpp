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
#include "imageprovider.h"
#include "thumbhashprovider.h"
#include "logmanager.h"
#include "backupmanager.h"
#include "memoriesmodel.h"
#include "peoplemodel.h"
#include "videocontroller.h"

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


    AuthManager *authManager = new AuthManager(secureStorage, app);
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
    qmlRegisterType<MemoriesModel>("harbour.immich.models", 1, 0, "MemoriesModel");
    qmlRegisterType<PeopleModel>("harbour.immich.models", 1, 0, "PeopleModel");
    qmlRegisterType<TimelineModel>("harbour.immich.models", 1, 0, "TimelineModel");
    qmlRegisterType<VideoController>("harbour.immich.media", 1, 0, "VideoController");
    ImmichApi *immichApi = new ImmichApi(authManager, app);
    AlbumModel *albumModel = new AlbumModel(authManager, app);
    TimelineModel *timelineModel = new TimelineModel(app);

    immichApi->setSettingsManager(settingsManager);

    BackupManager *backupManager = new BackupManager(authManager, settingsManager, immichApi, app);
    backupManager->initialize();

    // Connect manual upload to backup tracking
    QObject::connect(immichApi, &ImmichApi::assetUploaded, [backupManager](const QString &assetId, const QString &filePath, const QString &status) {
        Q_UNUSED(status)
        backupManager->registerManualUpload(filePath, assetId);
    });

    // Connect asset deletion to backup state
    QObject::connect(immichApi, &ImmichApi::assetsDeleted, [backupManager](const QStringList &assetIds) {
        for (const QString &id : assetIds) {
            backupManager->handleServerDeletion(id);
        }
    });

    // Register custom image provider for authenticated image loading
    view->engine()->addImageProvider(QLatin1String("immich"), new ImmichImageProvider(authManager, settingsManager));
    view->engine()->addImageProvider(QLatin1String("thumbhash"), new ThumbhashProvider());

    QObject::connect(immichApi, &ImmichApi::albumsReceived, albumModel, &AlbumModel::loadAlbums);

    // Timeline model connections
    timelineModel->setServerUrl(authManager->serverUrl());
    timelineModel->setUserId(authManager->userId());
    timelineModel->setApi(immichApi);
    timelineModel->setContext(QStringLiteral("timeline"));
    QObject::connect(authManager, &AuthManager::serverUrlChanged, [authManager, timelineModel]() {
        timelineModel->setServerUrl(authManager->serverUrl());
    });
    QObject::connect(authManager, &AuthManager::userIdChanged, [authManager, timelineModel]() {
        timelineModel->setUserId(authManager->userId());
    });
    QObject::connect(immichApi, &ImmichApi::favoritesToggled, timelineModel, &TimelineModel::updateFavorites);
    QObject::connect(immichApi, &ImmichApi::assetsDeleted, timelineModel, &TimelineModel::removeAssets);

    view->rootContext()->setContextProperty("authManager", authManager);
    view->rootContext()->setContextProperty("oauthManager", oauthManager);
    view->rootContext()->setContextProperty("immichApi", immichApi);
    view->rootContext()->setContextProperty("albumModel", albumModel);
    view->rootContext()->setContextProperty("timelineModel", timelineModel);
    view->rootContext()->setContextProperty("settingsManager", settingsManager);
    view->rootContext()->setContextProperty("secureStorage", secureStorage);
    view->rootContext()->setContextProperty("logManager", logManager);
    view->rootContext()->setContextProperty("backupManager", backupManager);

    view->setSource(SailfishApp::pathTo("qml/harbour-immich.qml"));
    view->show();

    secureStorage->initialize();

    return app->exec();
}
