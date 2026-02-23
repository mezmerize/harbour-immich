#ifndef SECURESTORAGE_H
#define SECURESTORAGE_H

#include <QObject>
#include <QString>
#include <Sailfish/Secrets/secretmanager.h>
#include <Sailfish/Secrets/createcollectionrequest.h>
#include <Sailfish/Secrets/storedsecretrequest.h>
#include <Sailfish/Secrets/storesecretrequest.h>
#include <Sailfish/Secrets/deletesecretrequest.h>
#include <Sailfish/Secrets/result.h>
#include <Sailfish/Secrets/secret.h>

class SecureStorage : public QObject
{
   Q_OBJECT

public:
   explicit SecureStorage(QObject *parent = nullptr);

   Q_INVOKABLE void saveServerUrl(const QString &url);
   Q_INVOKABLE QString loadServerUrl() const;

   Q_INVOKABLE void saveAccessToken(const QString &token);
   Q_INVOKABLE QString loadAccessToken() const;

   Q_INVOKABLE void saveEmail(const QString &email);
   Q_INVOKABLE QString loadEmail() const;

   Q_INVOKABLE void savePassword(const QString &password);
   Q_INVOKABLE QString loadPassword() const;

   Q_INVOKABLE void clearAll();

   Q_INVOKABLE void initialize();

signals:
   void initialized();
   void error(const QString &message);

private:
   void ensureCollection();
   void storeSecret(const QString &name, const QString &value);
   QString getSecret(const QString &name) const;
   void deleteSecret(const QString &name);

   Sailfish::Secrets::SecretManager m_secretManager;
   QString m_collectionName;
   bool m_initialized;

   // Cache for synchronous access (loaded at init)
   mutable QString m_cachedServerUrl;
   mutable QString m_cachedAccessToken;
   mutable QString m_cachedEmail;
   mutable QString m_cachedPassword;
   mutable bool m_cacheLoaded;
};

#endif
