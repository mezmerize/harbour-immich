#ifndef VIDEOCONTROLLER_H
#define VIDEOCONTROLLER_H

#include <QObject>
#include <QString>
#include <QPointer>
#include <QMediaPlayer>

class AuthManager;

class VideoController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject* player READ player CONSTANT)
    Q_PROPERTY(QObject* mediaObject READ mediaObject CONSTANT)
    Q_PROPERTY(QObject* authManager READ authManager WRITE setAuthManager NOTIFY authManagerChanged)
    Q_PROPERTY(int playbackState READ playbackState NOTIFY playbackStateChanged)
    Q_PROPERTY(int mediaStatus READ mediaStatus NOTIFY mediaStatusChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(int error READ error NOTIFY errorChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorChanged)
    Q_PROPERTY(bool failed READ failed NOTIFY failedChanged)

public:
    enum PlaybackState {
        StoppedState = QMediaPlayer::StoppedState,
        PlayingState = QMediaPlayer::PlayingState,
        PausedState = QMediaPlayer::PausedState
    };
    Q_ENUM(PlaybackState)

    enum MediaStatus {
        UnknownStatus = QMediaPlayer::UnknownMediaStatus,
        NoMedia = QMediaPlayer::NoMedia,
        Loading = QMediaPlayer::LoadingMedia,
        Loaded = QMediaPlayer::LoadedMedia,
        Stalled = QMediaPlayer::StalledMedia,
        Buffering = QMediaPlayer::BufferingMedia,
        Buffered = QMediaPlayer::BufferedMedia,
        EndOfMedia = QMediaPlayer::EndOfMedia,
        InvalidMedia = QMediaPlayer::InvalidMedia
    };
    Q_ENUM(MediaStatus)

    enum Error {
        NoError = QMediaPlayer::NoError
    };
    Q_ENUM(Error)

    explicit VideoController(QObject *parent = nullptr);

    QObject* player() const;
    QObject* mediaObject() const;

    QObject* authManager() const;
    void setAuthManager(QObject *authManager);

    int playbackState() const;
    int mediaStatus() const;
    qint64 position() const;
    qint64 duration() const;
    bool seekable() const;
    int error() const;
    QString errorString() const;
    bool failed() const;

    Q_INVOKABLE void load(const QString &assetId);
    Q_INVOKABLE void loadLocalFile(const QString &filePath);
    Q_INVOKABLE void unload();
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(qint64 position);

signals:
    void authManagerChanged();
    void playbackStateChanged();
    void mediaStatusChanged();
    void positionChanged();
    void durationChanged();
    void seekableChanged();
    void errorChanged();
    void failedChanged();
    void loaded();

private slots:
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);
    void onStateChanged(QMediaPlayer::State state);
    void onError(QMediaPlayer::Error error);

private:
    void applyPendingSource();
    void setFailed(bool failed);

    QMediaPlayer *m_player;
    QPointer<AuthManager> m_authManager;

    QString m_assetId;
    QString m_localPath;
    bool m_autoPlay;
    bool m_sourcePending;
    bool m_loadedEmitted;
    bool m_failed;
    bool m_suppressErrors;
    int m_retryCount;
    int m_loadGeneration;
    qint64 m_retryPosition;
};

#endif // VIDEOCONTROLLER_H
