import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"
import "../components/TimelineHelper.js" as TimelineHelper

Page {
    id: page

    property string albumId
    property string albumName
    property string albumDescription: ""
    property string albumStartDate: ""
    property string albumEndDate: ""

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property string activeFilter: "taken"
    property string sortOrder: "desc"
    property bool showFavorites: false
    property string contextId: "album-" + albumId
    property var queryParams: ({"albumId": albumId, "order": sortOrder})
    property var heroAssetIds: []
    property bool heroInitialized: false
    property string dateRange: ""

    TimelineModel {
        id: albumModel
    }

    function refresh() {
        albumModel.clear()
        albumModel.setLoading(true)
        heroInitialized = false
        var showCreatedAt = page.activeFilter === "created"
        albumModel.setGroupByCreatedAt(showCreatedAt)
        var params = {"albumId": albumId, "order": sortOrder}
        if (showFavorites) params["isFavorite"] = "true"
        if (showCreatedAt) params["orderBy"] = "createdAt"
        queryParams = params
        immichApi.fetchTimelineBuckets(contextId, queryParams)
    }

    function updateHeroIds() {
        if (heroInitialized) return
        var ids = TimelineHelper.getHeroIds(albumModel)
        if (ids.length > 0) {
            heroAssetIds = ids
            heroInitialized = true
            scrollToTopTimer.restart()
        }
    }

    function updateDateRange() {
        dateRange = TimelineHelper.computeDateRange(albumStartDate, albumEndDate)
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
        model: albumModel

        PullDownMenu {
            enabled: albumModel.selectedCount === 0

            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }

            MenuItem {
                //% "Information"
                text: qsTrId("pullDownMenu.information")
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("AlbumInfoPage.qml"), {
                        albumId: albumId
                    })
                }
            }

            MenuItem {
                //% "Share album"
                text: qsTrId("pullDownMenu.shareAlbum")
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                        albumId: albumId,
                        shareType: "ALBUM"
                    })
                }
            }
        }

        header: Column {
            width: bucketsList.width

            // Hero section
            HeroImageRotator {
                width: parent.width
                height: heroAssetIds.length > 0 ? page.height / 2 : 0
                assetIds: heroAssetIds
                active: page.status === PageStatus.Active && heroAssetIds.length > 0
                visible: heroAssetIds.length > 0

                // Album info overlay
                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.bottomMargin: Theme.paddingLarge
                    spacing: Theme.paddingSmall / 2

                    Label {
                        width: parent.width
                        text: albumName
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.bold: true
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        width: parent.width
                        text: albumDescription
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        visible: albumDescription !== ""
                    }

                    Row {
                        spacing: Theme.paddingMedium

                        Label {
                            text: albumModel.totalCount === 1
                                //% "1 asset"
                                ? qsTrId("albumDetailPage.asset")
                                //% "%1 assets"
                                : qsTrId("albumDetailPage.assets").arg(albumModel.totalCount)
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryHighlightColor
                        }

                        Label {
                            text: "·"
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryHighlightColor
                            visible: dateRange !== ""
                        }

                        Label {
                            text: dateRange
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryHighlightColor
                            visible: dateRange !== ""
                        }
                    }
                }
            }

            // No hero images (most likely due to no assets at all)
            Column {
                width: parent.width
                visible: heroAssetIds.length === 0

                PageHeader {
                    title: albumName
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: albumDescription
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    visible: albumDescription !== ""
                }

                Row {
                    x: Theme.horizontalPageMargin
                    spacing: Theme.paddingMedium

                    Label {
                        visible: albumModel.totalCount > 0
                        text: albumModel.totalCount === 1 ? qsTrId("albumDetailPage.asset") : qsTrId("albumDetailPage.assets").arg(albumModel.totalCount)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                    }

                    Label {
                        text: "·"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                        visible: dateRange !== ""
                    }

                    Label {
                        text: dateRange
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                        visible: dateRange !== ""
                    }
                }
            }

            TimelineFilterBar {
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

        delegate: TimelineBucketDelegate {
            width: bucketsList.width
            bucketIndex: index
            bucketKey: albumModel.getBucketTimeBucket(index)
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
            assetModel: albumModel

            onAssetClicked: {
                pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                    assetId: assetId,
                    isFavorite: isFavorite,
                    isVideo: isVideo,
                    thumbhash: thumbhash,
                    assetModel: albumModel,
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
        loading: albumModel.loading && albumModel.bucketCount === 0
        //% "Loading album assets..."
        message: qsTrId("albumDetailPage.loading")
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
        visible: !albumModel.loading && albumModel.totalCount === 0
        iconSource: "image://theme/icon-m-folder"
        message: page.showFavorites
            //% "No favorite assets in this album"
            ? qsTrId("albumDetailPage.noFavorites")
            //% "No assets in this album"
            : qsTrId("albumDetailPage.noAssets")
    }

    Component.onCompleted: {
        albumModel.setServerUrl(authManager.serverUrl)
        albumModel.setUserId(authManager.userId)
        page.refresh()
    }

    Connections {
        target: immichApi
        onTimelineBucketsReceived: {
            if (context !== page.contextId) return
            albumModel.loadBuckets(buckets)
            albumModel.setLoading(false)
            page.updateDateRange()
            if (albumModel.getBucketCount() > 0) {
                albumModel.requestBucketLoad(0)
            }
        }
        onTimelineBucketReceived: {
            if (context !== page.contextId) return
            albumModel.loadBucketAssets(timeBucket, bucketData)
            page.updateHeroIds()
        }
        onAlbumUpdated: {
            if (albumId === page.albumId) {
                page.albumName = albumName
                page.albumDescription = description
            }
        }
        onFavoritesToggled: {
            albumModel.updateFavorites(assetIds, isFavorite)
            albumModel.clearSelection()
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
        onAssetsDeleted: {
            page.refresh()
            notification.show(assetIds.length === 1
                //% "Deleted asset"
                ? qsTrId("notification.deletedAsset")
                //% "Deleted %1 assets"
                : qsTrId("notification.deletedAssets").arg(assetIds.length))
        }
        onAssetsRemovedFromAlbum: {
            if (albumId === page.albumId) {
                page.refresh()
            }
        }
        onAssetVisibilityChanged: {
            if (visibility === "archive") {
                //% "Moved to archive"
                notification.show(qsTrId("notification.movedToArchive"))
            } else if (visibility === "locked") {
                //% "Moved to locked folder"
                notification.show(qsTrId("notification.movedToLockedFolder"))
            }
            albumModel.clearSelection()
            page.refresh()
        }
    }

    Connections {
        target: albumModel
        onBucketLoadRequested: {
            immichApi.fetchTimelineBucket(page.contextId, timeBucket, page.queryParams)
        }
    }

    // Selection Action Bar
    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: albumModel.selectedCount > 0
        selectedCount: albumModel.selectedCount
        allAreFavorites: albumModel.selectedCount > 0 && albumModel.areAllSelectedFavorites()
        hasSelectedOtherOwner: albumModel.selectedCount > 0 && albumModel.hasSelectedOtherOwner()
        showArchive: true

        onAddToFavorites: immichApi.toggleFavorite(albumModel.getSelectedAssetIds(), true)
        onRemoveFromFavorites: immichApi.toggleFavorite(albumModel.getSelectedAssetIds(), false)
        onShare: {
            pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                assetIds: albumModel.getSelectedAssetIds(),
                shareType: "INDIVIDUAL"
            })
        }
        onAddToAlbum: {
            pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
                assetIds: albumModel.getSelectedAssetIds()
            })
        }
        onClearSelection: albumModel.clearSelection()
        onDownload: {
            var ids = albumModel.getSelectedAssetIds()
            for (var i = 0; i < ids.length; i++) {
                immichApi.downloadAsset(ids[i])
            }
            albumModel.clearSelection()
            notification.show(ids.length === 1
                //% "Downloading asset..."
                ? qsTrId("notification.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("notification.downloadingAssets").arg(ids.length))
        }
        onDeleteSelected: {
            var selectedIds = albumModel.getSelectedAssetIds()
            deleteRemorse.execute(selectedIds.length > 1
                //% "Deleting %1 assets
                ? qsTrId("notification.deletingAssets").arg(selectedIds.length)
                //% "Deleting asset
                : qsTrId("notification.deletingAsset"), function() {
                    immichApi.deleteAssets(selectedIds)
                    page.clearSelection()
            })
        }
        onMoveToArchive: {
            immichApi.changeAssetVisibility(albumModel.getSelectedAssetIds(), "archive")
            albumModel.clearSelection()
        }
        onMoveToLockedFolder: {
            immichApi.changeAssetVisibility(albumModel.getSelectedAssetIds(), "locked")
            albumModel.clearSelection()
        }
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
        anchors.bottom: albumModel.selectedCount > 0 ? selectionActionBar.top : parent.bottom
    }
}
