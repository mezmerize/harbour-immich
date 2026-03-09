#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTranslator>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QTimer>
#include "authmanager.h"
#include "oauthmanager.h"
#include "immichapi.h"
#include "albummodel.h"
#include "timelinemodel.h"
#include "settingsmanager.h"
#include "securestorage.h"
#include "imageprovider.h"
#include "thumbhashprovider.h"
#include "logmanager.h"

int main(int argc, char *argv[])
{
   QGuiApplication *app = SailfishApp::application(argc, argv);
   app->setOrganizationName("mezmerize");
   app->setApplicationName("harbour-immich");

   // Check for URL scheme activation argument (app.immich://oauth-callback?...)
   QString activationUrl;
   for (int i = 1; i < argc; ++i) {
       QString arg = QString::fromUtf8(argv[i]);
       if (arg.startsWith(QStringLiteral("app.immich://"))) {
           activationUrl = arg;
           break;
       }
   }

   // Single instance - if already running forward url by DBus and exit
   QDBusConnection dbus = QDBusConnection::sessionBus();
   if (!dbus.registerService(QStringLiteral("org.harbour.immich"))) {
       if (!activationUrl.isEmpty()) {
           QDBusInterface iface(QStringLiteral("org.harbour.immich"), QStringLiteral("/oauth"), QStringLiteral("local.OAuthManager"), dbus);
           iface.call(QStringLiteral("handleCallbackUrl"), activationUrl);
       }
       return 0;
   }

   LogManager *logManager = new LogManager(app);
   qInstallMessageHandler(LogManager::messageHandler);

   QQuickView *view = SailfishApp::createView();

   SettingsManager *settingsManager = new SettingsManager(app);

   // Translator
   QTranslator *translator = new QTranslator(app);
   const QString translationsDir = SailfishApp::pathTo("translations").toLocalFile();
   if (!translator->load(QLocale::system(), "harbour-immich", "-", translationsDir)) {
       translator->load("harbour-immich-en", translationsDir);
   }
   app->installTranslator(translator);
   SecureStorage *secureStorage = new SecureStorage(app);

   secureStorage->initialize();

   AuthManager *authManager = new AuthManager(secureStorage, app);
   OAuthManager *oauthManager = new OAuthManager(authManager, secureStorage, app);
   dbus.registerObject(QStringLiteral("/oauth"), oauthManager, QDBusConnection::ExportAllSlots);
   if (!activationUrl.isEmpty()) {
       QTimer::singleShot(0, [oauthManager, activationUrl]() {
           oauthManager->handleCallbackUrl(activationUrl);
       });
   }
   ImmichApi *immichApi = new ImmichApi(authManager, app);
   AlbumModel *albumModel = new AlbumModel(app);
   TimelineModel *timelineModel = new TimelineModel(app);

   immichApi->setSettingsManager(settingsManager);

   // Register custom image provider for authenticated image loading
   view->engine()->addImageProvider(QLatin1String("immich"), new ImmichImageProvider(authManager, settingsManager));
   view->engine()->addImageProvider(QLatin1String("thumbhash"), new ThumbhashProvider());

   QObject::connect(immichApi, &ImmichApi::albumsReceived, albumModel, &AlbumModel::loadAlbums);

   // Timeline model connections
   timelineModel->setServerUrl(authManager->serverUrl());
   QObject::connect(authManager, &AuthManager::serverUrlChanged, [authManager, timelineModel]() {
       timelineModel->setServerUrl(authManager->serverUrl());
   });
   QObject::connect(immichApi, &ImmichApi::timelineBucketsReceived, timelineModel, &TimelineModel::loadBuckets);
   QObject::connect(immichApi, &ImmichApi::timelineBucketReceived, timelineModel, &TimelineModel::loadBucketAssets);
   QObject::connect(immichApi, &ImmichApi::favoritesToggled, timelineModel, &TimelineModel::updateFavorites);
   QObject::connect(immichApi, &ImmichApi::assetsDeleted, timelineModel, &TimelineModel::removeAssets);
   QObject::connect(timelineModel, &TimelineModel::bucketLoadRequested, immichApi, &ImmichApi::fetchTimelineBucket);

   view->rootContext()->setContextProperty("authManager", authManager);
   view->rootContext()->setContextProperty("oauthManager", oauthManager);
   view->rootContext()->setContextProperty("immichApi", immichApi);
   view->rootContext()->setContextProperty("albumModel", albumModel);
   view->rootContext()->setContextProperty("timelineModel", timelineModel);
   view->rootContext()->setContextProperty("settingsManager", settingsManager);
   view->rootContext()->setContextProperty("secureStorage", secureStorage);
   view->rootContext()->setContextProperty("logManager", logManager);

   view->setSource(SailfishApp::pathTo("qml/harbour-immich.qml"));
   view->show();

   return app->exec();
}
