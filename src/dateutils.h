#ifndef DATEUTILS_H
#define DATEUTILS_H

#include <QDate>
#include <QLocale>
#include <QString>

namespace DateUtils {
inline QString monthYearLabel(const QDate &date)
{
    const QLocale locale;
    QString name = locale.standaloneMonthName(date.month());
    if (!name.isEmpty()) {
        name.replace(0, 1, locale.toUpper(name.left(1)));
    }
    return name + QLatin1Char(' ') + QString::number(date.year());
}
}

#endif // DATEUTILS_H
