#ifndef LOGMANAGER_H
#define LOGMANAGER_H

#include <QObject>
#include <QStringList>
#include <QMutex>
#include <QDateTime>
#include <QFile>
#include <QTimer>

class LogManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList logs READ logs NOTIFY logsChanged)
    Q_PROPERTY(int count READ count NOTIFY logsChanged)

public:
    static LogManager *instance();
    explicit LogManager(QObject *parent = nullptr);

    QStringList logs() const;
    int count() const;

    Q_INVOKABLE void clear();
    Q_INVOKABLE QString logFilePath() const;
    Q_INVOKABLE QString previousLogContents() const;

    void addEntry(const QString &entry);

    static void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg);

signals:
    void logsChanged();

private:
    void initLogFile();

    static LogManager *s_instance;
    QStringList m_logs;
    mutable QMutex m_mutex;
    int m_maxEntries;
    QFile m_logFile;
    QString m_logFilePath;
    QString m_previousLogPath;
    QTimer m_emitTimer;
    bool m_pendingEmit;
};

#endif
