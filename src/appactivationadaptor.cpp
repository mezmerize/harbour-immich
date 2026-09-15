#include "appactivationadaptor.h"
#include "oauthmanager.h"

static void handleActivationUris(OAuthManager *oauthManager, const QStringList &uris)
{
    bool handled = false;
    for (const QString &uri : uris) {
        if (uri.trimmed().startsWith(QStringLiteral("app.immich"))) {
            oauthManager->handleCallbackUrl(uri);
            handled = true;
        }
    }
    if (!handled) {
        oauthManager->raiseWindow();
    }
}

MaemoActivationAdaptor::MaemoActivationAdaptor(OAuthManager *oauthManager)
    : QDBusAbstractAdaptor(oauthManager)
    , m_oauthManager(oauthManager)
{
}

void MaemoActivationAdaptor::openUrl(const QStringList &uris)
{
    handleActivationUris(m_oauthManager, uris);
}

FreedesktopApplicationAdaptor::FreedesktopApplicationAdaptor(OAuthManager *oauthManager)
    : QDBusAbstractAdaptor(oauthManager)
    , m_oauthManager(oauthManager)
{
}

void FreedesktopApplicationAdaptor::Activate(const QVariantMap &platformData)
{
    Q_UNUSED(platformData)
    m_oauthManager->raiseWindow();
}

void FreedesktopApplicationAdaptor::Open(const QStringList &uris, const QVariantMap &platformData)
{
    Q_UNUSED(platformData)
    handleActivationUris(m_oauthManager, uris);
}

void FreedesktopApplicationAdaptor::ActivateAction(const QString &actionName, const QVariantList &parameter, const QVariantMap &platformData)
{
    Q_UNUSED(actionName)
    Q_UNUSED(parameter)
    Q_UNUSED(platformData)
    m_oauthManager->raiseWindow();
}
