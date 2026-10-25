import QtQuick 2.6
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
    readonly property var heroAssetIds: albumModel.heroAssetIds
    property string dateRange: ""
    property bool showDateRange: dateRange !== "" && albumModel.totalCount > 0 && activeFilter === "taken" && !showFavorites

    TimelineModel {
        id: albumModel
        context: page.contextId
        queryParams: page.queryParams
    }

    function refresh() {
        bucketsList.resetScroll()
        albumModel.clear()
        albumModel.setLoading(true)
        var showCreatedAt = page.activeFilter === "created"
        albumModel.setGroupByCreatedAt(showCreatedAt)
        var params = {"albumId": albumId, "order": sortOrder}
        if (showFavorites) params["isFavorite"] = true
        queryParams = params
        albumModel.fetchBuckets()
    }

    function updateDateRange() {
        dateRange = TimelineHelper.computeDateRange(albumStartDate, albumEndDate)
    }

    TimelineGrid {
        id: bucketsList
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: selectionActionBar.visible ? selectionActionBar.top : parent.bottom
        assetModel: albumModel
        columns: page.assetsPerRow

        PullDownMenu {
            enabled: albumModel.selectedCount === 0

            MenuItem {
                //% "Remove album"
                text: qsTrId("pullDownMenu.removeAlbum")
                //% "Removing album"
                onClicked: deleteRemorse.execute(qsTrId("notification.removingAlbum"), function() {
                    immichApi.removeAlbum(albumId)
                })
            }

            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: syncEngine.sync()
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

        headerComponent: Component {
            Column {
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
                            visible: showDateRange
                        }

                        Label {
                            text: dateRange
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryHighlightColor
                            visible: showDateRange
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
                        text: albumModel.totalCount === 1 ? qsTrId("albumDetailPage.asset") : qsTrId("albumDetailPage.assets").arg(albumModel.totalCount)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                    }

                    Label {
                        text: "·"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                        visible: showDateRange
                    }

                    Label {
                        text: dateRange
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                        visible: showDateRange
                    }
                }
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
            pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                assetId: assetId,
                isFavorite: isFavorite,
                isVideo: isVideo,
                thumbhash: thumbhash,
                assetModel: albumModel,
                currentIndex: currentIndex,
                albumId: page.albumId
            })
        }

        onColumnsSettled: {
            settingsManager.assetsPerRow = isPortrait ? columns : Math.ceil(columns / 2)
        }
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
        albumModel.setUserId(authManager.userId)
        page.refresh()
    }

    Connections {
        target: immichApi
        onAlbumUpdated: {
            if (albumId === page.albumId) {
                page.albumName = albumName
                page.albumDescription = description
            }
        }
        onAlbumRemoved: if (albumId === page.albumId) pageStack.pop()
        onFavoritesToggled: {
            albumModel.clearSelection()
            notification.show(TimelineHelper.favoritesNotification(isFavorite, assetIds.length))
        }
        onAssetsDeleted: {
            notification.show(TimelineHelper.deletedNotification(assetIds.length))
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
        }
    }

    Connections {
        target: albumModel
        onBucketsLoaded: page.updateDateRange()
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
        onDownload: {
            var ids = albumModel.getSelectedAssetIds()
            for (var i = 0; i < ids.length; i++) {
                immichApi.downloadAsset(ids[i])
            }
            albumModel.clearSelection()
            notification.show(ids.length === 1
                //% "Downloading asset"
                ? qsTrId("notification.downloadingAsset")
                //% "Downloading %1 assets"
                : qsTrId("notification.downloadingAssets").arg(ids.length))
        }
        onDeleteSelected: {
            var selectedIds = albumModel.getSelectedAssetIds()
            deleteRemorse.execute(selectedIds.length > 1
                //% "Deleting %1 assets"
                ? qsTrId("notification.deletingAssets").arg(selectedIds.length)
                //% "Deleting asset"
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

    SelectedCountButton {
        selectedCount: albumModel.selectedCount
        actionBarHeight: selectionActionBar.visible ? selectionActionBar.contentHeight : 0
        forceHidden: selectionActionBar.activeMenuType !== ""
        onClearSelection: albumModel.clearSelection()
    }

    NotificationBanner {
        id: notification
        anchors.bottom: albumModel.selectedCount > 0 ? selectionActionBar.top : parent.bottom
    }
}
