import QtQuick 2.6
import QtFeedback 5.0
import Sailfish.Silica 1.0
import "../components"
import "../components/TimelineHelper.js" as TimelineHelper

Page {
    id: page
    objectName: "timelinePage"

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property int bucketCount: timelineModel.bucketCount

    // Filter state
    property string activeFilter: "taken"
    property string sortOrder: "desc"
    property bool showFavorites: false

    // Highlight state for scroll-to-asset
    property string highlightAssetId: ""

    function refresh() {
        highlightAssetId = ""
        grid.resetScroll()
        timelineModel.clear()
        timelineModel.setLoading(true)
        var isFavorite = showFavorites
        var showCreatedAt = page.activeFilter === "created"
        timelineModel.setGroupByCreatedAt(showCreatedAt)
        var params = { "order": sortOrder }
        if (isFavorite) params["isFavorite"] = true
        timelineModel.queryParams = params
        timelineModel.fetchBuckets()
    }

    TimelineGrid {
        id: grid
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: selectionActionBar.shown ? selectionActionBar.top : parent.bottom

        assetModel: timelineModel
        columns: page.assetsPerRow
        highlightAssetId: page.highlightAssetId

        PullDownMenu {
            MenuItem {
                //% "Settings"
                text: qsTrId("pullDownMenu.settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }

            MenuItem {
                //% "Library"
                text: qsTrId("pullDownMenu.library")
                onClicked: pageStack.push(Qt.resolvedUrl("LibraryPage.qml"))
            }

            MenuItem {
                //% "Search"
                text: qsTrId("pullDownMenu.search")
                onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
            }

            MenuItem {
                //% "Albums"
                text: qsTrId("pullDownMenu.albums")
                onClicked: pageStack.push(Qt.resolvedUrl("AlbumsPage.qml"))
            }

            MenuItem {
                //% "Upload"
                text: qsTrId("pullDownMenu.upload")
                onClicked: pageStack.push(Qt.resolvedUrl("UploadPage.qml"))
            }

            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: syncEngine.sync()
            }
        }

        headerComponent: Component {
            Column {
                property alias memoriesBar: memoriesBar
                width: grid.width
                spacing: 0

                PageHeader {
                    //% "Timeline"
                    title: qsTrId("timelinePage.timeline")
                }

                MemoriesBar {
                    id: memoriesBar
                    width: parent.width
                    visible: settingsManager.showMemoriesBar
                }

                FilterBar {
                    activeFilter: page.activeFilter
                    sortOrder: page.sortOrder
                    showFavorites: page.showFavorites
                    onFilterActivated: {
                        page.activeFilter = filter
                        page.refresh()
                    }
                    onFilterFavorites: {
                        page.showFavorites = showFavorites
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
        }

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

        onLocalAssetClicked: {
            pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                "assetId": "",
                "currentIndex": globalIndex
            })
        }

        onColumnsSettled: {
            settingsManager.assetsPerRow = isPortrait ? columns : Math.ceil(columns / 2)
        }

        onAssetScrolled: {
            page.highlightAssetId = assetId
            highlightClearTimer.restart()
        }
    }

    // Scrubber
    Item {
        id: timelineScrubber
        anchors {
            right: parent.right
            top: grid.top
            bottom: grid.bottom
            topMargin: grid.headerHeight
        }
        width: Theme.iconSizeSmall
        visible: bucketCount > 5 && timelineModel.selectedCount === 0
        z: 10

        property real scrollFraction: {
            var r = grid.visibleArea.heightRatio
            if (r <= 0 || r >= 1) return 0
            return grid.visibleArea.yPosition / (1 - r)
        }
        property bool thumbVisible: scrubArea.pressed || fadeTimer.running

        Timer {
            id: fadeTimer
            interval: 1500
            repeat: false
        }

        Connections {
            target: grid
            onContentYChanged: {
                if (!scrubArea.pressed && grid.moving) {
                    fadeTimer.restart()
                }
            }
            onMovingChanged: {
                if (grid.moving) {
                    fadeTimer.restart()
                }
            }
        }

        Rectangle {
            anchors {
                right: parent.right
                top: parent.top
                bottom: parent.bottom
            }
            width: Theme.paddingSmall
            color: Theme.secondaryColor
            opacity: timelineScrubber.thumbVisible ? (scrubArea.pressed ? 0.5 : 0.3) : 0
            radius: width / 2
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }

        Rectangle {
            id: scrubHandle
            width: Theme.iconSizeSmall
            height: width
            radius: width / 2
            anchors.right: parent.right
            color: Theme.highlightColor
            opacity: timelineScrubber.thumbVisible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            y: scrubArea.pressed ? Math.max(0, Math.min(timelineScrubber.height - height, scrubArea.mouseY - height / 2)) : Math.max(0, Math.min(timelineScrubber.height - height, timelineScrubber.scrollFraction * (timelineScrubber.height - height)))
        }

        Label {
            id: scrubMonthLabel
            visible: scrubArea.pressed && text !== ""
            anchors {
                right: scrubHandle.left
                rightMargin: Theme.paddingMedium
                verticalCenter: scrubHandle.verticalCenter
            }
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.highlightColor
        }

        ThemeEffect {
            id: scrubEffect
            effect: ThemeEffect.Press
        }

        MouseArea {
            id: scrubArea
            anchors.fill: parent
            preventStealing: true
            property string lastLabel: ""

            function scrubTo(posY) {
                var h = timelineScrubber.height
                if (h <= 0 || timelineModel.renderRowCount <= 0) return
                var frac = Math.max(0, Math.min(1, posY / h))
                var maxY = Math.max(1, grid.contentHeight - grid.height)
                var targetY = frac * maxY
                var label = ""

                if (timelineModel.bucketCount >= 12) {
                    var entry = timelineModel.nearestMonthEntry(Math.max(0, targetY - grid.headerHeight))
                    if (entry && entry.y !== undefined) {
                        grid.contentY = entry.y + grid.headerHeight
                        label = entry.label
                    } else {
                        grid.contentY = targetY
                    }
                } else {
                    grid.contentY = targetY
                    var rowIndex = timelineModel.firstRowAtY(Math.max(0, targetY - grid.headerHeight))
                    var row = timelineModel.renderRowAt(rowIndex)
                    label = row && row.bucketIndex !== undefined ? timelineModel.bucketMonthYear(row.bucketIndex) : ""
                }

                if (label !== "" && label !== lastLabel) {
                    lastLabel = label
                    scrubMonthLabel.text = label
                    scrubEffect.play()
                }
            }

            onPressed: {
                lastLabel = ""
                fadeTimer.stop()
                scrubTo(mouse.y)
            }
            onPositionChanged: if (pressed) scrubTo(mouse.y)
            onReleased: {
                lastLabel = ""
                fadeTimer.restart()
            }
        }
    }

    LoadingIndicator {
        anchors {
            left: grid.left
            right: grid.right
            top: grid.top
            topMargin: grid.headerHeight
            bottom: grid.bottom
        }
        loading: (syncEngine.syncing || timelineModel.loading) && bucketCount === 0
        message: syncEngine.syncing
            //% "Synchronizing timeline..."
            ? qsTrId("timelinePage.syncing")
            //% "Loading timeline..."
            : qsTrId("timelinePage.loading")
    }

    EmptyState {
        anchors {
            left: grid.left
            right: grid.right
            top: grid.top
            topMargin: grid.headerHeight
            bottom: grid.bottom
        }
        visible: !syncEngine.syncing && !timelineModel.loading && bucketCount === 0
        iconSource: page.showFavorites ? "image://theme/icon-m-favorite" : "image://theme/icon-m-image"
        message: page.showFavorites
            //% "No favorites yet"
            ? qsTrId("timelinePage.noFavoritesLabel")
            //% "No assets yet"
            : qsTrId("timelinePage.noAssetsLabel")
        hint: page.showFavorites
            //% "Long-press an asset and add it to favorites to see it here"
            ? qsTrId("timelinePage.noFavoritesInfo")
            //% "Upload or import assets in Immich to start building your timeline"
            : qsTrId("timelinePage.noAssetsInfo")
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
        canStack: timelineModel.selectedCount > 1 && !timelineModel.isAnySelectedAStack() && !timelineModel.hasSelectedOtherOwner()
        hasSelectedOtherOwner: timelineModel.selectedCount > 0 && timelineModel.hasSelectedOtherOwner()
        selectionHasLocal: timelineModel.selectedCount > 0 && timelineModel.hasSelectedLocal()
        selectionHasRemote: timelineModel.selectedCount > 0 && timelineModel.hasSelectedRemote()
        showArchive: true

        onStackSelected: {
            var selectedIds = timelineModel.getSelectedRemoteIds()
            if (selectedIds.length > 0) {
                immichApi.createStack(selectedIds)
            }
        }
        onAddToFavorites: {
            var selectedIds = timelineModel.getSelectedRemoteIds()
            if (selectedIds.length > 0) {
                immichApi.toggleFavorite(selectedIds, true)
            }
        }
        onRemoveFromFavorites: {
            var selectedIds = timelineModel.getSelectedRemoteIds()
            if (selectedIds.length > 0) {
                immichApi.toggleFavorite(selectedIds, false)
            }
        }
        onShare: {
            var selectedIds = timelineModel.getSelectedRemoteIds()
            if (selectedIds.length === 0) return
            pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                assetIds: selectedIds,
                shareType: "INDIVIDUAL"
            })
        }
        onAddToAlbum: {
            var remoteIds = timelineModel.getSelectedRemoteIds()
            if (remoteIds.length === 0) return
            var dialog = pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
                assetIds: remoteIds
            })
            dialog.accepted.connect(function() {
                timelineModel.clearSelection()
            })
        }
        onUpload: {
            var localPaths = timelineModel.getSelectedLocalPaths()
            if (localPaths.length === 0) return
            immichApi.uploadAssets(localPaths)
            timelineModel.clearSelection()
            notification.show(localPaths.length === 1
                //% "Uploading file"
                ? qsTrId("notification.uploadingFile")
                //% "Uploading %1 files"
                : qsTrId("notification.uploadingFiles").arg(localPaths.length))
        }
        onDownload: {
            var selectedIds = timelineModel.getSelectedRemoteIds()
            if (selectedIds.length === 0) return
            for (var i = 0; i < selectedIds.length; i++) {
                immichApi.downloadAsset(selectedIds[i])
            }
            timelineModel.clearSelection()
            notification.show(selectedIds.length === 1
                //% "Downloading asset"
                ? qsTrId("notification.downloadingAsset")
                //% "Downloading %1 assets"
                : qsTrId("notification.downloadingAssets").arg(selectedIds.length))
        }
        onDeleteSelected: {
            var remoteIds = timelineModel.getSelectedRemoteIds()
            var localPaths = timelineModel.getSelectedLocalPaths()
            var total = remoteIds.length + localPaths.length
            if (total === 0) return
            deleteRemorse.execute(total === 1
                //% "Deleting asset"
                ? qsTrId("notification.deletingAsset")
                //% "Deleting %1 assets"
                : qsTrId("notification.deletingAssets").arg(total), function() {
                    if (remoteIds.length > 0) {
                        immichApi.deleteAssets(remoteIds)
                    }
                    if (localPaths.length > 0) {
                        timelineModel.removeLocalFiles(localPaths)
                    }
                    timelineModel.clearSelection()
            })
        }
        onMoveToArchive: {
            var selectedIds = timelineModel.getSelectedRemoteIds()
            if (selectedIds.length === 0) return
            immichApi.changeAssetVisibility(selectedIds, "archive")
            timelineModel.clearSelection()
        }
        onMoveToLockedFolder: {
            var selectedIds = timelineModel.getSelectedRemoteIds()
            if (selectedIds.length === 0) return
            immichApi.changeAssetVisibility(selectedIds, "locked")
            timelineModel.clearSelection()
        }
    }

    ScrollToTopButton {
        targetFlickable: grid
        actionBarHeight: selectionActionBar.shown ? selectionActionBar.contentHeight : 0
        forceHidden: selectionActionBar.activeMenuType !== ""
    }

    SelectedCountButton {
        selectedCount: timelineModel.selectedCount
        actionBarHeight: selectionActionBar.shown ? selectionActionBar.contentHeight : 0
        forceHidden: selectionActionBar.activeMenuType !== ""
        onClearSelection: timelineModel.clearSelection()
    }

    RemorsePopup {
        id: deleteRemorse
    }

    Timer {
        id: highlightClearTimer
        interval: 2500
        repeat: false
        onTriggered: highlightAssetId = ""
    }

    Component.onCompleted: page.refresh()

    Connections {
        target: timelineModel
        onScrollToAssetRequested: grid.scrollToAssetRow(bucketIndex, assetIndexInBucket, assetId)
    }

    Connections {
        target: immichApi
        onErrorOccurred: {
            timelineModel.setLoading(false)
            notification.showError(error)
        }
        onAssetsDeleted: {
            notification.show(TimelineHelper.deletedNotification(assetIds.length))
        }
        onAssetDownloaded: {
            //% "Downloaded to: %1"
            notification.show(qsTrId("notification.downloaded").arg(filePath))
        }
        onAssetsAddedToAlbum: {
            timelineModel.clearSelection()
            //% "Added asset(s) to album"
            notification.show(qsTrId("notification.addedToAlbum"))
        }
        onFavoritesToggled: {
            timelineModel.clearSelection()
            notification.show(TimelineHelper.favoritesNotification(isFavorite, assetIds.length))
        }
        onAlbumCreated: {
            //% "Created album: %1"
            notification.show(qsTrId("notification.createdAlbum").arg(albumName))
        }
        onStackCreated: {
            timelineModel.clearSelection()
            //% "Stack created"
            notification.show(qsTrId("notification.stackCreated"))
        }
        onStackDeleted: {
            //% "Stack removed"
            notification.show(qsTrId("notification.stackDeleted"))
        }
        onAssetVisibilityChanged: {
            if (visibility === "archive") {
                //% "Moved to archive"
                notification.show(qsTrId("notification.movedToArchive"))
            } else if (visibility === "locked") {
                //% "Moved to locked folder"
                notification.show(qsTrId("notification.movedToLockedFolder"))
            }
        }
    }

    NotificationBanner {
        id: notification
        anchors.bottom: parent.bottom
    }
}
