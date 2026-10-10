#include "clientcertmanager.h"
#include "securestorage.h"
#include <QDebug>
#include <QFile>
#include <QUrl>
#include <QBuffer>
#include <QDateTime>
#include <QLocale>
#include <QList>
#include <QStringList>
#include <QSslConfiguration>
#include <QSslKey>
#include <QNetworkReply>
#include <QSslError>
#include <QSettings>

bool ClientCertManager::s_selfSignedAllowed = false;
QString ClientCertManager::s_selfSignedHost;

QNetworkReply *TlsNetworkAccessManager::createRequest(Operation op, const QNetworkRequest &request, QIODevice *outgoingData)
{
    QNetworkReply *reply = QNetworkAccessManager::createRequest(op, request, outgoingData);
    ClientCertManager::attachSelfSignedBypass(reply);
    return reply;
}

ClientCertManager::ClientCertManager(SecureStorage *storage, QObject *parent)
    : QObject(parent)
    , m_storage(storage)
    , m_hasCertificate(false)
    , m_allowSelfSigned(QSettings().value(QStringLiteral("tls/allowSelfSigned"), false).toBool())
{
    s_selfSignedAllowed = m_allowSelfSigned;
}

bool ClientCertManager::allowSelfSigned() const
{
    return m_allowSelfSigned;
}

void ClientCertManager::setAllowSelfSigned(bool allow)
{
    if (m_allowSelfSigned == allow)
        return;
    m_allowSelfSigned = allow;
    s_selfSignedAllowed = allow;
    QSettings().setValue(QStringLiteral("tls/allowSelfSigned"), allow);
    emit tlsPolicyChanged();
}

void ClientCertManager::setServerUrl(const QString &url)
{
    s_selfSignedHost = QUrl(url).host().toLower();
}

void ClientCertManager::attachSelfSignedBypass(QNetworkReply *reply)
{
    if (!s_selfSignedAllowed || s_selfSignedHost.isEmpty() || !reply)
        return;

    QObject::connect(reply, &QNetworkReply::sslErrors, reply, [reply](const QList<QSslError> &errors) {
        if (reply->url().host().compare(s_selfSignedHost, Qt::CaseInsensitive) == 0) {
            qInfo() << "ClientCertManager: Ignoring" << errors.size() << "TLS error(s) for" << s_selfSignedHost;
            reply->ignoreSslErrors(errors);
        }
    });
}

bool ClientCertManager::parsePkcs12(const QByteArray &data, const QString &password, QSslKey *keyOut, QSslCertificate *certOut, QList<QSslCertificate> *caOut) const
{
    QBuffer buffer;
    buffer.setData(data);
    if (!buffer.open(QIODevice::ReadOnly)) {
        return false;
    }

    QSslKey key;
    QSslCertificate cert;
    QList<QSslCertificate> caCerts;
    const bool ok = QSslCertificate::importPkcs12(&buffer, &key, &cert, &caCerts, password.toUtf8());
    buffer.close();

    if (!ok || cert.isNull() || key.isNull()) {
        return false;
    }
    if (keyOut) {
        *keyOut = key;
    }
    if (certOut) {
        *certOut = cert;
    }
    if (caOut) {
        *caOut = caCerts;
    }
    return true;
}

void ClientCertManager::applyToDefaultConfiguration(const QSslCertificate &cert, const QSslKey &key, const QList<QSslCertificate> &caCerts)
{
    QSslConfiguration config = QSslConfiguration::defaultConfiguration();
    config.setLocalCertificate(cert);
    config.setPrivateKey(key);

    QList<QSslCertificate> cas = config.caCertificates();
    // Drop CAs added by a previous import before merging new
    for (const QSslCertificate &ca : m_addedCaCerts) {
        cas.removeAll(ca);
    }
    m_addedCaCerts.clear();
    for (const QSslCertificate &ca : caCerts) {
        if (!cas.contains(ca)) {
            cas.append(ca);
            m_addedCaCerts.append(ca);
        }
    }
    config.setCaCertificates(cas);

    QSslConfiguration::setDefaultConfiguration(config);
    qInfo() << "ClientCertManager: Applied client certificate to default TLS configuration";
}

void ClientCertManager::clearDefaultClientCertificate()
{
    QSslConfiguration config = QSslConfiguration::defaultConfiguration();
    config.setLocalCertificate(QSslCertificate());
    config.setPrivateKey(QSslKey());
    if (!m_addedCaCerts.isEmpty()) {
        QList<QSslCertificate> cas = config.caCertificates();
        for (const QSslCertificate &ca : m_addedCaCerts) {
            cas.removeAll(ca);
        }
        m_addedCaCerts.clear();
        config.setCaCertificates(cas);
    }
    QSslConfiguration::setDefaultConfiguration(config);
    qInfo() << "ClientCertManager: Cleared client certificate from default TLS configuration";
}

