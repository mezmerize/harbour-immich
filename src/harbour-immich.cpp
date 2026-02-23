#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTranslator>
#include "authmanager.h"
#include "oauthmanager.h"
#include "immichapi.h"
#include "albummodel.h"
#include "timelinemodel.h"
#include "settingsmanager.h"
#include "securestorage.h"
#include "imageprovider.h"
#include "thumbhashprovider.h"

int main(int argc, char *argv[])
{
   QGuiApplication *app = SailfishApp::application(argc, argv);
   app->setOrganizationName("mezmerize");
   app->setApplicationName("harbour-immich");

   // Translator
   const auto translator = new QTranslator(app);
   const QString translationsDir = SailfishApp::pathTo("translations").toLocalFile();
   if (!translator->load(QLocale::system(), "harbour-immich", "-", translationsDir)) {
       translator->load("harbour-immich-en", translationsDir);
   }
   app->installTranslator(translator);

   QQuickView *view = SailfishApp::createView();

   SettingsManager *settingsManager = new SettingsManager(app);
   SecureStorage *secureStorage = new SecureStorage(app);

   secureStorage->initialize();

   AuthManager *authManager = new AuthManager(secureStorage, app);
   OAuthManager *oauthManager = new OAuthManager(authManager, secureStorage, app);
   ImmichApi *immichApi = new ImmichApi(authManager, app);
   AlbumModel *albumModel = new AlbumModel(app);
   TimelineModel *timelineModel = new TimelineModel(app);

   // Set settings manager for thumbnail quality
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

   view->setSource(SailfishApp::pathTo("qml/harbour-immich.qml"));
   view->show();

   return app->exec();
}
