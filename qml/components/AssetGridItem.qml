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
    property int imageSize: Math.floor(1024 / settingsManager.assetsPerRow)

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

    // Track if this item is potentially visible (within viewport + buffer)
    property bool shouldLoad: true // Will be set by parent based on scroll position

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
        source: item.shouldLoad && assetId ? "image://immich/thumbnail/" + assetId : ""
        asynchronous: true
        smooth: false
        cache: false
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
    
    Icon {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.paddingSmall
        width: Theme.iconSizeSmallPlus
        height: Theme.iconSizeSmallPlus
        source: "image://theme/icon-m-favorite-selected"
        visible: isFavorite
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.3)
        visible: isSelected
    }

    Image {
        anchors.centerIn: parent
        source: "image://theme/icon-m-acknowledge"
        visible: isSelected
        width: Theme.iconSizeMedium
        height: Theme.iconSizeMedium
    }
}