void ClientCertManager::applyStoredCertificate()
{
    const QString base64 = m_storage ? m_storage->loadClientCert() : QString();
    if (base64.isEmpty()) {
        return;
    }

    const QByteArray data = QByteArray::fromBase64(base64.toUtf8());
    const QString password = m_storage->loadClientCertPassword();

    QSslKey key;
    QSslCertificate cert;
    QList<QSslCertificate> caCerts;
    if (!parsePkcs12(data, password, &key, &cert, &caCerts)) {
        qWarning() << "ClientCertManager: Failed to load stored client certificate for TLS";
        return;
    }

    applyToDefaultConfiguration(cert, key, caCerts);

    m_certificate = cert;
    m_hasCertificate = true;
    emit certificateChanged();
}

bool ClientCertManager::importCertificate(const QString &filePath, const QString &password)
{
    QString path = filePath;
    if (path.startsWith(QStringLiteral("file://"))) {
        path = QUrl(path).toLocalFile();
    }

    QFile file(path);
    if (!file.exists()) {
        emit importFailed(QStringLiteral("File not found"));
        return false;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        emit importFailed(QStringLiteral("Unable to read the selected file"));
        return false;
    }
    const QByteArray data = file.readAll();
    file.close();


    if (data.isEmpty()) {
        emit importFailed(QStringLiteral("The selected file is empty"));
        return false;
    }

    QSslKey key;
    QSslCertificate cert;
    QList<QSslCertificate> caCerts;
    if (!parsePkcs12(data, password, &key, &cert, &caCerts)) {
        emit importFailed(QStringLiteral("Invalid certificate or wrong password"));
        return false;
    }

    if (!m_storage) {
        emit importFailed(QStringLiteral("Secure storage unavailable"));
        return false;
    }

    m_storage->saveClientCert(QString::fromUtf8(data.toBase64()));
    m_storage->saveClientCertPassword(password);

    applyToDefaultConfiguration(cert, key, caCerts);

    m_certificate = cert;
    m_hasCertificate = true;
    emit certificateChanged();
    emit importSucceeded();
    qInfo() << "ClientCertManager: Imported client certificate";
    return true;
}

void ClientCertManager::removeCertificate()
{
    if (m_storage) {
        m_storage->clearClientCert();
    }
    clearDefaultClientCertificate();
    m_certificate = QSslCertificate();
    m_hasCertificate = false;
    emit certificateChanged();
    qInfo() << "ClientCertManager: Removed client certificate";
}

bool ClientCertManager::hasCertificate() const
{
    return m_hasCertificate;
}

QString ClientCertManager::subject() const
{
    if (m_certificate.isNull()) {
        return QString();
    }
    QStringList parts;
    parts << m_certificate.subjectInfo(QSslCertificate::CommonName);
    parts << m_certificate.subjectInfo(QSslCertificate::Organization);
    parts.removeAll(QString());
    return parts.join(QStringLiteral(", "));
}

QString ClientCertManager::issuer() const
{
    if (m_certificate.isNull()) {
        return QString();
    }
    QStringList parts;
    parts << m_certificate.issuerInfo(QSslCertificate::CommonName);
    parts << m_certificate.issuerInfo(QSslCertificate::Organization);
    parts.removeAll(QString());
    return parts.join(QStringLiteral(", "));
}

QString ClientCertManager::serialNumber() const
{
    if (m_certificate.isNull()) {
        return QString();
    }
    return QString::fromUtf8(m_certificate.serialNumber());
}

QString ClientCertManager::validFrom() const
{
    if (m_certificate.isNull()) {
        return QString();
    }
    return QLocale().toString(m_certificate.effectiveDate().toLocalTime(), QLocale::ShortFormat);
}

QString ClientCertManager::validUntil() const
{
    if (m_certificate.isNull()) {
        return QString();
    }
    return QLocale().toString(m_certificate.expiryDate().toLocalTime(), QLocale::ShortFormat);
}

bool ClientCertManager::isExpired() const
{
    if (m_certificate.isNull()) {
        return false;
    }
    return m_certificate.expiryDate() < QDateTime::currentDateTime();
}

int ClientCertManager::daysUntilExpiry() const
{
    if (m_certificate.isNull()) {
        return -1;
    }
    return QDateTime::currentDateTime().daysTo(m_certificate.expiryDate());
}

bool ClientCertManager::isExpiringSoon() const
{
    if (m_certificate.isNull() || isExpired()) {
        return false;
    }
    return daysUntilExpiry() <= ExpiryWarningDays;
}
