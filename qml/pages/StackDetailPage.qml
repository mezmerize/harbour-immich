import QtQuick 2.0
import Sailfish.Silica 1.0
import QtFeedback 5.0
import "../components"

Page {
    id: page

    property string stackId
    property string primaryAssetId
    property bool primaryIsFavorite: false
    property string primaryThumbhash: ""
    property int timelineAssetIndex: -1

    property var assets: []
    property int currentIndex: 0
    property bool stackLoaded: false
    property bool isFavorite: false
    property var assetInfo: null
    property int totalTimelineAssets: timelineModel.totalCount
    property int pendingTimelineIndex: -1

    // Zoom + pan state
    property real imageScale: 1.0
    property real panX: 0
    property real panY: 0
    property bool zoomed: imageScale > 1.05

    // Horizontal slide state (for prev/next timeline peek)
    property real slideOffset: 0

    // Vertical drag-to-dismiss state
    property real dragOffsetY: 0
    property bool draggingVertical: false
    property real dismissThreshold: page.height * 0.2
    property real dragOpacity: draggingVertical ? Math.max(0.2, 1.0 - Math.abs(dragOffsetY) / (page.height * 0.5)) : 1.0

    ThemeEffect {
        id: hapticFeedback
        effect: ThemeEffect.Press
    }

    function getCurrentAsset() {
        if (!assets || assets.length === 0 || currentIndex < 0 || currentIndex >= assets.length) return null
        return assets[currentIndex]
    }

    // Switch within the stack (thumbnail strip tap)
    function switchTo(newIndex) {
        if (!assets || assets.length === 0) return
        if (newIndex < 0 || newIndex >= assets.length) return

        imageScale = 1.0
        panX = 0
        panY = 0

        transitionCover.source = mainImage.source
        transitionCover.visible = true
        currentIndex = newIndex
        assetInfo = null
        var asset = assets[newIndex]
        if (asset) {
            mainImage.source = asset.id ? "image://immich/detail/" + asset.id : ""
            immichApi.getAssetInfo(asset.id)
        }
    }

    // Get timeline asset thumbnail for prev/next peek
    function getTimelineAssetSource(index) {
        if (index < 0 || index >= totalTimelineAssets) return ""
        var asset = timelineModel.getAssetByAssetIndex(index)
        return asset && asset.id ? "image://immich/detail/" + asset.id : ""
    }

    // Navigate to a different timeline asset (swipe left/right)
    function navigateToTimelineAsset(newTimelineIndex) {
        if (newTimelineIndex < 0 || newTimelineIndex >= totalTimelineAssets) return

        var asset = timelineModel.getAssetByAssetIndex(newTimelineIndex)
        if (!asset || !asset.id) {
            var location = timelineModel.getAssetLocation(newTimelineIndex)
            if (location && location.bucketIndex !== undefined && location.bucketIndex >= 0) {
                pendingTimelineIndex = newTimelineIndex
                timelineModel.requestBucketLoad(location.bucketIndex)
            }
            return
        }
        if (!asset || !asset.id) return

        if (asset.stackId && asset.stackId !== "") {
            // Target is a stack — replace this page with a new StackDetailPage
            pageStack.replace(Qt.resolvedUrl("StackDetailPage.qml"), {
                "stackId": asset.stackId,
                "primaryAssetId": asset.id,
                "primaryIsFavorite": asset.isFavorite || false,
                "primaryThumbhash": asset.thumbhash || "",
                "timelineAssetIndex": newTimelineIndex
            }, PageStackAction.Immediate)
        } else {
            // Target is a regular asset — replace with AssetDetailPage
            pageStack.replace(Qt.resolvedUrl("AssetDetailPage.qml"), {
                "assetId": asset.id,
                "isFavorite": asset.isFavorite || false,
                "isVideo": asset.isVideo || false,
                "thumbhash": asset.thumbhash || "",
                "currentIndex": newTimelineIndex
            }, PageStackAction.Immediate)
        }
    }

    allowedOrientations: Orientation.All
    backNavigation: false
    backgroundColor: "transparent"

    // Semi-transparent backdrop
    DismissDragBackdrop {
        anchors.fill: parent
        dragOpacity: page.dragOpacity
        dragOffsetY: page.dragOffsetY
        draggingVertical: page.draggingVertical
        dismissThreshold: page.dismissThreshold
        //% "Release to close"
        releaseText: qsTrId("stackDetailPage.releaseToClose")
        //% "Drag to close"
        dragText: qsTrId("stackDetailPage.dragToClose")
        z: -1
    }

    // Main content
    Item {
        id: contentContainer
        anchors.fill: parent
        opacity: dragOpacity
        transform: Translate { y: dragOffsetY }

        // Image viewport with prev/current/next for horizontal timeline peek
        Item {
            id: imageViewport
            anchors.fill: parent
            clip: true

            // Previous timeline asset (left of current)
            Image {
                id: prevImage
                x: -imageViewport.width + slideOffset
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                source: timelineAssetIndex > 0 ? getTimelineAssetSource(timelineAssetIndex - 1) : ""
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
                source: {
                    var asset = getCurrentAsset()
                    if (asset && asset.thumbhash) return "image://thumbhash/" + asset.thumbhash
                    if (primaryThumbhash) return "image://thumbhash/" + primaryThumbhash
                    return ""
                }
                visible: mainImage.status !== Image.Ready && !zoomed
                asynchronous: false
                smooth: true
                cache: true
            }

            // Current asset image
            Image {
                id: mainImage
                x: zoomed ? 0 : slideOffset
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                source: primaryAssetId ? "image://immich/detail/" + primaryAssetId : ""
                asynchronous: true
                smooth: true
                scale: imageScale
                transformOrigin: Item.Center

                onStatusChanged: {
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
                    running: mainImage.status === Image.Loading && !thumbhashPlaceholder.visible
                    size: BusyIndicatorSize.Medium
                }
            }

            // Next timeline asset (right of current)
            Image {
                id: nextImage
                x: imageViewport.width + slideOffset
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                source: timelineAssetIndex < totalTimelineAssets - 1 ? getTimelineAssetSource(timelineAssetIndex + 1) : ""
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

            // Loading overlay for stack data
            BusyIndicator {
                anchors.centerIn: parent
                running: !stackLoaded
                size: BusyIndicatorSize.Large
            }
        }

        ZoomSwipeArea {
            anchors.fill: parent
            z: 1
            stateTarget: page
            imageTarget: mainImage
            viewportWidth: page.width
            viewportHeight: page.height
            currentIndex: page.timelineAssetIndex
            totalCount: page.totalTimelineAssets
            onPrevRequested: {
                transitionCover.source = prevImage.source
                transitionCover.visible = true
                page.navigateToTimelineAsset(page.timelineAssetIndex - 1)
            }
            onNextRequested: {
                transitionCover.source = nextImage.source
                transitionCover.visible = true
                page.navigateToTimelineAsset(page.timelineAssetIndex + 1)
            }
            onDismissRequested: pageStack.pop()
        }

        // Top bar: back + info
        Item {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: Theme.itemSizeMedium
            z: 10
            visible: !zoomed && !draggingVertical

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.rgba("black", 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
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
                visible: !zoomed && !draggingVertical && stackLoaded
                opacity: visible ? 1.0 : 0.0
                Behavior on opacity { FadeAnimation { duration: 150 } }
                onClicked: {
                    var asset = getCurrentAsset()
                    if (asset && asset.id) {
                        pageStack.push(Qt.resolvedUrl("AssetInfoPage.qml"), {
                            assetId: asset.id,
                            assetInfo: page.assetInfo
                        })
                    }
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
                visible: !zoomed && !draggingVertical && stackLoaded
                opacity: visible ? 1.0 : 0.0
                Behavior on opacity { FadeAnimation { duration: 150 } }
                onClicked: pageStack.pop()
            }
        }

        // Bottom panel: counter, thumbnails, action bar
        Item {
            id: bottomPanel
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
            }
            height: bottomColumn.height
            visible: !zoomed && !draggingVertical && stackLoaded
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { FadeAnimation { duration: 150 } }
            z: 10

            Rectangle {
                anchors.fill: parent
                color: Theme.rgba("black", 0.6)
            }

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

            Column {
                id: bottomColumn
                width: parent.width
                spacing: Theme.paddingSmall

                // Asset counter
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: Theme.paddingMedium
                    //% "%1 / %2"
                    text: assets.length > 0 ? qsTrId("stackDetailPage.assetCounter").arg(currentIndex + 1).arg(assets.length) : ""
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                }

                // Thumbnail strip
                SilicaListView {
                    id: thumbnailStrip
                    width: parent.width
                    height: Theme.itemSizeMedium
                    orientation: ListView.Horizontal
                    clip: true
                    spacing: Theme.paddingSmall
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin

                    model: assets ? assets.length : 0

                    delegate: BackgroundItem {
                        width: Theme.itemSizeMedium
                        height: Theme.itemSizeMedium
                        highlighted: index === currentIndex

                        Image {
                            id: stripThumbhash
                            anchors.fill: parent
                            anchors.margins: 2
                            fillMode: Image.PreserveAspectCrop
                            source: (assets && assets[index] && assets[index].thumbhash) ? "image://thumbhash/" + assets[index].thumbhash : ""
                            visible: stripThumbnail.status !== Image.Ready
                            asynchronous: false
                            smooth: true
                            cache: true
                        }

                        Image {
                            id: stripThumbnail
                            anchors.fill: parent
                            anchors.margins: 2
                            source: (assets && assets[index] && assets[index].id) ? "image://immich/thumbnail/" + assets[index].id : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 128
                            sourceSize.height: 128

                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.width: index === currentIndex ? 3 : 0
                                border.color: Theme.highlightColor
                            }
                        }

                        onClicked: {
                            switchTo(index)
                        }
                    }

                    HorizontalScrollDecorator {}
                }

                // Action bar
                Row {
                    id: actionRow
                    width: parent.width

                    property int buttonCount: 6

                    // Favorite
                    IconButton {
                        width: parent.width / actionRow.buttonCount
                        icon.source: isFavorite ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"
                        onClicked: {
                            hapticFeedback.play()
                            immichApi.toggleFavorite([primaryAssetId], !isFavorite)
                        }
                    }

                    // Download
                    IconButton {
                        width: parent.width / actionRow.buttonCount
                        icon.source: "image://theme/icon-m-cloud-download"
                        onClicked: {
                            hapticFeedback.play()
                            var asset = getCurrentAsset()
                            if (asset) {
                                immichApi.downloadAsset(asset.id)
                                //% "Downloading..."
                                notification.show(qsTrId("stackDetailPage.downloading"))
                            }
                        }
                    }

                    // Share
                    IconButton {
                        width: parent.width / actionRow.buttonCount
                        icon.source: "image://theme/icon-m-share"
                        onClicked: {
                            var asset = getCurrentAsset()
                            if (asset) {
                                pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                                    shareType: "INDIVIDUAL",
                                    assetIds: [asset.id]
                                })
                            }
                        }
                    }

                    // Search similar
                    IconButton {
                        width: parent.width / actionRow.buttonCount
                        icon.source: "image://theme/icon-m-search"
                        onClicked: {
                            var asset = getCurrentAsset()
                            if (asset) {
                                pageStack.push(Qt.resolvedUrl("SearchResultsPage.qml"), {
                                    smartSearchAssetId: asset.id
                                })
                            }
                        }
                    }

                    // Show in timeline
                    IconButton {
                        width: parent.width / actionRow.buttonCount
                        icon.source: "image://theme/icon-m-whereami"
                        onClicked: {
                            var asset = getCurrentAsset()
                            if (asset) {
                                var assetDate = asset.localDateTime || asset.fileCreatedAt || ""
                                pageStack.pop(pageStack.find(function(p) {
                                    return p.objectName === "timelinePage"
                                }))
                                timelineModel.scrollToAsset(asset.id, assetDate)
                            }
                        }
                    }

                    // Unstack
                    IconButton {
                        width: parent.width / actionRow.buttonCount
                        icon.source: "image://theme/icon-m-levels"
                        onClicked: {
                            hapticFeedback.play()
                            //% "Unstacking"
                            unstackRemorse.execute(qsTrId("stackDetailPage.unstacking"), function() {
                                immichApi.deleteStack(page.stackId)
                            })
                        }
                    }
                }

                // Bottom spacing
                Item {
                    width: 1
                    height: Theme.paddingMedium
                }
            }
        }

        NotificationBanner {
            id: notification
            anchors.bottom: bottomPanel.top
            z: 10
        }
    }

    RemorsePopup {
        id: unstackRemorse
    }

    Connections {
        target: timelineModel
        onBucketAssetsLoaded: {
            if (page.pendingTimelineIndex < 0) {
                return
            }
            var location = timelineModel.getAssetLocation(page.pendingTimelineIndex)
            if (location && location.bucketIndex === bucketIndex) {
                var targetIndex = page.pendingTimelineIndex
                page.pendingTimelineIndex = -1
                page.navigateToTimelineAsset(targetIndex)
            }
        }
    }

    Component.onCompleted: {
        isFavorite = primaryIsFavorite
        immichApi.getStack(stackId)
    }

    Connections {
        target: immichApi
        onStackReceived: {
            if (stackId === page.stackId) {
                page.assets = assets
                page.stackLoaded = true
                if (assets.length > 0) {
                    // Find the primary asset index
                    for (var i = 0; i < assets.length; i++) {
                        if (assets[i].id === page.primaryAssetId) {
                            page.currentIndex = i
                            page.isFavorite = assets[i].isFavorite || false
                            break
                        }
                    }
                    // Load detail image for current asset
                    var current = page.getCurrentAsset()
                    if (current) {
                        mainImage.source = "image://immich/detail/" + current.id
                        immichApi.getAssetInfo(current.id)
                    }
                }
            }
        }
        onAssetInfoReceived: {
            var current = page.getCurrentAsset()
            if (current && info.id === current.id) {
                page.assetInfo = info
            }
            if (info.id === page.primaryAssetId && info.isFavorite !== undefined) {
                page.isFavorite = info.isFavorite
            }
        }
        onFavoritesToggled: {
            if (assetIds.indexOf(page.primaryAssetId) > -1) {
                page.isFavorite = isFavorite
                notification.show(isFavorite ?
                    //% "Added to favorites"
                    qsTrId("stackDetailPage.addedToFavorites")
                    //% "Removed from favorites"
                    : qsTrId("stackDetailPage.removedFromFavorites"))
            }
        }
        onAssetDownloaded: {
            var current = page.getCurrentAsset()
            if (current && assetId === current.id) {
                //% "Downloaded to: %1"
                notification.show(qsTrId("stackDetailPage.downloaded").arg(filePath))
            }
        }
        onStackDeleted: {
            if (stackId === page.stackId) {
                // Refresh timeline and go back
                immichApi.fetchTimelineBuckets("timeline", {"visibility": "timeline", "withStacked": "true", "order": "desc", "withPartners": "true"})
                pageStack.pop()
            }
        }
    }
}
