.pragma library

function parseAssets(results, sortAsc) {
    var parsed = []
    for (var i = 0; i < results.length; i++) {
        var a = results[i]
        var dt = a.localDateTime || a.fileCreatedAt || a.createdAt || ""
        parsed.push({
            id: a.id,
            isFavorite: a.isFavorite || false,
            isVideo: a.type === "VIDEO",
            thumbhash: a.thumbhash || "",
            duration: a.duration || "",
            dateTime: dt,
            dateObj: new Date(dt)
        })
    }
    if (sortAsc) {
        parsed.sort(function(a, b) { return a.dateObj - b.dateObj })
    } else {
        parsed.sort(function(a, b) { return b.dateObj - a.dateObj })
    }
    return parsed
}

function pickHeroIds(parsed, maxCount) {
    if (!maxCount) maxCount = 5
    var heroIds = []
    if (parsed.length === 0) return heroIds

    var indices = []
    for (var h = 0; h < parsed.length; h++) indices.push(h)
    for (var s = indices.length - 1; s > 0; s--) {
        var j = Math.floor(Math.random() * (s + 1))
        var tmp = indices[s]; indices[s] = indices[j]; indices[j] = tmp
    }
    for (var k = 0; k < indices.length && heroIds.length < maxCount; k++) {
        if (!parsed[indices[k]].isVideo) heroIds.push(parsed[indices[k]].id)
    }
    if (heroIds.length === 0 && parsed.length > 0) heroIds.push(parsed[0].id)
    return heroIds
}

function computeDateRange(parsed) {
    if (parsed.length === 0) return ""
    var sorted = parsed.slice().sort(function(a, b) { return a.dateObj - b.dateObj })
    var fmt = function(d) {
        var dd = d.getDate(), mm = d.getMonth() + 1, yyyy = d.getFullYear()
        return (dd < 10 ? "0" + dd : dd) + "." + (mm < 10 ? "0" + mm : mm) + "." + yyyy
    }
    if (sorted[0].dateObj.getTime() === sorted[sorted.length - 1].dateObj.getTime()) {
        return fmt(sorted[0].dateObj)
    }
    return fmt(sorted[0].dateObj) + " — " + fmt(sorted[sorted.length - 1].dateObj)
}

function groupByMonthAndDate(parsed) {
    var monthMap = {}, monthOrder = []
    for (var g = 0; g < parsed.length; g++) {
        var asset = parsed[g], d = asset.dateObj
        var monthKey = d.getFullYear() + "-" + (d.getMonth() + 1)
        var months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
        var monthLabel = months[d.getMonth()] + " " + d.getFullYear()
        var dateKey = d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
        var dd = d.getDate(), mm = d.getMonth() + 1, yyyy = d.getFullYear()
        var dateLabel = (dd < 10 ? "0" + dd : dd) + "." + (mm < 10 ? "0" + mm : mm) + "." + yyyy

        if (!monthMap[monthKey]) {
            monthMap[monthKey] = { monthYear: monthLabel, dateMap: {}, dateOrder: [] }
            monthOrder.push(monthKey)
        }
        var month = monthMap[monthKey]
        if (!month.dateMap[dateKey]) {
            month.dateMap[dateKey] = { displayDate: dateLabel, assets: [] }
            month.dateOrder.push(dateKey)
        }
        month.dateMap[dateKey].assets.push({
            id: asset.id, isFavorite: asset.isFavorite, isVideo: asset.isVideo,
            thumbhash: asset.thumbhash, duration: asset.duration, assetIndex: g
        })
    }
    var result = []
    for (var m = 0; m < monthOrder.length; m++) {
        var mData = monthMap[monthOrder[m]], groups = []
        for (var di = 0; di < mData.dateOrder.length; di++) groups.push(mData.dateMap[mData.dateOrder[di]])
        result.push({ monthYear: mData.monthYear, groups: groups })
    }
    return result
}

function processResults(results, sortAsc) {
    var parsed = parseAssets(results, sortAsc)
    return {
        allAssets: parsed,
        heroAssetIds: pickHeroIds(parsed, 5),
        dateRange: computeDateRange(parsed),
        groupedAssets: groupByMonthAndDate(parsed),
        totalCount: parsed.length
    }
}
