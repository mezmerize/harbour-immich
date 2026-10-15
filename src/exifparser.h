#ifndef EXIFPARSER_H
#define EXIFPARSER_H

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <string>
#include <set>

struct ExifData {
    int orientation = 0;
    std::string make;
    std::string model;
    std::string description;
    std::string dateTimeOriginal;
    std::string offsetTimeOriginal;
    std::string lensModel;
    double fNumber = 0;
    double focalLength = 0;
    double exposureTime = 0;
    int iso = 0;
    bool hasGps = false;
    double latitude = 0;
    double longitude = 0;
    int pixelX = 0;
    int pixelY = 0;
};

namespace exifparser_detail {

struct TiffView {
    const unsigned char *d;
    size_t n;
    bool le;

    bool u16(size_t off, uint16_t &v) const
    {
        if (off > n || n - off < 2) return false;
        if (le) {
            v = static_cast<uint16_t>(d[off] | (d[off + 1] << 8));
        } else {
            v = static_cast<uint16_t>((d[off] << 8) | d[off + 1]);
        }
        return true;
    }

    bool u32(size_t off, uint32_t &v) const
    {
        if (off > n || n - off < 4) return false;
        if (le) {
            v = static_cast<uint32_t>(d[off]) | (static_cast<uint32_t>(d[off + 1]) << 8) | (static_cast<uint32_t>(d[off + 2]) << 16) | (static_cast<uint32_t>(d[off + 3]) << 24);
        } else {
            v = (static_cast<uint32_t>(d[off]) << 24) | (static_cast<uint32_t>(d[off + 1]) << 16) | (static_cast<uint32_t>(d[off + 2]) << 8) | static_cast<uint32_t>(d[off + 3]);
        }
        return true;
    }

    bool rational(size_t off, double &v) const
    {
        uint32_t num, den;
        if (!u32(off, num) || !u32(off + 4, den))
            return false;
        if (den == 0) return false;
        v = static_cast<double>(num) / static_cast<double>(den);
        return true;
    }

