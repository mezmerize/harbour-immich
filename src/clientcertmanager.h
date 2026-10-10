#ifndef CLIENTCERTMANAGER_H
#define CLIENTCERTMANAGER_H

#include <QObject>
#include <QString>
#include <QList>
#include <QSslCertificate>
#include <QSslKey>
#include <QNetworkAccessManager>

class SecureStorage;

class TlsNetworkAccessManager : public QNetworkAccessManager
{
public:
    using QNetworkAccessManager::QNetworkAccessManager;

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request, QIODevice *outgoingData = nullptr) override;
};

class ClientCertManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasCertificate READ hasCertificate NOTIFY certificateChanged)
    Q_PROPERTY(QString subject READ subject NOTIFY certificateChanged)
    Q_PROPERTY(QString issuer READ issuer NOTIFY certificateChanged)
    Q_PROPERTY(QString serialNumber READ serialNumber NOTIFY certificateChanged)
    Q_PROPERTY(QString validFrom READ validFrom NOTIFY certificateChanged)
    Q_PROPERTY(QString validUntil READ validUntil NOTIFY certificateChanged)
    Q_PROPERTY(bool isExpired READ isExpired NOTIFY certificateChanged)
    Q_PROPERTY(bool isExpiringSoon READ isExpiringSoon NOTIFY certificateChanged)
    Q_PROPERTY(int daysUntilExpiry READ daysUntilExpiry NOTIFY certificateChanged)
    Q_PROPERTY(bool allowSelfSigned READ allowSelfSigned WRITE setAllowSelfSigned NOTIFY tlsPolicyChanged)

public:
    explicit ClientCertManager(SecureStorage *storage, QObject *parent = nullptr);

    bool allowSelfSigned() const;
    void setAllowSelfSigned(bool allow);
    void setServerUrl(const QString &url);
    static void attachSelfSignedBypass(QNetworkReply *reply);

    Q_INVOKABLE bool importCertificate(const QString &filePath, const QString &password);

    bool hasCertificate() const;
    QString subject() const;
    QString issuer() const;
    QString serialNumber() const;
    QString validFrom() const;
    QString validUntil() const;
    bool isExpired() const;
    bool isExpiringSoon() const;
    int daysUntilExpiry() const;

    Q_INVOKABLE void removeCertificate();
    Q_INVOKABLE void applyStoredCertificate();

    static const int ExpiryWarningDays = 30;

signals:
    void certificateChanged();
    void importSucceeded();
    void importFailed(const QString &reason);
    void tlsPolicyChanged();

private:
    bool parsePkcs12(const QByteArray &data, const QString &password, QSslKey *keyOut, QSslCertificate *certOut, QList<QSslCertificate> *caOut) const;
    void applyToDefaultConfiguration(const QSslCertificate &cert, const QSslKey &key, const QList<QSslCertificate> &caCerts);
    void clearDefaultClientCertificate();

    static bool s_selfSignedAllowed;
    static QString s_selfSignedHost;

    SecureStorage *m_storage;
    QSslCertificate m_certificate;
    QList<QSslCertificate> m_addedCaCerts;
    bool m_hasCertificate;
    bool m_allowSelfSigned;
};

#endif // CLIENTCERTMANAGER_H
