#ifndef APPACTIVATIONADAPTOR_H
#define APPACTIVATIONADAPTOR_H

#include <QDBusAbstractAdaptor>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class OAuthManager;

class MaemoActivationAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "mezmerize.harbour_immich")

public:
    explicit MaemoActivationAdaptor(OAuthManager *oauthManager);

public slots:
    void openUrl(const QStringList &uris);

private:
    OAuthManager *m_oauthManager;
};

class FreedesktopApplicationAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Application");

public:
    explicit FreedesktopApplicationAdaptor(OAuthManager *oauthManager);

public slots:
    void Activate(const QVariantMap &platformData);
    void Open(const QStringList &uris, const QVariantMap &platformData);
    void ActivateAction(const QString &actionName, const QVariantList &parameter, const QVariantMap &platformData);

private:
    OAuthManager *m_oauthManager;
};

#endif // APPACTIVATIONADAPTOR_H
