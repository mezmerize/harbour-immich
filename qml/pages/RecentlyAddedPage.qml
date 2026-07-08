import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"
import "../components/TimelineHelper.js" as TimelineHelper

Page {
    id: page

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property string activeFilter: "all"
    property string sortOrder: "desc"
    property string contextId: "recentlyAdded"
    property var queryParams: ({"visibility": "timeline", "orderBy": "createdAt", "order": sortOrder})
    property var heroAssetIds: []
    property bool heroInitialized: false

    TimelineModel {
        id: recentlyAddedModel
        groupByCreatedAt: true
    }

    function refresh() {
        var params = {"visibility": "timeline", "orderBy": "createdAt", "order": sortOrder}
        if (activeFilter === "favorites") params["isFavorite"] = "true"
        queryParams = params
        recentlyAddedModel.clear()
        recentlyAddedModel.setLoading(true)
        heroInitialized = false
        immichApi.fetchTimelineBuckets(contextId, queryParams)
    }

    function updateHeroIds() {
        if (heroInitialized) return
        var ids = TimelineHelper.getHeroIds(recentlyAddedModel)
        if (ids.length > 0) {
            heroAssetIds = ids
            heroInitialized = true
            scrollToTopTimer.restart()
        }
    }

    Timer {
        id: scrollToTopTimer
        interval: 50
        repeat: false
        onTriggered: bucketsList.positionViewAtBeginning()
    }

    SilicaListView {
        id: bucketsList
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: selectionActionBar.visible ? selectionActionBar.top : parent.bottom
        clip: true
        cacheBuffer: Math.max(height * 2, 2000)
        model: recentlyAddedModel

        PullDownMenu {
            enabled: recentlyAddedModel.selectedCount === 0

            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }
        }

        header: Column {
            width: bucketsList.width

            HeroImageRotator {
                width: parent.width
                height: heroAssetIds.length > 0 ? page.height / 2 : 0
                assetIds: heroAssetIds
                active: page.status === PageStatus.Active && heroAssetIds.length > 0
                visible: heroAssetIds.length > 0

                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        leftMargin: Theme.horizontalPageMargin
                        rightMargin: Theme.horizontalPageMargin
                        bottomMargin: Theme.paddingLarge
                    }
                    spacing: Theme.paddingSmall / 2

                    Label {
                        width: parent.width
                        //% "Recently Added"
                        text: qsTrId("recentlyAddedPage.recentlyAdded")
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.bold: true
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        text: recentlyAddedModel.totalCount === 1
                            //% "1 asset"
                            ? qsTrId("recentlyAddedPage.asset")
                            //% "%1 assets"
                            : qsTrId("recentlyAddedPage.assets").arg(recentlyAddedModel.totalCount)
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryHighlightColor
                    }
                }
            }

            Column {
                width: parent.width
                visible: heroAssetIds.length === 0

                PageHeader {
                    title: qsTrId("recentlyAddedPage.recentlyAdded")
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
            bucketKey: recentlyAddedModel.getBucketTimeBucket(index)
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
            assetModel: recentlyAddedModel

            onAssetClicked: {
                pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                    assetId: assetId,
                    isFavorite: isFavorite,
                    isVideo: isVideo,
                    thumbhash: thumbhash,
                    assetModel: recentlyAddedModel,
                    currentIndex: currentIndex
                })
            }
        }

        footer: Item {
            width: parent.width
            height: Theme.paddingLarge
        }

        VerticalScrollDecorator {}
    }

    // Loading
    LoadingIndicator {
        anchors {
            left: bucketsList.left
            right: bucketsList.right
            bottom: bucketsList.bottom
            top: bucketsList.top
            topMargin: heroAssetIds.length > 0 ? page.height / 2 : 0
        }
        loading: recentlyAddedModel.loading && recentlyAddedModel.bucketCount === 0
        //% "Loading recently added assets..."
        message: qsTrId("recentlyAddedPage.loading")
    }

    // Empty state
    EmptyState {
        anchors {
            left: bucketsList.left
            right: bucketsList.right
            bottom: bucketsList.bottom
            top: bucketsList.top
            topMargin: heroAssetIds.length > 0 ? page.height / 2 : 0
        }
        visible: !recentlyAddedModel.loading && recentlyAddedModel.totalCount === 0
        iconSource: "image://theme/icon-m-cloud-upload"
        //% "No recently added assets"
        message: qsTrId("recentlyAddedPage.noAssets")
    }

    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: recentlyAddedModel.selectedCount > 0
        selectedCount: recentlyAddedModel.selectedCount
        allAreFavorites: recentlyAddedModel.selectedCount > 0 && recentlyAddedModel.areAllSelectedFavorites()
        hasSelectedOtherOwner: recentlyAddedModel.selectedCount > 0 && recentlyAddedModel.hasSelectedOtherOwner()
        showArchive: true

        onAddToFavorites: immichApi.toggleFavorite(recentlyAddedModel.getSelectedAssetIds(), true)
        onRemoveFromFavorites: immichApi.toggleFavorite(recentlyAddedModel.getSelectedAssetIds(), false)
        onShare: {
            pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                assetIds: recentlyAddedModel.getSelectedAssetIds(),
                shareType: "INDIVIDUAL"
            })
        }
        onAddToAlbum: {
            pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
                assetIds: recentlyAddedModel.getSelectedAssetIds()
            })
        }
        onClearSelection: recentlyAddedModel.clearSelection()
        onDownload: {
            var ids = recentlyAddedModel.getSelectedAssetIds()
            for (var i = 0; i < ids.length; i++) {
                immichApi.downloadAsset(ids[i])
            }
            recentlyAddedModel.clearSelection()
            notification.show(ids.length === 1
                //% "Downloading asset..."
                ? qsTrId("notification.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("notification.downloadingAssets").arg(ids.length))
        }
        onDeleteSelected: {
            var selectedIds = recentlyAddedModel.getSelectedAssetIds()
            deleteRemorse.execute(selectedIds.length > 1
                //% "Deleting %1 assets"
                ? qsTrId("notification.deletingAssets").arg(selectedIds.length)
                //% "Deleting asset"
                : qsTrId("notification.deletingAsset"), function() {
                    immichApi.deleteAssets(selectedIds)
                    recentlyAddedModel.clearSelection()
            })
        }
        onMoveToArchive: immichApi.changeAssetVisibility(recentlyAddedModel.getSelectedAssetIds(), "archive")
    }

    RemorsePopup {
        id: deleteRemorse
    }

    ScrollToTopButton {
        targetFlickable: bucketsList
        actionBarHeight: selectionActionBar.visible ? selectionActionBar.contentHeight : 0
        forceHidden: selectionActionBar.activeMenuType !== ""
    }

    NotificationBanner {
        id: notification
        anchors.bottom: recentlyAddedModel.selectedCount > 0 ? selectionActionBar.top : parent.bottom
    }

    Component.onCompleted: {
        recentlyAddedModel.setServerUrl(authManager.serverUrl)
        recentlyAddedModel.setUserId(authManager.userId)
        page.refresh()
    }

    Connections {
        target: immichApi
        onTimelineBucketsReceived: {
            if (context !== page.contextId) return
            recentlyAddedModel.loadBuckets(buckets)
            recentlyAddedModel.setLoading(false)
            if (recentlyAddedModel.getBucketCount() > 0) {
                recentlyAddedModel.requestBucketLoad(0)
            }
        }
        onTimelineBucketReceived: {
            if (context !== page.contextId) return
            recentlyAddedModel.loadBucketAssets(timeBucket, bucketData)
            page.updateHeroIds()
        }
        onFavoritesToggled: {
            recentlyAddedModel.updateFavorites(assetIds, isFavorite)
            recentlyAddedModel.clearSelection()
            notification.show(isFavorite ? (assetIds.length === 1
                //% "Added asset to favorites"
                ? qsTrId("notification.addedAssetToFavorites")
                //% "Added %1 assets to favorites"
                : qsTrId("notification.addedAssetsToFavorites").arg(assetIds.length)) : (assetIds.length === 1
                //% "Removed asset from favorites"
                ? qsTrId("notification.removedAssetFromFavorites")
                //% "Removed %1 assets from favorites"
                : qsTrId("notification.removedAssetsFromFavorites").arg(assetIds.length)))
        }
        onAssetVisibilityChanged: {
            if (visibility === "archive") {
                //% "Moved to archive"
                notification.show(qsTrId("notification.movedToArchive"))
            } else if (visibility === "locked") {
                //% "Moved to locked folder"
                notification.show(qsTrId("notification.movedToLockedFolder"))
            }
            recentlyAddedModel.clearSelection()
            page.refresh()
        }
        onAssetsDeleted: {
            page.refresh()
            notification.show(assetIds.length === 1
                //% "Deleted asset"
                ? qsTrId("notification.deletedAsset")
                //% "Deleted %1 assets"
                : qsTrId("notification.deletedAssets").arg(assetIds.length))
        }
    }

    Connections {
        target: recentlyAddedModel
        onBucketLoadRequested: {
            immichApi.fetchTimelineBucket(page.contextId, timeBucket, page.queryParams)
        }
    }
}
