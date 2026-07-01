import QtQuick 2.0
import Sailfish.Silica 1.0
import QtFeedback 5.0

BackgroundItem {
    id: item

    property string assetId
    property bool isFavorite
    property bool isSelected
    property bool isVideo
    property int assetIndex: -1
    property string thumbhash: ""
    property string duration: ""
    property string stackId: ""
    property int stackAssetCount: 0
    property int imageSize: Math.max(64, Math.ceil(Math.max(width, height)))
    property bool isHighlighted: false
    property bool currentBackupState: false

    function syncBackupState() {
        currentBackupState = assetId && backupManager.isAssetBackedUp(assetId)
    }

    function formatDuration(dur) {
        if (!dur || dur === "") return ""
        // API returns duration as "H:MM:SS.ffffff"
        var parts = dur.split(".")
        var timePart = parts[0] // "H:MM:SS"
        var segments = timePart.split(":")
        if (segments.length < 3) return timePart
        var h = parseInt(segments[0])
        var m = parseInt(segments[1])
        var s = parseInt(segments[2])
        if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    Component.onCompleted:  syncBackupState()

    ThemeEffect {
        id: selectionFeedback
        effect: ThemeEffect.Press
    }

    signal addToSelection()

    onIsSelectedChanged: {
        if (isSelected) {
            selectionFeedback.play()
        }
    }

    onAssetIdChanged:  syncBackupState()

    Image {
        id: thumbhashImage
        anchors.fill: parent
        anchors.margins: 2
        fillMode: Image.PreserveAspectCrop
        source: thumbhash ? "image://thumbhash/" + thumbhash : ""
        visible: thumbnail.status !== Image.Ready
        asynchronous: false
        smooth: true
        cache: true
    }

    Image {
        id: thumbnail
        anchors.fill: parent
        anchors.margins: 2
        fillMode: Image.PreserveAspectCrop
        source: assetId ? "image://immich/thumbnail/" + assetId : ""
        asynchronous: true
        smooth: false
        cache: true
        sourceSize.width: imageSize
        sourceSize.height: imageSize

        Rectangle {
            anchors.fill: parent
            color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
            visible: thumbnail.status === Image.Loading && !thumbhash
        }

        BusyIndicator {
            anchors.centerIn: parent
            running: thumbnail.status === Image.Loading && !thumbhash
            size: BusyIndicatorSize.Small
        }

        Icon {
            anchors.centerIn: parent
            source: "image://theme/icon-m-image"
            visible: thumbnail.status === Image.Error && !thumbhash
            opacity: 0.3
        }
    }

    Rectangle {
        anchors.fill: parent
        color: isSelected ? Theme.rgba(Theme.highlightBackgroundColor, 0.2) : "transparent"
        border.width: isSelected ? 2 : 0
        border.color: isSelected ? Theme.highlightColor : "transparent"
        z: 10
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: durationRow.height + Theme.paddingSmall
        color: Theme.rgba(Theme.highlightDimmerColor, 0.8)
        visible: isVideo

        Row {
            id: durationRow
            anchors.centerIn: parent
            spacing: Theme.paddingSmall / 2

            Icon {
                source: "image://theme/icon-m-play"
                width: Theme.iconSizeExtraSmall
                height: Theme.iconSizeExtraSmall
                anchors.verticalCenter: parent.verticalCenter
            }

            Label {
                text: formatDuration(duration)
                font.pixelSize: Theme.fontSizeTiny
                color: Theme.primaryColor
                visible: text !== ""
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Favorite icon
    Icon {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: Theme.paddingSmall
        width: Theme.iconSizeSmallPlus
        height: Theme.iconSizeSmallPlus
        source: "image://theme/icon-m-favorite-selected"
        visible: isFavorite
    }

    // Stack indicator
    Icon {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.paddingSmall
        width: Theme.iconSizeSmallPlus
        height: Theme.iconSizeSmallPlus
        source: "image://theme/icon-m-levels"
        visible: stackId !== "" && stackAssetCount > 1
    }

    // Backup status indicator
    Icon {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: Theme.paddingSmall
        width: Theme.iconSizeSmallPlus
        height: Theme.iconSizeSmallPlus
        source: "image://theme/icon-m-cloud-download"
        visible: item.currentBackupState
    }

    // Highlight overlay for scroll-to-asset
    Rectangle {
        id: highlightOverlay
        anchors.fill: parent
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
        border.width: 2
        border.color: Theme.highlightColor
        opacity: 0
        z: 15

        SequentialAnimation {
            id: highlightAnim
            loops: 2
            NumberAnimation { target: highlightOverlay; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutQuad }
            NumberAnimation { target: highlightOverlay; property: "opacity"; from: 1; to: 0; duration: 500; easing.type: Easing.InQuad }
        }
    }

    onIsHighlightedChanged: {
        if (isHighlighted) {
            highlightAnim.start()
        } else {
            highlightAnim.stop()
            highlightOverlay.opacity = 0
        }
    }

    Connections {
        target: backupManager
        onBackupStatusChanged: item.syncBackupState()
    }
}