    bool srational(size_t off, double &v) const
    {
        uint32_t unum, uden;
        if (!u32(off, unum) || !u32(off + 4, uden)) return false;
        if (uden == 0) return false;
        v = static_cast<double>(static_cast<int32_t>(unum)) / static_cast<double>(static_cast<int32_t>(uden));
        return true;
    }
};

inline size_t typeUnitSize(uint16_t type)
{
    switch (type) {
    case 1:
    case 2:
        return 1; // BYTE, ASCII
    case 3:
        return 2; // SHORT
    case 4:
    case 9:
        return 4; // LONG, SLONG
    case 5:
    case 10:
        return 8; // RATIONAL, SRATIONAL
    default:
        return 0;
    }
}

inline bool ifdEntry(const TiffView &t, size_t entry, uint16_t &tag, uint16_t &type, uint32_t &count, size_t &valueOff)
{
    if (entry > t.n || t.n - entry < 12)
        return false;
    if (!t.u16(entry, tag) || !t.u16(entry + 2, type) || !t.u32(entry + 4, count)) return false;
    const size_t unit = typeUnitSize(type);
    if (unit == 0)
        return false;
    const uint64_t total = static_cast<uint64_t>(unit) * count;
    if (total <= 4) {
        valueOff = entry + 8;
        return true;
    }
    if (total > t.n)
        return false;
    uint32_t off;
    if (!t.u32(entry + 8, off))
        return false;
    if (static_cast<uint64_t>(off) + total > t.n)
        return false;
    valueOff = off;
    return true;
}

typedef void (*IfdCallback)(const TiffView &t, uint16_t tag, uint16_t type, uint32_t count, size_t valueOff, void *ctx);

inline void parseIfd(const TiffView &t, uint32_t ifdOff, std::set<uint32_t> &visited, IfdCallback cb, void *ctx)
{
    if (ifdOff >= t.n || visited.count(ifdOff))
        return;
    visited.insert(ifdOff);
    uint16_t count;
    if (!t.u16(ifdOff, count))
        return;
    if (count > 1000) count = 1000;
    const size_t base = static_cast<size_t>(ifdOff) + 2;
    for (uint32_t i = 0; i < count; ++i) {
        const size_t entry = base + static_cast<size_t>(i) * 12;
        if (entry > t.n || t.n - entry < 12)
            break;
        uint16_t tag, type;
        uint32_t cnt;
        size_t valueOff;
        if (ifdEntry(t, entry, tag, type, cnt, valueOff)) {
            cb(t, tag, type, cnt, valueOff, ctx);
        }
    }
}

inline std::string readAscii(const TiffView &t, uint16_t type, uint32_t count, size_t off)
{
    if (type != 2 || count == 0 || off >= t.n)
        return std::string();
    if (off + count > t.n) count = static_cast<uint32_t>(t.n - off);
    std::string s(reinterpret_cast<const char *>(t.d + off), count);
    while (!s.empty() && (s[s.size() - 1] == '\0' || s[s.size() - 1] == ' ')) {
        s.erase(s.size() - 1);
    }
    return s;
}

inline bool readUInt(const TiffView &t, uint16_t type, uint32_t count, size_t off, uint32_t &v)
{
    if (count < 1)
        return false;
    if (type == 3) {
        uint16_t x;
        if (!t.u16(off, x))
            return false;
        v = x;
        return true;
    }
    if (type == 4 || type == 9) {
        return t.u32(off, v);
    }
    return false;
}

inline bool readRat(const TiffView &t, uint16_t type, uint32_t count, size_t off, double &v)
{
    if (count < 1)
        return false;
    if (type == 5)
        return t.rational(off, v);
    if (type == 10)
        return t.srational(off, v);
    return false;
}

struct Ifd0Ctx {
    ExifData *out;
    uint32_t exifIfd;
    uint32_t gpsIfd;
};

inline void ifd0Cb(const TiffView &t, uint16_t tag, uint16_t type, uint32_t count, size_t off, void *ctx)
{
    Ifd0Ctx *c = static_cast<Ifd0Ctx *>(ctx);
    uint32_t u;
    switch (tag) {
    case 0x010E:
        c->out->description = readAscii(t, type, count, off);
        break;
    case 0x010F:
        c->out->make = readAscii(t, type, count, off);
        break;
    case 0x0110:
        c->out->model = readAscii(t, type, count, off);
        break;
    case 0x0112:
        if (readUInt(t, type, count, off, u))
            c->out->orientation = static_cast<int>(u);
        break;
    case 0x8769:
        if (readUInt(t, type, count, off, u))
            c->exifIfd = u;
        break;
    case 0x8825:
        if (readUInt(t, type, count, off, u))
            c->gpsIfd = u;
        break;
    default:
        break;
    }
}

inline void exifIfdCb(const TiffView &t, uint16_t tag, uint16_t type, uint32_t count, size_t off, void *ctx)
{
    ExifData *out = static_cast<ExifData *>(ctx);
    uint32_t u;
    double r;
    switch (tag) {
    case 0x829A:
        if (readRat(t, type, count, off, r))
            out->exposureTime = r;
        break;
    case 0x829D:
        if (readRat(t, type, count, off, r))
            out->fNumber = r;
        break;
    case 0x8827:
        if (readUInt(t, type, count, off, u))
            out->iso = static_cast<int>(u);
        break;
    case 0x9003:
        out->dateTimeOriginal = readAscii(t, type, count, off);
        break;
    case 0x9011:
        out->offsetTimeOriginal = readAscii(t, type, count, off);
        break;
    case 0x920A:
        if (readRat(t, type, count, off, r))
            out->focalLength = r;
        break;
    case 0xA002:
        if (readUInt(t, type, count, off, u))
            out->pixelX = static_cast<int>(u);
        break;
    case 0xA003:
        if (readUInt(t, type, count, off, u))
            out->pixelY = static_cast<int>(u);
        break;
    case 0xA434:
        out->lensModel = readAscii(t, type, count, off);
        break;
    default:
        break;
    }
}

struct GpsCtx {
    double lat[3];
    double lon[3];
    bool latOk;
    bool lonOk;
    char latRef;
    char lonRef;
};

inline void gpsCb(const TiffView &t, uint16_t tag, uint16_t type, uint32_t count, size_t off, void *ctx)
{
    GpsCtx *c = static_cast<GpsCtx *>(ctx);
    if (tag == 0x0001 || tag == 0x0003) {
        const std::string s = readAscii(t, type, count, off);
        if (!s.empty()) {
            if (tag == 0x0001) {
                c->latRef = s[0];
            } else {
                c->lonRef = s[0];
            }
        }
        return;
    }
    if (tag != 0x0002 && tag != 0x0004)
        return;
    if (type != 5 || count < 3)
        return;
    double *dst = (tag == 0x0002) ? c->lat : c->lon;
    for (int i = 0; i < 3; ++i) {
        if (!t.rational(off + static_cast<size_t>(i) * 8, dst[i]))
            return;
    }
    if (tag == 0x0002) {
        c->latOk = true;
    } else {
        c->lonOk = true;
    }
}

inline double dmsToDeg(const double dms[3], char ref)
{
    double v = dms[0] + dms[1] / 60.0 + dms[2] / 3600.0;
    if (ref == 'S' || ref == 'W' || ref == 's' || ref == 'w')
        v = -v;
    return v;
}

inline bool parseTiff(const unsigned char *d, size_t n, ExifData &out)
{
    if (n < 8)
        return false;
    TiffView t;
    t.d = d;
    t.n = n;
    if (d[0] == 'I' && d[1] == 'I') {
        t.le = true;
    } else if (d[0] == 'M' && d[1] == 'M') {
        t.le = false;
    } else {
        return false;
    }
    uint16_t magic;
    uint32_t ifd0;
    if (!t.u16(2, magic) || magic != 42)
        return false;
    if (!t.u32(4, ifd0))
        return false;

    std::set<uint32_t> visited;
    Ifd0Ctx ctx = { &out, 0, 0 };
    parseIfd(t, ifd0, visited, &ifd0Cb, &ctx);

    if (ctx.exifIfd) {
        parseIfd(t, ctx.exifIfd, visited, &exifIfdCb, &out);
    }
    if (ctx.gpsIfd) {
        GpsCtx gps;
        gps.latOk = gps.lonOk = false;
        gps.latRef = gps.lonRef = '\0';
        parseIfd(t, ctx.gpsIfd, visited, &gpsCb, &gps);
        if (gps.latOk && gps.lonOk) {
            out.hasGps = true;
            out.latitude = dmsToDeg(gps.lat, gps.latRef);
            out.longitude = dmsToDeg(gps.lon, gps.lonRef);
        }
    }
    return true;
}

} // namespace exifparser_detail

inline bool parseJpegExif(const unsigned char *data, size_t size, ExifData &out)
{
    using namespace exifparser_detail;
    if (!data || size < 4 || data[0] != 0xFF || data[1] != 0xD8)
        return false;

    size_t pos = 2;
    while (pos + 1 < size) {
        if (data[pos] != 0xFF)
            break;
        while (pos < size && data[pos] == 0xFF)
            ++pos;
        if (pos >= size)
            break;
        const unsigned char marker = data[pos++];
        if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
            continue;
        }
        if (marker == 0xDA || marker == 0xD9 || marker == 0x00)
            break;
        if (pos + 2 > size)
            break;
        const uint16_t len = static_cast<uint16_t>((data[pos] << 8) | data[pos + 1]);
        if (len < 2)
            break;
        size_t segEnd = pos + len;
        if (segEnd > size)
            segEnd = size;
        if (marker == 0xE1 && segEnd - (pos + 2) >= 6 && std::memcmp(data + pos + 2, "Exif\0\0", 6) == 0) {
            return parseTiff(data + pos + 8, segEnd - (pos + 8), out);
        }
        pos = segEnd;
    }
    return false;
}

#endif // EXIFPARSER_H
