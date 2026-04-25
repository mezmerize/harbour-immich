import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"

Page {
    id: page

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property string activeFilter: "all"
    property string sortOrder: "desc"
    property string contextId: "archive"
    property var queryParams: ({"visibility": "archive", "order": sortOrder})
    property var heroAssetIds: []
    property bool heroInitialized: false

    TimelineModel {
        id: archiveModel
    }

    function refresh() {
        var params = {"visibility": "archive", "order": sortOrder}
        if (activeFilter === "favorites") params["isFavorite"] = "true"
        queryParams = params
        archiveModel.clear()
        archiveModel.setLoading(true)
        heroInitialized = false
        immichApi.fetchTimelineBuckets(contextId, queryParams)
    }

    function updateHeroIds() {
        if (heroInitialized) return
        var ids = []
        var bucketCount = archiveModel.getBucketCount()
        for (var b = 0; b < bucketCount && ids.length < 5; b++) {
            if (!archiveModel.isBucketLoaded(b)) continue
            var assets = archiveModel.getBucketAssets(b)
            for (var a = 0; a < assets.length && ids.length < 5; a++) {
                if (!assets[a].isVideo) ids.push(assets[a].id)
            }
        }
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
        model: archiveModel

        PullDownMenu {
            enabled: archiveModel.selectedCount === 0

            MenuItem {
                //% "Refresh"
                text: qsTrId("archivedPage.refresh")
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
                        //% "Archived"
                        text: qsTrId("archivedPage.archived")
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.bold: true
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        text: archiveModel.totalCount === 1
                            //% "1 asset"
                            ? qsTrId("archivedPage.asset")
                            //% "%1 assets"
                            : qsTrId("archivedPage.assets").arg(archiveModel.totalCount)
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryHighlightColor
                    }
                }
            }

            Column {
                width: parent.width
                visible: heroAssetIds.length === 0

                PageHeader {
                    title: qsTrId("archivedPage.archived")
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
            bucketKey: archiveModel.getBucketTimeBucket(index)
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
            assetModel: archiveModel

            onAssetClicked: {
                pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                    assetId: assetId,
                    isFavorite: isFavorite,
                    isVideo: isVideo,
                    thumbhash: thumbhash
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
        loading: archiveModel.loading && archiveModel.bucketCount === 0
        //% "Loading archived assets..."
        message: qsTrId("archivedPage.loading")
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
        visible: !archiveModel.loading && archiveModel.totalCount === 0
        iconSource: "image://theme/icon-m-file-archive-folder"
        //% "No archived assets"
        message: qsTrId("archivedPage.noAssets")
    }

    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: archiveModel.selectedCount > 0
        selectedCount: archiveModel.selectedCount
        allAreFavorites: archiveModel.selectedCount > 0 && archiveModel.areAllSelectedFavorites()
        hasSelectedOtherOwner: archiveModel.selectedCount > 0 && archiveModel.hasSelectedOtherOwner()
        showArchive: true
        isArchivePage: true

        onAddToFavorites: immichApi.toggleFavorite(archiveModel.getSelectedAssetIds(), true)
        onRemoveFromFavorites: immichApi.toggleFavorite(archiveModel.getSelectedAssetIds(), false)
        onShare: {
            pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                assetIds: archiveModel.getSelectedAssetIds(),
                shareType: "INDIVIDUAL"
            })
        }
        onAddToAlbum: {
            pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
                assetIds: archiveModel.getSelectedAssetIds()
            })
        }
        onClearSelection: archiveModel.clearSelection()
        onDownload: {
            var ids = archiveModel.getSelectedAssetIds()
            for (var i = 0; i < ids.length; i++) {
                immichApi.downloadAsset(ids[i])
            }
            archiveModel.clearSelection()
        }
        onDeleteSelected: {
            var selectedIds = archiveModel.getSelectedAssetIds()
            deleteRemorse.execute(selectedIds.length > 1
                //% "Deleting %1 assets"
                ? qsTrId("archivedPage.deletingAssets").arg(selectedIds.length)
                //% "Deleting asset"
                : qsTrId("archivedPage.deletingAsset"), function() {
                    immichApi.deleteAssets(selectedIds)
                    archiveModel.clearSelection()
            })
        }
        onRemoveFromArchive: {
            immichApi.changeAssetVisibility(archiveModel.getSelectedAssetIds(), "timeline")
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
        anchors.bottom: archiveModel.selectedCount > 0 ? selectionActionBar.top : parent.bottom
    }

    Component.onCompleted: {
        archiveModel.setServerUrl(authManager.serverUrl)
        archiveModel.setUserId(authManager.userId)
        page.refresh()
    }

    Connections {
        target: immichApi
        onTimelineBucketsReceived: {
            if (context !== page.contextId) return
            archiveModel.loadBuckets(buckets)
            archiveModel.setLoading(false)
            if (archiveModel.getBucketCount() > 0) {
                archiveModel.requestBucketLoad(0)
            }
        }
        onTimelineBucketReceived: {
            if (context !== page.contextId) return
            archiveModel.loadBucketAssets(timeBucket, bucketData)
            page.updateHeroIds()
        }
        onFavoritesToggled: {
            archiveModel.updateFavorites(assetIds, isFavorite)
            archiveModel.clearSelection()
        }
        onAssetVisibilityChanged: {
            if (visibility === "timeline") {
                //% "Removed from archive"
                notification.show(qsTrId("archivedPage.removedFromArchive"))
                page.refresh()
            }
            archiveModel.clearSelection()
        }
        onAssetsDeleted: {
            page.refresh()
        }
    }

    Connections {
        target: archiveModel
        onBucketLoadRequested: {
            immichApi.fetchTimelineBucket(page.contextId, timeBucket, page.queryParams)
        }
    }
}
