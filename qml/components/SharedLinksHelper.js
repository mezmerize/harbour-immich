.pragma library

function pad2(n) {
    return n < 10 ? "0" + n : "" + n
}

function shareTitle(linkData, fallbackLabel) {
    if (linkData && linkData.album && linkData.album.albumName) return linkData.album.albumName
    if (linkData && linkData.description && linkData.description !== "") return linkData.description
    return fallbackLabel
}

function shareDescription(linkData, title) {
    if (linkData && linkData.description && linkData.description !== "" && title !== linkData.description) return linkData.description
    return ""
}

function formatExpiry(expiresAt, expiredLabel) {
    if (!expiresAt || expiresAt === "") return ""
    var d = new Date(expiresAt)
    if (isNaN(d.getTime())) return ""
    if (d < new Date()) return expiredLabel
    return pad2(d.getDate()) + "." + pad2(d.getMonth()) + "." + d.getFullYear() + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

function shareExpiration(expiresAt, expiredLabel, expiresTemplate, noExpiryLabel) {
    var expiry = formatExpiry(expiresAt, expiredLabel)
    if (expiry === expiredLabel) return expiredLabel
    if (expiry !== "") return expiresTemplate.replace("%1", expiry)
    return noExpiryLabel
}
