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
#include "backupmanager.h"

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

   const QString serverName = QStringLiteral("harbour-immich-instance");
   {
       QLocalSocket socket;
       socket.connectToServer(serverName);
       if (socket.waitForConnected(500)) {
           if (!activationUrl.isEmpty()) {
               socket.write(activationUrl.toUtf8());
               socket.waitForBytesWritten(1000);
           }
           socket.disconnectFromServer();
           return 0;
       }
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

   QLocalServer *localServer = new QLocalServer(app);
   QLocalServer::removeServer(serverName);
   if (!localServer->listen(serverName)) {
       qWarning() << "Failed to start single instance server:" << localServer->errorString();
   }
   QObject::connect(localServer, &QLocalServer::newConnection, [localServer, oauthManager]() {
       QLocalSocket *client = localServer->nextPendingConnection();
       if (!client) return;
       QObject::connect(client, &QLocalSocket::readyRead, [client, oauthManager]() {
           QString url = QString::fromUtf8(client->readAll());
           if (!url.isEmpty()) {
               oauthManager->handleCallbackUrl(url);
           }
           client->deleteLater();
       });
       QObject::connect(client, &QLocalSocket::disconnected, client, &QLocalSocket::deleteLater);
   });

   if (!activationUrl.isEmpty()) {
       QTimer::singleShot(0, [oauthManager, activationUrl]() {
           oauthManager->handleCallbackUrl(activationUrl);
       });
   }
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
   view->rootContext()->setContextProperty("backupManager", backupManager);

   view->setSource(SailfishApp::pathTo("qml/harbour-immich.qml"));
   view->show();

   return app->exec();
}
