#include "thumbhashprovider.h"
#include <QtMath>
#include <QDebug>
#include <QVector>

// Decodes a ThumbHash byte array into a QImage (RGBA).
// Based on the reference implementation: https://github.com/evanw/thumbhash
QImage thumbHashToQImage(const QByteArray &hashBytes)
{
   if (hashBytes.size() < 5)
       return QImage();

   const quint8 *hash = reinterpret_cast<const quint8 *>(hashBytes.constData());

   // Read the constants
   quint32 header24 = hash[0] | (hash[1] << 8) | (hash[2] << 16);
   quint16 header16 = hash[3] | (hash[4] << 8);

   qreal l_dc = (header24 & 63) / 63.0;
   qreal p_dc = ((header24 >> 6) & 63) / 31.5 - 1.0;
   qreal q_dc = ((header24 >> 12) & 63) / 31.5 - 1.0;
   qreal l_scale = ((header24 >> 18) & 31) / 31.0;
   int hasAlpha = header24 >> 23;
   qreal p_scale = ((header16 >> 3) & 63) / 63.0;
   qreal q_scale = ((header16 >> 9) & 63) / 63.0;
   int isLandscape = header16 >> 15;

   int lx = qMax(3, isLandscape ? (hasAlpha ? 5 : 7) : (header16 & 7));
   int ly = qMax(3, isLandscape ? (header16 & 7) : (hasAlpha ? 5 : 7));

   qreal a_dc = 1.0, a_scale = 0.0;
   if (hasAlpha) {
       if (hashBytes.size() < 6)
           return QImage();
       a_dc = (hash[5] & 15) / 15.0;
       a_scale = (hash[5] >> 4) / 15.0;
   }

   // Read the varying factors (boost saturation by 1.25x to compensate for quantization)
   int ac_start = hasAlpha ? 6 : 5;
   int ac_index = 0;

   auto decodeChannel = [&](int nx, int ny, qreal scale) -> QVector<qreal> {
       QVector<qreal> ac;
       for (int cy = 0; cy < ny; cy++) {
           for (int cx = cy ? 0 : 1; cx * ny < nx * (ny - cy); cx++) {
               int byteIdx = ac_start + (ac_index >> 1);
               if (byteIdx >= hashBytes.size()) {
                   ac.append(0);
               } else {
                   qreal val = (((hash[byteIdx] >> ((ac_index & 1) << 2)) & 15) / 7.5 - 1.0) * scale;
                   ac.append(val);
               }
               ac_index++;
           }
       }
       return ac;
   };

   QVector<qreal> l_ac = decodeChannel(lx, ly, l_scale);
   QVector<qreal> p_ac = decodeChannel(3, 3, p_scale * 1.25);
   QVector<qreal> q_ac = decodeChannel(3, 3, q_scale * 1.25);
   QVector<qreal> a_ac;
   if (hasAlpha) {
       a_ac = decodeChannel(5, 5, a_scale);
   }

   // Compute approximate aspect ratio and output dimensions
   qreal ratio = (qreal)lx / (qreal)ly;
   int w = qRound(ratio > 1.0 ? 32.0 : 32.0 * ratio);
   int h = qRound(ratio > 1.0 ? 32.0 / ratio : 32.0);
   if (w < 1) w = 1;
   if (h < 1) h = 1;

   QImage image(w, h, QImage::Format_ARGB32);
   QVector<qreal> fx(qMax(lx, hasAlpha ? 5 : 3));
   QVector<qreal> fy(qMax(ly, hasAlpha ? 5 : 3));

   for (int y = 0; y < h; y++) {
       for (int x = 0; x < w; x++) {
           qreal l = l_dc, p = p_dc, q = q_dc, a = a_dc;

           // Precompute the cosine coefficients
           for (int cx = 0; cx < fx.size(); cx++)
               fx[cx] = qCos(M_PI / w * (x + 0.5) * cx);
           for (int cy = 0; cy < fy.size(); cy++)
               fy[cy] = qCos(M_PI / h * (y + 0.5) * cy);

           // Decode L
           for (int cy = 0, j = 0; cy < ly; cy++)
               for (int cx = cy ? 0 : 1; cx * ly < lx * (ly - cy); cx++, j++)
                   l += l_ac[j] * fx[cx] * fy[cy] * 2.0;

           // Decode P and Q
           for (int cy = 0, j = 0; cy < 3; cy++) {
               for (int cx = cy ? 0 : 1; cx < 3 - cy; cx++, j++) {
                   qreal f = fx[cx] * fy[cy] * 2.0;
                   p += p_ac[j] * f;
                   q += q_ac[j] * f;
               }
           }

           // Decode A
           if (hasAlpha) {
               for (int cy = 0, j = 0; cy < 5; cy++)
                   for (int cx = cy ? 0 : 1; cx < 5 - cy; cx++, j++)
                       a += a_ac[j] * fx[cx] * fy[cy] * 2.0;
           }

           // Convert from LPQA to RGB
           qreal b_val = l - 2.0 / 3.0 * p;
           qreal r_val = (3.0 * l - b_val + q) / 2.0;
           qreal g_val = r_val - q;

           int ri = qMax(0, qMin(255, qRound(r_val * 255.0)));
           int gi = qMax(0, qMin(255, qRound(g_val * 255.0)));
           int bi = qMax(0, qMin(255, qRound(b_val * 255.0)));
           int ai = qMax(0, qMin(255, qRound(a * 255.0)));

           image.setPixel(x, y, qRgba(ri, gi, bi, ai));
       }
   }

   return image;
}

ThumbhashProvider::ThumbhashProvider()
   : QQuickImageProvider(QQuickImageProvider::Image)
{
}

QImage ThumbhashProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
   // The id is a base64-encoded thumbhash string
   QByteArray hashBytes = QByteArray::fromBase64(id.toLatin1());
   QImage image = thumbHashToQImage(hashBytes);

   if (image.isNull()) {
       if (size) *size = QSize(0, 0);
       return QImage();
   }

   if (size) *size = image.size();

   // Scale up to requested size if specified (for sharper rendering in QML)
   if (requestedSize.isValid() && requestedSize.width() > 0 && requestedSize.height() > 0) {
       image = image.scaled(requestedSize, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
   }

   return image;
}
