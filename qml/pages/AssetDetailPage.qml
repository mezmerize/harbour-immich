import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property string assetId
    property bool isFavorite: false
    property bool isVideo: false
    property var assetInfo: null
    property int currentIndex: -1
    property var albumAssets: null
    property int totalAssets: albumAssets ? albumAssets.length : timelineModel.totalCount
    property string thumbhash: ""
    property string currentThumbhash: assetInfo && assetInfo.thumbhash ? assetInfo.thumbhash : thumbhash

    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                //% "Information"
                text: qsTrId("assetDetailPage.information")
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("AssetInfoPage.qml"), {
                        assetId: assetId,
                        assetInfo: assetInfo
                    })
                }
            }

            MenuItem {
                //% "Show similar assets"
                text: qsTrId("assetDetailPage.showSimilar")
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("SearchResultsPage.qml"), {
                        smartSearchAssetId: assetId
                    })
                }
            }

            MenuItem {
                //% "Show in timeline"
                text: qsTrId("assetDetailPage.showInTimeline")
                onClicked: {
                    var assetDate = ""
                    if (assetInfo) {
                        assetDate = assetInfo.localDateTime || assetInfo.fileCreatedAt || ""
                    }
                    pageStack.pop(pageStack.find(function(p) {
                        return p.objectName === "timelinePage"
                    }))
                    timelineModel.scrollToAsset(assetId, assetDate)
                }
            }

            MenuItem {
                //% "Share"
                text: qsTrId("assetDetailPage.share")
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                        shareType: "INDIVIDUAL",
                        assetIds: [assetId]
                    })
                }
            }

            MenuItem {
                text: isFavorite
                      //% "Remove from favorites"
                      ? qsTrId("assetDetailPage.removeFromFavorites")
                      //% "Add to favorites"
                      : qsTrId("assetDetailPage.addToFavorites")
                onClicked: {
                    immichApi.toggleFavorite([assetId], !isFavorite)
                    isFavorite = !isFavorite
                }
            }
        }

        Column {
            id: column
            width: page.width

            Item {
                width: parent.width
                height: page.height

                Image {
                    id: thumbhashPlaceholder
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    source: currentThumbhash ? "image://thumbhash/" + currentThumbhash : ""
                    visible: assetImage.status !== Image.Ready
                    asynchronous: false
                    smooth: true
                    cache: true
                }

                Image {
                    id: assetImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    source: assetId ? "image://immich/detail/" + assetId : ""
                    asynchronous: true
                    smooth: true

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: assetImage.status === Image.Loading && !currentThumbhash
                        size: BusyIndicatorSize.Large
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: assetImage.status === Image.Error
                        //% "Failed to load image"
                        text: qsTrId("assetDetailPage.failed")
                        color: Theme.secondaryColor
                    }
                }
            }

            // Preload adjacent assets for faster navigation
            Image {
                id: preloadPrev
                visible: false
                width: 1
                height: 1
                asynchronous: true
                cache: true
                source: {
                    if (currentIndex > 0) {
                        var prevAsset = albumAssets ? albumAssets[currentIndex - 1] : timelineModel.getAssetByAssetIndex(currentIndex - 1)
                        return prevAsset && prevAsset.id ? "image://immich/detail/" + prevAsset.id : ""
                    }
                    return ""
                }
            }

            Image {
                id: preloadNext
                visible: false
                width: 1
                height: 1
                asynchronous: true
                cache: true
                source: {
                    if (currentIndex >= 0 && currentIndex < totalAssets - 1) {
                        var nextAsset = albumAssets ? albumAssets[currentIndex + 1] : timelineModel.getAssetByAssetIndex(currentIndex + 1)
                        return nextAsset && nextAsset.id ? "image://immich/detail/" + nextAsset.id : ""
                    }
                    return ""
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        PinchArea {
            anchors.fill: parent
            pinch.target: assetImage
            pinch.minimumScale: 1
            pinch.maximumScale: 4
            
            onPinchFinished: {
                if (assetImage.scale < 1.1) {
                    assetImage.scale = 1
                    assetImage.x = 0
                    assetImage.y = 0
                }
            }
            
            MouseArea {
                anchors.fill: parent
                
                onDoubleClicked: {
                    if (assetImage.scale > 1.1) {
                        assetImage.scale = 1
                        assetImage.x = 0
                        assetImage.y = 0
                    } else {
                        assetImage.scale = 2
                    }
                }
            }
        }

        // Navigation buttons
        IconButton {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.horizontalPageMargin
            icon.source: "image://theme/icon-m-left"
            visible: currentIndex > 0 && assetImage.scale <= 1.1
            opacity: 0.8
            onClicked: navigateToAsset(currentIndex - 1)

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: Theme.rgba(Theme.highlightDimmerColor, 0.5)
                z: -1
            }
        }

        IconButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Theme.horizontalPageMargin
            icon.source: "image://theme/icon-m-right"
            visible: currentIndex < totalAssets - 1 && currentIndex >= 0 && assetImage.scale <= 1.1
            opacity: 0.8
            onClicked: navigateToAsset(currentIndex + 1)

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: Theme.rgba(Theme.highlightDimmerColor, 0.5)
                z: -1
            }
        }
    }

    function navigateToAsset(assetIndex) {
        if (assetIndex < 0 || assetIndex >= totalAssets) return
        
        var asset = albumAssets ? albumAssets[assetIndex] : timelineModel.getAssetByAssetIndex(assetIndex)
        if (asset && asset.id) {
            assetImage.source = ""
            assetId = asset.id
            isFavorite = asset.isFavorite || false
            isVideo = asset.isVideo || false
            thumbhash = asset.thumbhash || ""
            currentIndex = assetIndex
            
            if (isVideo) {
                pageStack.replace(Qt.resolvedUrl("VideoPlayerPage.qml"), {
                    videoId: assetId,
                    isFavorite: isFavorite,
                    currentIndex: assetIndex,
                    albumAssets: albumAssets
                })
            } else {
                assetImage.source = "image://immich/detail/" + assetId
                immichApi.getAssetInfo(assetId)
            }
        } else {
            console.warn("AssetDetailPage: Invalid asset data at index", assetIndex)
        }
    }

    Component.onCompleted: {
        if (isVideo) {
            pageStack.replace(Qt.resolvedUrl("VideoPlayerPage.qml"), {
                videoId: assetId,
                isFavorite: isFavorite,
                currentIndex: currentIndex
            })
        } else {
            immichApi.getAssetInfo(assetId)
        }
    }

    Connections {
        target: immichApi
        onAssetInfoReceived: {
            assetInfo = info
        }
    }
}
