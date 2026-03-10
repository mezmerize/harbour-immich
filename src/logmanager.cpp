#include "logmanager.h"
#include <QMutexLocker>
#include <QStandardPaths>
#include <QDir>
#include <QTextStream>

LogManager *LogManager::s_instance = nullptr;

LogManager *LogManager::instance()
{
    return s_instance;
}

LogManager::LogManager(QObject *parent)
    : QObject(parent)
    , m_maxEntries(1000)
    , m_pendingEmit(false)
{
    s_instance = this;
    m_emitTimer.setSingleShot(true);
    m_emitTimer.setInterval(100);
    connect(&m_emitTimer, &QTimer::timeout, this, [this]() {
        m_pendingEmit = false;
        emit logsChanged();
    });
    initLogFile();
}

void LogManager::initLogFile()
{
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataDir);

    m_logFilePath = dataDir + QStringLiteral("/current.log");
    m_previousLogPath = dataDir + QStringLiteral("/previous.log");

    // Rotate current.log to previous.log
    if (QFile::exists(m_logFilePath)) {
        QFile::remove(m_previousLogPath);
        QFile::rename(m_logFilePath, m_previousLogPath);
    }

    m_logFile.setFileName(m_logFilePath);
    m_logFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
}

QStringList LogManager::logs() const
{
    QMutexLocker locker(&m_mutex);
    return m_logs;
}

int LogManager::count() const
{
    QMutexLocker locker(&m_mutex);
    return m_logs.size();
}

void LogManager::clear()
{
    {
        QMutexLocker locker(&m_mutex);
        m_logs.clear();
    }
    m_emitTimer.stop();
    m_pendingEmit = false;
    emit logsChanged();
}

void LogManager::addEntry(const QString &entry)
{
    {
        QMutexLocker locker(&m_mutex);
        m_logs.append(entry);
        while (m_logs.size() > m_maxEntries) {
            m_logs.removeFirst();
        }
        // Write to file immediately
        if (m_logFile.isOpen()) {
            QTextStream stream (&m_logFile);
            stream << entry << "\n";
            stream.flush();
        }
    }
    // Throttle notifications
    if (!m_pendingEmit) {
        m_pendingEmit = true;
        m_emitTimer.start();
    }
}

QString LogManager::logFilePath() const
{
    return m_logFilePath;
}

QString LogManager::previousLogContents() const
{
    QFile file(m_previousLogPath);
    if (!file.exists() || !file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }
    return QString::fromUtf8(file.readAll());
}

void LogManager::messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    Q_UNUSED(context)

    QString level;
    switch (type) {
    case QtDebugMsg:    level = QStringLiteral("DBG"); break;
    case QtInfoMsg:     level = QStringLiteral("INF"); break;
    case QtWarningMsg:  level = QStringLiteral("WRN"); break;
    case QtCriticalMsg: level = QStringLiteral("ERR"); break;
    case QtFatalMsg:    level = QStringLiteral("FTL"); break;
    }

    QString timestamp = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz"));
    QString entry = QStringLiteral("[%1] %2: %3").arg(timestamp, level, msg);

#ifndef QT_NO_DEBUG_OUTPUT
    // Also print to stderr for development
    fprintf(stderr, "%s\n", entry.toLocal8Bit().constData());
#endif

    if (s_instance) {
        s_instance->addEntry(entry);
    }
}
