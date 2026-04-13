import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    objectName: "timelinePage"

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property int bucketCount: timelineModel.bucketCount

    // Filter state
    property string activeFilter: "all"
    property string sortOrder: "desc"
    property string contextId: "timeline"
    property var queryParams: ({})

    // Highlight state for scroll-to-asset
    property string highlightAssetId: ""
    property var memoriesBarItem: null
    property bool memoriesLoading: false
    property var pendingMemoriesData: null

    function resetPendingScrollState() {
        pendingScrollAssetId = ""
        pendingScrollBucketIndex = -1
        pendingScrollAssetIndex = -1
        pendingScrollLastTargetY = -1
        pendingScrollLastBucketHeight = -1
        pendingScrollStablePasses = 0
        pendingScrollRetryCount = 0
    }

    function refresh() {
        resetPendingScrollState()
        highlightAssetId = ""
        scrollFinalizeTimer.stop()
        highlightClearTimer.stop()
        bucketsList.positionViewAtBeginning()
        timelineModel.clear()
        timelineModel.setLoading(true)
        var isFavorite = activeFilter === "favorites"
        timelineModel.setFavoriteFilter(isFavorite)
        var params = {
            "visibility": "timeline",
            "withStacked": "true",
            "order": sortOrder
        }
        if (isFavorite) {
            params["isFavorite"] = "true"
        } else {
            params["withPartners"] = "true"
        }
        queryParams = params
        immichApi.fetchTimelineBuckets(contextId, queryParams)
    }

    function currentBucketLoadMargin() {
        return bucketsList.flicking ? 0 : Math.max(bucketsList.height * 0.25, 300)
    }

    function shouldAutoLoadBucket(bucketIndex, itemY, itemHeight) {
        if (pendingScrollBucketIndex >= 0) {
            return bucketIndex === pendingScrollBucketIndex
        }
        if (bucketCount <= 0) {
            return false
        }

        var margin = currentBucketLoadMargin()
        return itemY + itemHeight >= bucketsList.contentY - margin && itemY <= bucketsList.contentY + bucketsList.height + margin
    }

    function findBucketItem(bucketIndex) {
        if (!bucketsList.contentItem) return null
        var children = bucketsList.contentItem.children
        for (var i = 0; i < children.length; i++) {
            var child = children[i]
            if (child && child.bucketIndex === bucketIndex) {
                return child
            }
        }
        return null
    }

    SilicaListView {
        id: bucketsList
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: selectionActionBar.shown ? selectionActionBar.top : parent.bottom
        clip: true
        cacheBuffer: Math.max(height * 2, 2000)
        pixelAligned: true
        model: timelineModel

        PullDownMenu {
            MenuItem {
                //% "Settings"
                text: qsTrId("timelinePage.settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }

            MenuItem {
                //% "Library"
                text: qsTrId("timelinePage.library")
                onClicked: pageStack.push(Qt.resolvedUrl("LibraryPage.qml"))
            }

            MenuItem {
                //% "Search"
                text: qsTrId("timelinePage.search")
                onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
            }

            MenuItem {
                //% "Albums"
                text: qsTrId("timelinePage.albums")
                onClicked: pageStack.push(Qt.resolvedUrl("AlbumsPage.qml"))
            }

            MenuItem {
                //% "Upload"
                text: qsTrId("timelinePage.upload")
                onClicked: pageStack.push(Qt.resolvedUrl("UploadPage.qml"))
            }

            MenuItem {
                //% "Refresh"
                text: qsTrId("timelinePage.refresh")
                onClicked: {
                    page.refresh()
                    page.memoriesLoading = true
                    immichApi.fetchMemories()
                }
            }
        }

        header: Column {
            width: bucketsList.width
            spacing: 0

            PageHeader {
                //% "Timeline"
                title: qsTrId("timelinePage.timeline")
            }

            MemoriesBar {
                id: memoriesBar
                width: parent.width
                loading: page.memoriesLoading
                visible: activeFilter === "all" && settingsManager.showMemoriesBar

                Component.onCompleted: {
                    page.memoriesBarItem = memoriesBar
                    if (page.pendingMemoriesData !== null) {
                        memoriesBar.loadMemories(page.pendingMemoriesData)
                        page.pendingMemoriesData = null
                    }
                }

                Component.onDestruction: {
                    if (page.memoriesBarItem === memoriesBar) {
                        page.memoriesBarItem = null
                    }
                }
            }

            TimelineFilterBar {
                activeFilter: page.activeFilter
                sortOrder: page.sortOrder
                onFilterActivated: {
                    page.activeFilter = filter
                    page.refresh()
                }
                onSortOrderToggled: {
                    page.sortOrder = order
                    page.refresh()
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingSmall
            }
        }

        delegate: TimelineBucketDelegate {
            width: bucketsList.width
            bucketIndex: index
            bucketKey: timelineModel.getBucketTimeBucket(index)
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
            highlightAssetId: page.highlightAssetId
            autoLoadAssets: page.shouldAutoLoadBucket(index, y, height)

            onAssetClicked: {
                if (stackId && stackId !== "") {
                    pageStack.push(Qt.resolvedUrl("StackDetailPage.qml"), {
                        "stackId": stackId,
                        "primaryAssetId": assetId,
                        "primaryIsFavorite": isFavorite,
                        "primaryThumbhash": thumbhash,
                        "timelineAssetIndex": currentIndex
                    })
                } else {
                    pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                        "assetId": assetId,
                        "isFavorite": isFavorite,
                        "isVideo": isVideo,
                        "thumbhash": thumbhash,
                        "currentIndex": currentIndex
                    })
                }
            }
        }

        footer: Item {
            width: parent.width
            height: Theme.paddingLarge
        }

        VerticalScrollDecorator {}
    }

    Item {
        anchors.left: bucketsList.left
        anchors.right: bucketsList.right
        anchors.top: bucketsList.top
        anchors.topMargin: bucketsList.headerItem ? bucketsList.headerItem.height : 0
        anchors.bottom: bucketsList.bottom
        visible: timelineModel.loading && bucketCount === 0

        Column {
            width: parent.width
            spacing: Theme.paddingMedium
            anchors.centerIn: parent

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Large
                running: parent.parent.visible
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                //% "Loading timeline..."
                text: qsTrId("timelinePage.loading")
                color: Theme.secondaryHighlightColor
            }
        }
    }

    Item {
        anchors.left: bucketsList.left
        anchors.right: bucketsList.right
        anchors.top: bucketsList.top
        anchors.topMargin: bucketsList.headerItem ? bucketsList.headerItem.height : 0
        anchors.bottom: bucketsList.bottom
        visible: !timelineModel.loading && bucketCount === 0

        Column {
            width: parent.width
            spacing: Theme.paddingLarge
            anchors.centerIn: parent

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                source: page.activeFilter === "favorites" ? "image://theme/icon-m-favorite" : "image://theme/icon-m-image"
                color: Theme.highlightColor
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: page.activeFilter === "favorites"
                    //% "No favorites yet"
                    ? qsTrId("timelinePage.noFavoritesLabel")
                    //% "No assets yet"
                    : qsTrId("timelinePage.noAssetsLabel")
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: page.activeFilter === "favorites"
                    //% "Long-press an asset and add it to favorites to see it here"
                    ? qsTrId("timelinePage.noFavoritesInfo")
                    //% "Upload or import assets in Immich to start building your timeline"
                    : qsTrId("timelinePage.noAssetsInfo")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // Selection action bar
    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        selectedCount: timelineModel.selectedCount
        allAreFavorites: timelineModel.selectedCount > 0 && timelineModel.areAllSelectedFavorites()
        hasAnyFavorites: timelineModel.selectedCount > 0 && timelineModel.areAnySelectedFavorites()
        canStack: timelineModel.selectedCount > 1 && !timelineModel.isAnySelectedAStack()

        onStackSelected: {
            var selectedIds = timelineModel.getSelectedAssetIds()
            immichApi.createStack(selectedIds)
        }
        onAddToFavorites: {
            var selectedIds = timelineModel.getSelectedAssetIds()
            immichApi.toggleFavorite(selectedIds, true)
        }
        onRemoveFromFavorites: {
            var selectedIds = timelineModel.getSelectedAssetIds()
            immichApi.toggleFavorite(selectedIds, false)
        }
        onShare: {
            var selectedIds = timelineModel.getSelectedAssetIds()
            pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                assetIds: selectedIds,
                shareType: "INDIVIDUAL"
            })
        }
        onAddToAlbum: {
            var dialog = pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
                assetIds: timelineModel.getSelectedAssetIds()
            })
            dialog.accepted.connect(function() {
                timelineModel.clearSelection()
            })
        }
        onClearSelection: timelineModel.clearSelection()
        onDownload: {
            var selectedIds = timelineModel.getSelectedAssetIds()
            for (var i = 0; i < selectedIds.length; i++) {
                immichApi.downloadAsset(selectedIds[i])
            }
            timelineModel.clearSelection()
            notification.show(selectedIds.length === 1
                //% "Downloading asset..."
                ? qsTrId("timelinePage.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("timelinePage.downloadingAssets").arg(selectedIds.length))
        }
        onDeleteSelected: {
            var selectedIds = timelineModel.getSelectedAssetIds()
            deleteRemorse.execute(selectedIds.length === 1
                //% "Deleting asset"
                ? qsTrId("timelinePage.deletingAsset")
                //% "Deleting %1 assets"
                : qsTrId("timelinePage.deletingAssets").arg(selectedIds.length), function() {
                    immichApi.deleteAssets(selectedIds)
                    timelineModel.clearSelection()
            })
        }
    }

    ScrollToTopButton {
        targetFlickable: bucketsList
        actionBarHeight: selectionActionBar.shown ? selectionActionBar.contentHeight : 0
        forceHidden: selectionActionBar.activeMenuType !== ""
    }

    RemorsePopup {
        id: deleteRemorse
    }

    // Scroll-to-asset state
    property string pendingScrollAssetId: ""
    property int pendingScrollBucketIndex: -1
    property int pendingScrollAssetIndex: -1
    property real pendingScrollLastTargetY: -1
    property real pendingScrollLastBucketHeight: -1
    property int pendingScrollStablePasses: 0
    property int pendingScrollRetryCount: 0

    function prepareScrollTarget(bucketIndex) {
        bucketsList.positionViewAtIndex(bucketIndex, ListView.Beginning)
        var targetItem = findBucketItem(bucketIndex)
        if (!targetItem) return
        if (!targetItem.dataLoaded) {
            targetItem.loadBucketData()
        }
        if (!targetItem.assetsLoaded) {
            targetItem.requestAssets()
        }
    }

    function scrollToAssetPosition(bucketIndex, assetIndexInBucket) {
        var targetItem = findBucketItem(bucketIndex)
        if (!targetItem) {
            bucketsList.positionViewAtIndex(bucketIndex, ListView.Beginning)
            return { success: false }
        }

        if (assetIndexInBucket >= 0 && (!targetItem.assetsLoaded || !targetItem.bucketSubGroups)) {
            return { success: false }
        }

        var bucketY = targetItem.y

        // Add bucket header height
        var assetOffsetY = Theme.itemSizeSmall

        // Calculate exact Y offset within the bucket for the target asset
        if (assetIndexInBucket >= 0 && targetItem.bucketSubGroups) {
            var subGroups = targetItem.bucketSubGroups
            var assetsSoFar = 0
            for (var sg = 0; sg < subGroups.length; sg++) {
                var subGroup = subGroups[sg]
                var subGroupAssetCount = subGroup.assets ? subGroup.assets.length : 0

                if (assetsSoFar + subGroupAssetCount > assetIndexInBucket) {
                    // Target asset is in this subgroup
                    assetOffsetY += Theme.itemSizeExtraSmall
                    var indexInSubGroup = assetIndexInBucket - assetsSoFar
                    var rowInSubGroup = Math.floor(indexInSubGroup / page.assetsPerRow)
                    assetOffsetY += rowInSubGroup * page.cellSize
                    assetOffsetY += page.cellSize / 2
                    break
                }

                // Skip this entire subgroup
                assetOffsetY += Theme.itemSizeExtraSmall
                var rowsInSubGroup = Math.ceil(subGroupAssetCount / page.assetsPerRow)
                assetOffsetY += rowsInSubGroup * page.cellSize
                assetsSoFar += subGroupAssetCount
            }
        }

        // Center the target asset on screen
        var targetY = Math.max(0, Math.min(bucketY + assetOffsetY - bucketsList.height / 2, bucketsList.contentHeight - bucketsList.height))
        if (Math.abs(bucketsList.contentY - targetY) > 2) {
            bucketsList.contentY = targetY
        }
        return {
            success: true,
            targetY: targetY,
            bucketHeight: targetItem.height
        }
    }

    Connections {
        target: pendingScrollBucketIndex >= 0 ? bucketsList : null
        onContentHeightChanged: {
            scrollFinalizeTimer.restart()
        }
    }

    Connections {
        target: pendingScrollBucketIndex >= 0 ? timelineModel : null
        onBucketAssetsLoaded: {
            if (bucketIndex === pendingScrollBucketIndex) {
                scrollFinalizeTimer.restart()
            }
        }
    }

    // Finalize timer: waits for layout to settle and scrolls
    Timer {
        id: scrollFinalizeTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (pendingScrollBucketIndex >= 0) {
                prepareScrollTarget(pendingScrollBucketIndex)
                var scrollResult = scrollToAssetPosition(pendingScrollBucketIndex, pendingScrollAssetIndex)
                if (!scrollResult || typeof scrollResult !== "object" || !scrollResult.success) {
                    pendingScrollRetryCount += 1
                    if (pendingScrollRetryCount > 30) {
                        resetPendingScrollState()
                        return
                    }
                    scrollFinalizeTimer.restart()
                    return
                }

                var targetY = scrollResult.targetY
                var bucketHeight = scrollResult.bucketHeight
                if (targetY === undefined || bucketHeight === undefined) {
                    pendingScrollRetryCount += 1
                    if (pendingScrollRetryCount > 30) {
                        resetPendingScrollState()
                        return
                    }
                    scrollFinalizeTimer.restart()
                    return
                }

                var stableTarget = Math.abs(pendingScrollLastTargetY - targetY) <= 2
                var stableHeight = Math.abs(pendingScrollLastBucketHeight - bucketHeight) <= 2

                if (stableTarget && stableHeight) {
                    pendingScrollStablePasses += 1
                } else {
                    pendingScrollStablePasses = 0
                }

                pendingScrollLastTargetY = targetY
                pendingScrollLastBucketHeight = bucketHeight
                pendingScrollRetryCount = 0

                if (pendingScrollStablePasses < 1) {
                    scrollFinalizeTimer.restart()
                    return
                }
            }
            // Highlight the target asset
            if (pendingScrollAssetId !== "") {
                highlightAssetId = pendingScrollAssetId
                highlightClearTimer.restart()
            }
            // Clear pending state
            resetPendingScrollState()
        }
    }

    Timer {
        id: highlightClearTimer
        interval: 2500
        repeat: false
        onTriggered: highlightAssetId = ""
    }

    Connections {
        target: timelineModel
        onBucketLoadRequested: {
            immichApi.fetchTimelineBucket(page.contextId, timeBucket, page.queryParams)
        }
        onScrollToAssetRequested: {
            pendingScrollAssetId = assetId
            pendingScrollBucketIndex = bucketIndex
            pendingScrollAssetIndex = assetIndexInBucket
            pendingScrollLastTargetY = -1
            pendingScrollLastBucketHeight = -1
            pendingScrollStablePasses = 0
            pendingScrollRetryCount = 0

            if (timelineModel.isBucketLoaded(bucketIndex)) {
                prepareScrollTarget(bucketIndex)
                scrollFinalizeTimer.restart()
            } else {
                timelineModel.requestBucketLoad(bucketIndex)
            }
        }
    }

    Component.onCompleted: {
        page.refresh()
        page.memoriesLoading = true
        immichApi.fetchMemories()
    }

    Connections {
        target: immichApi
        onTimelineBucketsReceived: {
            if (context !== page.contextId) return
            timelineModel.loadBuckets(buckets)
            timelineModel.setLoading(false)
            if (pendingScrollBucketIndex < 0) {
                bucketsList.positionViewAtBeginning()
            }
        }
        onTimelineBucketReceived: {
            if (context !== page.contextId) return
            timelineModel.loadBucketAssets(timeBucket, bucketData)
        }
        onMemoriesReceived: {
            page.memoriesLoading = false
            if (page.memoriesBarItem) {
                page.memoriesBarItem.loadMemories(memories)
            } else {
                page.pendingMemoriesData = memories
            }
        }
        onErrorOccurred: {
            timelineModel.setLoading(false)
            notification.showError(error)
        }
        onAssetsDeleted: {
            notification.show(assetIds.length === 1
                //% "Deleted asset"
                ? qsTrId("timelinePage.deletedAsset")
                //% "Deleted %1 assets"
                : qsTrId("timelinePage.deletedAssets").arg(assetIds.length))
        }
        onAssetDownloaded: {
            //% "Downloaded to: %1"
            notification.show(qsTrId("timelinePage.downloaded").arg(filePath))
        }
        onAssetsAddedToAlbum: {
            timelineModel.clearSelection()
            //% "Added asset(s) to album"
            notification.show(qsTrId("timelinePage.addedToAlbum"))
        }
        onFavoritesToggled: {
            timelineModel.clearSelection()
            notification.show(isFavorite ? (assetIds.length === 1
                //% "Added asset to favorites"
                ? qsTrId("timelinePage.addedAssetToFavorites")
                //% "Added %1 assets to favorites"
                : qsTrId("timelinePage.addedAssetsToFavorites").arg(assetIds.length)) : (assetIds.length === 1
                //% "Removed asset from favorites"
                ? qsTrId("timelinePage.removedAssetFromFavorites")
                //% "Removed %1 assets from favorites"
                : qsTrId("timelinePage.removedAssetsFromFavorites").arg(assetIds.length)))
        }
        onAlbumCreated: {
            //% "Created album: %1"
            notification.show(qsTrId("timelinePage.createdAlbum").arg(albumName))
            // Refresh albums list
            immichApi.fetchAlbums()
        }
        onUploadAllComplete: {
            if (successCount > 0) {
                page.refresh()
            }
        }
        onStackCreated: {
            //% "Stack created"
            notification.show(qsTrId("timelinePage.stackCreated"))
            page.refresh()
        }
        onStackDeleted: {
            //% "Stack removed"
            notification.show(qsTrId("timelinePage.stackDeleted"))
            page.refresh()
        }
    }

    NotificationBanner {
        id: notification
        anchors.bottom: parent.bottom
    }
}
