#ifndef THUMBHASHPROVIDER_H
#define THUMBHASHPROVIDER_H

#include <QQuickImageProvider>
#include <QImage>

QImage thumbHashToQImage(const QByteArray &hashBytes);

class ThumbhashProvider : public QQuickImageProvider
{
public:
   ThumbhashProvider();
   QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};

#endif
