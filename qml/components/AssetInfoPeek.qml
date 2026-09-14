import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: peek

    property string assetId: ""
    property var assetInfo
    property real dragOffsetY: 0
    property real openThreshold: 0

    property bool pastThreshold: openThreshold > 0 && -dragOffsetY >= openThreshold
    readonly property var exifInfo: (assetInfo && assetInfo.exifInfo) || null
    readonly property string fileName: (assetInfo && assetInfo.originalFileName) || ""
    readonly property string dateText: {
        var dt = (assetInfo && (assetInfo.localDateTime || assetInfo.fileCreatedAt)) || ""
        return dt ? Qt.formatDateTime(new Date(dt), "dd.MM.yyyy hh:mm") : ""
    }
    readonly property string cameraText: {
        if (exifInfo && (exifInfo.make || exifInfo.model)) return ((exifInfo.make || "") + " " + (exifInfo.model || "")).replace(/^\s+|\s+$/g, "")
        return ""
    }
    readonly property string resolutionText: {
        if (exifInfo && exifInfo.exifImageWidth && exifInfo.exifImageHeight) return exifInfo.exifImageWidth + " x " + exifInfo.exifImageHeight
        return ""
    }
    readonly property string sizeText: {
        if (exifInfo && exifInfo.fileSizeInByte) return formatBytes(exifInfo.fileSizeInByte)
        return ""
    }
    readonly property string locationText: {
        if (!exifInfo) return ""
        var parts = []
        if (exifInfo.city) parts.push(exifInfo.city)
        if (exifInfo.country) parts.push(exifInfo.country)
        if (parts.length > 0) return parts.join(", ")
        if (exifInfo.latitude !== undefined && exifInfo.latitude !== null && exifInfo.latitude !== 0) {
            var lon = (exifInfo.longitude !== undefined && exifInfo.longitude !== null) ? exifInfo.longitude : 0
            return exifInfo.latitude.toFixed(4) + ", " + lon.toFixed(4)
        }
        return ""
    }

    function formatBytes(bytes) {
        if (!bytes || bytes === 0) return "0 B"
        var sizes = ["B", "KB", "MB", "GB", "TB"]
        var i = Math.floor(Math.log(bytes) / Math.log(1024))
        return parseFloat((bytes / Math.pow(1024, i)).toFixed(2)) + " " + sizes[i]
    }

    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    y: parent ? parent.height + Math.min(0, dragOffsetY) : 0
    visible: dragOffsetY < 0

    Column {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: Theme.paddingMedium
        }
        spacing: Theme.paddingLarge

        Row {
            width: parent.width - 2 * Theme.horizontalPageMargin
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.paddingLarge
            visible: peek.fileName !== ""

            Icon {
                source: "image://theme/icon-m-image"
                width: Theme.iconSizeSmall
                height: Theme.iconSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }

            Label {
                width: parent.width
                text: peek.fileName
                color: Theme.lightPrimaryColor
                truncationMode: TruncationMode.Fade
            }
        }

        Repeater {
            model: [
                { icon: "image://theme/icon-m-date", text: peek.dateText },
                { icon: "image://theme/icon-m-scale", text: peek.resolutionText },
                { icon: "image://theme/icon-m-file-image", text: peek.sizeText },
                { icon: "image://theme/icon-m-camera", text: peek.cameraText },
                { icon: "image://theme/icon-m-location", text: peek.locationText }
            ]

            Row {
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge
                visible: modelData.text !== ""

                Icon {
                    source: modelData.icon
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: modelData.text
                    color: Theme.lightPrimaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    truncationMode: TruncationMode.Fade
                }
            }
        }
    }

    Label {
        y: Math.max(0, -peek.dragOffsetY - height - Theme.paddingLarge)
        anchors.horizontalCenter: parent.horizontalCenter
        text: peek.pastThreshold
            //% "Release to view info"
            ? qsTrId("assetInfoPeek.releaseToViewInfo")
            //% "Pull up for info"
            : qsTrId("assetInfoPeek.dragForInfo")
        color: peek.pastThreshold ? Theme.highlightColor : Theme.secondaryColor
        font.pixelSize: Theme.fontSizeMedium
        opacity: peek.openThreshold > 0 ? Math.min(1.0, -peek.dragOffsetY / (peek.openThreshold * 0.5)) : 1.0
    }
}
