import QtQuick 2.0
import Sailfish.Silica 1.0
import QtFeedback 5.0
import "../components"

Page {
    id: page

    ThemeEffect {
        id: hapticFeedback
        effect: ThemeEffect.Press
    }

    property string assetId
    property bool isFavorite: false
    property bool isVideo: false
    property var assetInfo: null
    property int currentIndex: -1
    property var albumAssets: null
    property string albumId: ""
    property var assetModel: timelineModel
    property int totalAssets: albumAssets ? albumAssets.length : (assetModel ? assetModel.totalCount : 0)
    property string thumbhash: ""
    property string currentThumbhash: assetInfo && assetInfo.thumbhash ? assetInfo.thumbhash : thumbhash
    property int pendingNavigationIndex: -1
    property bool isLockedAsset: false
    property bool isOwnedByOther: assetInfo ? (assetInfo.ownerId !== undefined && assetInfo.ownerId !== authManager.userId) : false

    // Zoom + pan state
    property real imageScale: 1.0
    property real panX: 0
    property real panY: 0
    property bool zoomed: imageScale > 1.05

    // Horizontal slide state (for prev/next peek)
    property real slideOffset: 0

    // Vertical drag-to-dismiss state
    property real dragOffsetY: 0
    property bool draggingVertical: false
    property real dismissThreshold: page.height * 0.2
    property real dragOpacity: draggingVertical ? Math.max(0.2, 1.0 - Math.abs(dragOffsetY) / (page.height * 0.5)) : 1.0

    function getAssetSource(index) {
        if (index < 0 || index >= totalAssets) return ""
        var asset = albumAssets ? albumAssets[index] : (assetModel ? assetModel.getAssetByAssetIndex(index) : null)
        return asset && asset.id ? "image://immich/detail/" + asset.id : ""
    }

    function navigateToAsset(assetIndex) {
        if (assetIndex < 0 || assetIndex >= totalAssets) return

        imageScale = 1.0
        panX = 0
        panY = 0

        var asset = albumAssets ? albumAssets[assetIndex] : assetModel.getAssetByAssetIndex(assetIndex)
        if (!albumAssets && (!asset || !asset.id)) {
            var location = assetModel.getAssetLocation(assetIndex)
            if (location && location.bucketIndex !== undefined && location.bucketIndex >= 0) {
                pendingNavigationIndex = assetIndex
                assetModel.requestBucketLoad(location.bucketIndex)
            }
            return
        }
        if (asset && asset.id) {
            // If timeline asset is a stack, replace with stack detail
            if (!albumAssets && asset.stackId && asset.stackId !== "") {
                pageStack.replace(Qt.resolvedUrl("StackDetailPage.qml"), {
                    "stackId": asset.stackId,
                    "primaryAssetId": asset.id,
                    "primaryIsFavorite": asset.isFavorite || false,
                    "primaryThumbhash": asset.thumbhash || "",
                    "timelineAssetIndex": assetIndex,
                    "assetModel": page.assetModel
                }, PageStackAction.Immediate)
                return
            }

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

    function getButtonCount() {
        if (isLockedAsset || isOwnedByOther) return 3
        if (albumId) return 6
        return 5
    }

    allowedOrientations: Orientation.All
    backNavigation: false
    backgroundColor: "transparent"

    // Semi-transparent backdrop that fades during drag
    DismissDragBackdrop {
        anchors.fill: parent
        dragOpacity: page.dragOpacity
        dragOffsetY: page.dragOffsetY
        draggingVertical: page.draggingVertical
        dismissThreshold: page.dismissThreshold
        //% "Release to close"
        releaseText: qsTrId("assetDetailPage.releaseToClose")
        //% "Drag to close"
        dragText: qsTrId("assetDetailPage.dragToClose")
        z: -1
    }

    // Main content container - moves vertically during drag-to-dismiss
    Item {
        id: contentContainer
        anchors.fill: parent
        opacity: dragOpacity
        transform: Translate { y: dragOffsetY }

        // Image viewport with prev/current/next for horizontal peek
        Item {
            id: imageViewport
            anchors.fill: parent
            clip: true

            // Previous asset (left of current)
            Image {
                id: prevImage
                x: -imageViewport.width + slideOffset
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                source: getAssetSource(currentIndex - 1)
                asynchronous: true
                cache: true
            }

            // Thumbhash placeholder for current asset
            Image {
                id: thumbhashPlaceholder
                x: zoomed ? 0 : slideOffset
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                source: currentThumbhash ? "image://thumbhash/" + currentThumbhash : ""
                visible: assetImage.status !== Image.Ready && !zoomed
                asynchronous: false
                smooth: true
                cache: true
            }

            // Current asset image
            Image {
                id: assetImage
                x: zoomed ? 0 : slideOffset
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                source: assetId ? "image://immich/detail/" + assetId : ""
                asynchronous: true
                smooth: true
                scale: imageScale
                transformOrigin: Item.Center

                onStatusChanged:  {
                    if (status === Image.Ready && transitionCover.visible) {
                        transitionCover.visible = false
                        transitionCover.source = ""
                    }
                }

                transform: Translate {
                    x: panX
                    y: panY
                }

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
                    color: Theme.lightSecondaryColor
                }
            }

            // Next asset (right of current)
            Image {
                id: nextImage
                x: imageViewport.width + slideOffset
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                source: getAssetSource(currentIndex + 1)
                asynchronous: true
                cache: true
            }

            // Transition cover to prevent flash during asset switch
            Image {
                id: transitionCover
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                visible: false
                asynchronous: false
                cache: true
                z: 2
            }
        }

        ZoomSwipeArea {
            anchors.fill: parent
            z: 1
            stateTarget: page
            imageTarget: assetImage
            viewportWidth: page.width
            viewportHeight: page.height
            currentIndex: page.currentIndex
            totalCount: page.totalAssets
            onPrevRequested: {
                transitionCover.source = prevImage.source
                transitionCover.visible = true
                page.navigateToAsset(page.currentIndex - 1)
            }
            onNextRequested: {
                transitionCover.source = nextImage.source
                transitionCover.visible = true
                page.navigateToAsset(page.currentIndex + 1)
            }
            onDismissRequested: pageStack.pop()
        }

        // Info button (top-left)
        IconButton {
            id: infoButton
            anchors {
                top: parent.top
                left: parent.left
                topMargin: Theme.paddingLarge
                leftMargin: Theme.horizontalPageMargin
            }
            icon.source: "image://theme/icon-m-about"
            icon.color: Theme.lightPrimaryColor
            visible: !zoomed && !draggingVertical
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { FadeAnimation { duration: 150 } }
            onClicked: {
                pageStack.push(Qt.resolvedUrl("AssetInfoPage.qml"), {
                    assetId: assetId,
                    assetInfo: assetInfo
                })
            }
            z: 10
        }

        // Back button (top-right)
        IconButton {
            id: backButton
            anchors {
                top: parent.top
                right: parent.right
                topMargin: Theme.paddingLarge
                rightMargin: Theme.horizontalPageMargin
            }
            icon.source: "image://theme/icon-m-reset"
            icon.color: Theme.lightPrimaryColor
            visible: !zoomed && !draggingVertical
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { FadeAnimation { duration: 150 } }
            onClicked: pageStack.pop()
            z: 10
        }

        // Bottom action bar
        Rectangle {
            id: actionBar
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
            }
            height: actionRow.height + Theme.paddingMedium * 2
            color: Theme.rgba("black", 0.6)
            visible: !zoomed && !draggingVertical
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { FadeAnimation { duration: 150 } }
            z: 10

            // Gradient top edge
            Rectangle {
                anchors.bottom: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Theme.paddingLarge * 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Theme.rgba("black", 0.6) }
                }
            }

            Row {
                id: actionRow
                anchors.centerIn: parent
                width: parent.width

                property int buttonCount: page.getButtonCount()

                IconButton {
                    width: parent.width / actionRow.buttonCount
                    icon.source: isFavorite ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"
                    icon.color: Theme.lightPrimaryColor
                    visible: !isOwnedByOther
                    onClicked: {
                        hapticFeedback.play()
                        immichApi.toggleFavorite([assetId], !isFavorite)
                    }
                }

                IconButton {
                    width: parent.width / actionRow.buttonCount
                    icon.source: "image://theme/icon-m-cloud-download"
                    icon.color: Theme.lightPrimaryColor
                    onClicked: {
                        hapticFeedback.play()
                        immichApi.downloadAsset(assetId)
                        //% "Downloading..."
                        notification.show(qsTrId("notification.downloading"))
                    }
                }

                IconButton {
                    width: parent.width / actionRow.buttonCount
                    icon.source: "image://theme/icon-m-share"
                    icon.color: Theme.lightPrimaryColor
                    visible: !isLockedAsset
                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                            shareType: "INDIVIDUAL",
                            assetIds: [assetId]
                        })
                    }
                }

                IconButton {
                    width: parent.width / actionRow.buttonCount
                    icon.source: "image://theme/icon-m-search"
                    icon.color: Theme.lightPrimaryColor
                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("SearchResultsPage.qml"), {
                            smartSearchAssetId: assetId
                        })
                    }
                }

                IconButton {
                    width: parent.width / actionRow.buttonCount
                    icon.source: "image://theme/icon-m-whereami"
                    icon.color: Theme.lightPrimaryColor
                    visible: !isLockedAsset && !isOwnedByOther
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

                IconButton {
                    width: parent.width / actionRow.buttonCount
                    visible: albumId !== ""
                    icon.source: "image://theme/icon-m-delete"
                    icon.color: Theme.lightPrimaryColor
                    onClicked: {
                        hapticFeedback.play()
                        //% "Removing from album"
                        removeRemorse.execute(qsTrId("notification.removingFromAlbum"), function() {
                            immichApi.removeAssetsFromAlbum(albumId, [assetId])
                        })
                    }
                }
            }
        }

        NotificationBanner {
            id: notification
            anchors.bottom: actionBar.top
            z: 10
        }
    }

    RemorsePopup {
        id: removeRemorse
    }

    Connections {
        target: albumAssets ? null : assetModel
        onBucketAssetsLoaded: {
            if (page.pendingNavigationIndex < 0) {
                return
            }
            var location = assetModel.getAssetLocation(page.pendingNavigationIndex)
            if (location && location.bucketIndex === bucketIndex) {
                var targetIndex = page.pendingNavigationIndex
                page.pendingNavigationIndex = -1
                page.navigateToAsset(targetIndex)
            }
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
            if (info.id === page.assetId && info.isFavorite !== undefined) {
                page.isFavorite = info.isFavorite
            }
        }
        onFavoritesToggled: {
            if (assetIds.indexOf(assetId) > -1) {
                page.isFavorite = isFavorite
                notification.show(isFavorite ?
                     //% "Added asset to favorites"
                     qsTrId("notification.addedAssetToFavorites")
                     //% "Removed asset from favorites"
                     : qsTrId("notification.removedAssetFromFavorites"))
            }
        }
        onAssetDownloaded: {
            if (assetId === page.assetId) {
                //% "Downloaded to: %1"
                notification.show(qsTrId("notification.downloaded").arg(filePath))
            }
        }
        onAssetsRemovedFromAlbum: {
            if (albumId === page.albumId) {
                pageStack.pop()
            }
        }
    }
}
