import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"
import "../components/TimelineHelper.js" as TimelineHelper

Page {
    id: page

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property string sortOrder: "desc"
    property string contextId: "favorites"
    property var queryParams: ({"isFavorite": "true", "withStacked": "true", "order": sortOrder})
    property var heroAssetIds: []
    property bool heroInitialized: false

    TimelineModel {
        id: favoritesModel
    }

    function refresh() {
        favoritesModel.clear()
        favoritesModel.setLoading(true)
        heroInitialized = false
        queryParams = {"isFavorite": "true", "withStacked": "true", "order": sortOrder}
        immichApi.fetchTimelineBuckets(contextId, queryParams)
    }

    function updateHeroIds() {
        if (heroInitialized) return
        var ids = TimelineHelper.getHeroIds(favoritesModel)
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
        model: favoritesModel

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }

            MenuItem {
                text: page.sortOrder === "desc"
                    //% "Show oldest first"
                    ? qsTrId("pullDownMenu.showOldestFirst")
                    //% "Show newest first"
                    : qsTrId("pullDownMenu.showNewestFirst")
                onClicked: {
                    page.sortOrder = page.sortOrder === "desc" ? "asc" : "desc"
                    page.refresh()
                }
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
                        //% "Favorites"
                        text: qsTrId("favoritesPage.favorites")
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.bold: true
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        text: favoritesModel.totalCount === 1
                            //% "1 asset"
                            ? qsTrId("favoritesPage.asset")
                            //% "%1 assets"
                            : qsTrId("favoritesPage.assets").arg(favoritesModel.totalCount)
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryHighlightColor
                    }
                }
            }

            Column {
                width: parent.width
                visible: heroAssetIds.length === 0

                PageHeader {
                    title: qsTrId("favoritesPage.favorites")
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
            bucketKey: favoritesModel.getBucketTimeBucket(index)
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
            assetModel: favoritesModel

            onAssetClicked: {
                pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                    assetId: assetId,
                    isFavorite: isFavorite,
                    isVideo: isVideo,
                    thumbhash: thumbhash,
                    assetModel: favoritesModel,
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
        loading: favoritesModel.loading && favoritesModel.bucketCount === 0
        //% "Loading favorites..."
        message: qsTrId("favoritesPage.loading")
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
        visible: !favoritesModel.loading && favoritesModel.totalCount === 0
        iconSource: "image://theme/icon-m-favorite"
        //% "No favorite assets"
        message: qsTrId("favoritesPage.noAssets")
    }

    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: favoritesModel.selectedCount > 0
        selectedCount: favoritesModel.selectedCount
        allAreFavorites: true
        hasSelectedOtherOwner: favoritesModel.selectedCount > 0 && favoritesModel.hasSelectedOtherOwner()
        showArchive: true

        onRemoveFromFavorites: immichApi.toggleFavorite(favoritesModel.getSelectedAssetIds(), false)
        onShare: {
            pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                assetIds: favoritesModel.getSelectedAssetIds(),
                shareType: "INDIVIDUAL"
            })
        }
        onAddToAlbum: {
            pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
                assetIds: favoritesModel.getSelectedAssetIds()
            })
        }
        onClearSelection: favoritesModel.clearSelection()
        onDownload: {
            var ids = favoritesModel.getSelectedAssetIds()
            for (var i = 0; i < ids.length; i++) {
                immichApi.downloadAsset(ids[i])
            }
            favoritesModel.clearSelection()
            notification.show(ids.length === 1
                //% "Downloading asset..."
                ? qsTrId("notification.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("notification.downloadingAssets").arg(ids.length))
        }
        onDeleteSelected: {
            var selectedIds = favoritesModel.getSelectedAssetIds()
            deleteRemorse.execute(selectedIds.length > 1
                //% "Deleting %1 assets"
                ? qsTrId("notification.deletingAssets").arg(selectedIds.length)
                //% "Deleting asset"
                : qsTrId("notification.deletingAsset"), function() {
                    immichApi.deleteAssets(selectedIds)
                    favoritesModel.clearSelection()
            })
        }
        onMoveToArchive: immichApi.changeAssetVisibility(favoritesModel.getSelectedAssetIds(), "archive")
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
        anchors.bottom: favoritesModel.selectedCount > 0 ? selectionActionBar.top : parent.bottom
    }

    Component.onCompleted: {
        favoritesModel.setServerUrl(authManager.serverUrl)
        favoritesModel.setUserId(authManager.userId)
        page.refresh()
    }

    Connections {
        target: immichApi
        onTimelineBucketsReceived: {
            if (context !== page.contextId) return
            favoritesModel.loadBuckets(buckets)
            favoritesModel.setLoading(false)
            if (favoritesModel.getBucketCount() > 0) {
                favoritesModel.requestBucketLoad(0)
            }
        }
        onTimelineBucketReceived: {
            if (context !== page.contextId) return
            favoritesModel.loadBucketAssets(timeBucket, bucketData)
            page.updateHeroIds()
        }
        onFavoritesToggled: {
            favoritesModel.updateFavorites(assetIds, isFavorite)
            favoritesModel.clearSelection()
            if (!isFavorite) {
                notification.show(assetIds.length === 1
                    //% "Removed asset from favorites"
                    ? qsTrId("notification.removedAssetFromFavorites")
                    //% "Removed %1 assets from favorites"
                    : qsTrId("notification.removedAssetsFromFavorites").arg(assetIds.length))
                page.refresh()
            }
        }
        onAssetsDeleted: {
            page.refresh()
            notification.show(assetIds.length === 1
                //% "Deleted asset"
                ? qsTrId("notification.deletedAsset")
                //% "Deleted %1 assets"
                : qsTrId("notification.deletedAssets").arg(assetIds.length))
        }
        onAssetVisibilityChanged: {
            if (visibility === "archive") {
                //% "Moved to archive"
                notification.show(qsTrId("notification.movedToArchive"))
            } else if (visibility === "locked") {
                //% "Moved to locked folder"
                notification.show(qsTrId("notification.movedToLockedFolder"))
            }
            favoritesModel.clearSelection()
            page.refresh()
        }
    }

    Connections {
        target: favoritesModel
        onBucketLoadRequested: {
            immichApi.fetchTimelineBucket(page.contextId, timeBucket, page.queryParams)
        }
    }
}
