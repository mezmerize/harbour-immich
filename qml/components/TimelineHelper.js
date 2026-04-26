.pragma library

function getHeroIds(model, maxCount) {
    if (maxCount === undefined) maxCount = 5
    var ids = []
    var bucketCount = model.getBucketCount()
    for (var b = 0; b < bucketCount && ids.length < maxCount; b++) {
        if (!model.isBucketLoaded(b)) continue
        var assets = model.getBucketAssets(b)
        for (var a = 0; a < assets.length && ids.length < maxCount; a++) {
            if (!assets[a].isVideo) ids.push(assets[a].id)
        }
    }
    return ids
}

function computeDateRange(startDate, endDate) {
    if (!startDate || !endDate) return ""
    var fmt = function(d) {
        var dd = d.getDate()
        var mm = d.getMonth() + 1
        var yyyy = d.getFullYear()
        return (dd < 10 ? "0" + dd : dd) + "." + (mm < 10 ? "0" + mm : mm) + "." + yyyy
    }
    var first = new Date(startDate)
    var last = new Date(endDate)
    if (first > last) {
        var tmp = first
        first = last
        last = tmp
    }
    if (first.getFullYear() === last.getFullYear() && first.getMonth() === last.getMonth() && first.getDate() === last.getDate()) {
        return fmt(first)
    } else {
        return fmt(first) + " - " + fmt(last)
    }
}
