#include "securestorage.h"
#include <QDebug>
#include <QEventLoop>
#include <QSettings>

using namespace Sailfish::Secrets;

static const QString COLLECTION_NAME = QStringLiteral("immich");

SecureStorage::SecureStorage(QObject *parent)
   : QObject(parent)
   , m_collectionName(COLLECTION_NAME)
   , m_initialized(false)
   , m_cacheLoaded(false)
{
}

void SecureStorage::initialize()
{
   ensureCollection();
}

void SecureStorage::ensureCollection()
{
   CreateCollectionRequest *request = new CreateCollectionRequest(this);
   request->setManager(&m_secretManager);
   request->setCollectionName(m_collectionName);
   request->setAccessControlMode(SecretManager::OwnerOnlyMode);
   request->setCollectionLockType(CreateCollectionRequest::DeviceLock);
   request->setDeviceLockUnlockSemantic(SecretManager::DeviceLockKeepUnlocked);
   request->setStoragePluginName(SecretManager::DefaultEncryptedStoragePluginName);
   request->setEncryptionPluginName(SecretManager::DefaultEncryptedStoragePluginName);

   connect(request, &CreateCollectionRequest::statusChanged, this, [this, request]() {
       if (request->status() == Request::Finished) {
           if (request->result().code() == Result::Succeeded ||
               request->result().errorCode() == Result::CollectionAlreadyExistsError) {
               m_initialized = true;
               // Load cached credentials
               m_cachedServerUrl = getSecret(QStringLiteral("serverUrl"));
               m_cachedAccessToken = getSecret(QStringLiteral("accessToken"));
               m_cachedEmail = getSecret(QStringLiteral("email"));
               m_cachedPassword = getSecret(QStringLiteral("password"));
               m_cacheLoaded = true;
               emit initialized();
           } else {
               qWarning() << "Failed to create secrets collection:" << request->result().errorMessage();
               emit error(request->result().errorMessage());
           }
           request->deleteLater();
       }
   });

   request->startRequest();
}

void SecureStorage::storeSecret(const QString &name, const QString &value)
{
   // First delete any existing secret with this name (to allow updates)
   DeleteSecretRequest *deleteRequest = new DeleteSecretRequest(this);
   deleteRequest->setManager(&m_secretManager);
   deleteRequest->setIdentifier(Secret::Identifier(
       name,
       m_collectionName,
       SecretManager::DefaultEncryptedStoragePluginName));
   deleteRequest->setUserInteractionMode(SecretManager::SystemInteraction);

   connect(deleteRequest, &DeleteSecretRequest::statusChanged, this, [this, deleteRequest, name, value]() {
       if (deleteRequest->status() == Request::Finished) {
           deleteRequest->deleteLater();

           // Now store the new secret
           Secret secret(Secret::Identifier(
               name,
               m_collectionName,
               SecretManager::DefaultEncryptedStoragePluginName));
           secret.setData(value.toUtf8());
           secret.setType(Secret::TypeBlob);

           StoreSecretRequest *storeRequest = new StoreSecretRequest(this);
           storeRequest->setManager(&m_secretManager);
           storeRequest->setSecretStorageType(StoreSecretRequest::CollectionSecret);
           storeRequest->setUserInteractionMode(SecretManager::SystemInteraction);
           storeRequest->setSecret(secret);

           connect(storeRequest, &StoreSecretRequest::statusChanged, this, [storeRequest, name]() {
               if (storeRequest->status() == Request::Finished) {
                   if (storeRequest->result().code() != Result::Succeeded) {
                       qWarning() << "Failed to store secret" << name << ":" << storeRequest->result().errorMessage();
                   }
                   storeRequest->deleteLater();
               }
           });

           storeRequest->startRequest();
       }
   });

   deleteRequest->startRequest();
}

QString SecureStorage::getSecret(const QString &name) const
{
   StoredSecretRequest request;
   request.setManager(const_cast<SecretManager*>(&m_secretManager));
   request.setIdentifier(Secret::Identifier(
       name,
       m_collectionName,
       SecretManager::DefaultEncryptedStoragePluginName));
   request.setUserInteractionMode(SecretManager::SystemInteraction);

   // Use event loop for synchronous retrieval
   QEventLoop loop;
   QObject::connect(&request, &StoredSecretRequest::statusChanged, &loop, [&loop, &request]() {
       if (request.status() == Request::Finished) {
           loop.quit();
       }
   });

   request.startRequest();

   if (request.status() != Request::Finished) {
       loop.exec();
   }

   if (request.result().code() == Result::Succeeded) {
       return QString::fromUtf8(request.secret().data());
   }

   return QString();
}

void SecureStorage::deleteSecret(const QString &name)
{
   DeleteSecretRequest *request = new DeleteSecretRequest(this);
   request->setManager(&m_secretManager);
   request->setIdentifier(Secret::Identifier(
       name,
       m_collectionName,
       SecretManager::DefaultEncryptedStoragePluginName));
   request->setUserInteractionMode(SecretManager::SystemInteraction);

   connect(request, &DeleteSecretRequest::statusChanged, this, [request]() {
       if (request->status() == Request::Finished) {
           request->deleteLater();
       }
   });

   request->startRequest();
}

void SecureStorage::saveServerUrl(const QString &url)
{
   m_cachedServerUrl = url;
   storeSecret(QStringLiteral("serverUrl"), url);
}

QString SecureStorage::loadServerUrl() const
{
   if (m_cacheLoaded) {
       return m_cachedServerUrl;
   }
   return getSecret(QStringLiteral("serverUrl"));
}

void SecureStorage::saveAccessToken(const QString &token)
{
   m_cachedAccessToken = token;
   storeSecret(QStringLiteral("accessToken"), token);
}

QString SecureStorage::loadAccessToken() const
{
   if (m_cacheLoaded) {
       return m_cachedAccessToken;
   }
   return getSecret(QStringLiteral("accessToken"));
}

void SecureStorage::saveEmail(const QString &email)
{
   m_cachedEmail = email;
   storeSecret(QStringLiteral("email"), email);
}

QString SecureStorage::loadEmail() const
{
   if (m_cacheLoaded) {
       return m_cachedEmail;
   }
   return getSecret(QStringLiteral("email"));
}

void SecureStorage::savePassword(const QString &password)
{
   m_cachedPassword = password;
   storeSecret(QStringLiteral("password"), password);
}

QString SecureStorage::loadPassword() const
{
   if (m_cacheLoaded) {
       return m_cachedPassword;
   }
   return getSecret(QStringLiteral("password"));
}

void SecureStorage::clearAll()
{
   m_cachedServerUrl.clear();
   m_cachedAccessToken.clear();
   m_cachedEmail.clear();
   m_cachedPassword.clear();

   // Delete secrets
   deleteSecret(QStringLiteral("serverUrl"));
   deleteSecret(QStringLiteral("accessToken"));
   deleteSecret(QStringLiteral("email"));
   deleteSecret(QStringLiteral("password"));
}
