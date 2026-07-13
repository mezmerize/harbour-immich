import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../components/AssetGroupHelper.js" as AssetGroupHelper

Page {
    id: page

    property string cityName
    property string stateName
    property string countryName

    property bool selectionMode: false
    property var selectedAssets: []
    property bool allSelectedAreFavorites: false
    property bool loading: true
    property string sortOrder: "desc"
    property bool showFavorites: false

    property var allAssets: []
    property var groupedAssets: []
    property var heroAssetIds: []
    property string dateRange: ""
    property int totalCount: 0

    function updateAllSelectedAreFavorites() {
        if (selectedAssets.length === 0) { allSelectedAreFavorites = false; return }
        for (var i = 0; i < allAssets.length; i++) {
            if (selectedAssets.indexOf(allAssets[i].id) > -1 && !allAssets[i].isFavorite) {
                allSelectedAreFavorites = false; return
            }
        }
        allSelectedAreFavorites = true
    }

    function toggleAssetSelection(assetId) {
        var index = selectedAssets.indexOf(assetId)
        if (index > -1) selectedAssets.splice(index, 1)
        else selectedAssets.push(assetId)
        selectedAssets = selectedAssets
        if (selectedAssets.length === 0) selectionMode = false
        updateAllSelectedAreFavorites()
    }

    function clearSelection() { selectedAssets = []; selectionMode = false }
    function isAssetSelected(assetId) { return selectedAssets.indexOf(assetId) > -1 }

    function refresh() {
        loading = true
        var params = { "order": sortOrder, "size": 250 }
        if (cityName) params["city"] = cityName
        if (stateName) params["state"] = stateName
        if (countryName) params["country"] = countryName
        if (showFavorites) params["isFavorite"] = "true"
        immichApi.searchByParameters(params)
    }

    function processAssets(results) {
        var r = AssetGroupHelper.processResults(results, sortOrder === "asc")
        allAssets = r.allAssets
        if (r.heroAssetIds.length > 0) heroAssetIds = r.heroAssetIds
        dateRange = r.dateRange
        groupedAssets = r.groupedAssets
        totalCount = r.totalCount
        loading = false
    }

    SilicaFlickable {
        id: flickable
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: selectionActionBar.visible ? selectionActionBar.top : parent.bottom
        contentHeight: contentColumn.height
        clip: true

        PullDownMenu {
            enabled: !page.selectionMode

            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }
        }

        Column {
            id: contentColumn
            width: parent.width

            // Hero section
            HeroImageRotator {
                width: parent.width
                height: heroAssetIds.length > 0 ? page.height / 2 : 0
                assetIds: heroAssetIds
                active: page.status === PageStatus.Active && heroAssetIds.length > 0
                visible: heroAssetIds.length > 0

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
                        text: cityName
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.bold: true
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Row {
                        spacing: Theme.paddingMedium

                        Label {
                            text: totalCount === 1
                                //% "1 asset"
                                ? qsTrId("placeDetailPage.asset")
                                //% "%1 assets"
                                : qsTrId("placeDetailPage.assets").arg(totalCount)
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
                    title: cityName
                }

                Row {
                    x: Theme.horizontalPageMargin
                    spacing: Theme.paddingMedium

                    Label {
                        text: totalCount === 1 ? qsTrId("placeDetailPage.asset") : qsTrId("placeDetailPage.assets").arg(totalCount)
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
                showActiveFilter: false
                sortOrder: page.sortOrder
                showFavorites: page.showFavorites
                onFilterFavorites: {
                    page.showFavorites = showFavorites
                    page.refresh()
                }
                onSortOrderToggled: {
                    page.sortOrder = order
                    page.refresh()
                }
            }

            GroupedAssetGrid {
                width: contentColumn.width
                groupedAssets: page.groupedAssets
                selectionMode: page.selectionMode
                selectedAssets: page.selectedAssets
                onAssetClicked: pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                    assetId: assetId,
                    isFavorite: isFavorite,
                    isVideo: isVideo,
                    thumbhash: thumbhash,
                    albumAssets: page.allAssets,
                    currentIndex: assetIndex
                })
                onAssetPressAndHold: {
                    if (!page.selectionMode) page.selectionMode = true
                    page.toggleAssetSelection(assetId)
                }
                onSubGroupSelectToggled: {
                    if (allSelected) {
                        for (var i = 0; i < assets.length; i++) {
                            if (page.isAssetSelected(assets[i].id)) page.toggleAssetSelection(assets[i].id)
                        }
                    } else {
                        if (!page.selectionMode) page.selectionMode = true
                        for (var i = 0; i < assets.length; i++) {
                            if (!page.isAssetSelected(assets[i].id)) page.toggleAssetSelection(assets[i].id)
                        }
                    }
                }
            }
        }
        VerticalScrollDecorator {}
    }

    // Loading
    LoadingIndicator {
        anchors {
            left: flickable.left
            right: flickable.right
            bottom: flickable.bottom
            top: flickable.top
            topMargin: heroAssetIds.length > 0 ? page.height / 2 : 0
        }
        loading: page.loading && allAssets.length === 0
        //% "Loading assets..."
        message: qsTrId("placeDetailPage.loading")
    }

    // Empty state
    EmptyState {
        anchors {
            left: flickable.left
            right: flickable.right
            bottom: flickable.bottom
            top: flickable.top
            topMargin: heroAssetIds.length > 0 ? page.height / 2 : 0
        }
        visible: !page.loading && allAssets.length === 0
        iconSource: "image://theme/icon-m-location"
        //% "No assets"
        message: qsTrId("placeDetailPage.noAssets")
    }

    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: page.selectionMode
        selectedCount: page.selectedAssets.length
        allAreFavorites: page.allSelectedAreFavorites
        showArchive: true

        onAddToFavorites: immichApi.toggleFavorite(page.selectedAssets, true)
        onRemoveFromFavorites: immichApi.toggleFavorite(page.selectedAssets, false)
        onShare: pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
            assetIds: page.selectedAssets,
            shareType: "INDIVIDUAL"
        })
        onAddToAlbum: pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
            assetIds: page.selectedAssets
        })
        onClearSelection: page.clearSelection()
        onDownload: {
            for (var i = 0; i < page.selectedAssets.length; i++) immichApi.downloadAsset(page.selectedAssets[i])
            page.clearSelection()
            notification.show(page.selectedAssets.length === 1
                //% "Deleted asset"
                ? qsTrId("notification.deletedAsset")
                //% "Deleted %1 assets"
                : qsTrId("notification.deletedAssets").arg(page.selectedAssets.length))
        }
        onDeleteSelected: {
            var ids = page.selectedAssets.slice()
            deleteRemorse.execute(ids.length > 1
                //% "Deleting %1 assets"
                ? qsTrId("notification.deletingAssets").arg(ids.length)
                //% "Deleting asset"
                : qsTrId("notification.deletingAsset"), function() {
                    immichApi.deleteAssets(page.selectedAssets)
                    page.clearSelection()
            })
        }
        onMoveToArchive: immichApi.changeAssetVisibility(page.selectedAssets, "archive")
    }

    RemorsePopup {
        id: deleteRemorse
    }

    ScrollToTopButton {
        targetFlickable: flickable
        actionBarHeight: selectionActionBar.visible ? selectionActionBar.contentHeight : 0
        forceHidden: selectionActionBar.activeMenuType !== ""
    }

    NotificationBanner {
        id: notification
        anchors.bottom: page.selectionMode ? selectionActionBar.top : parent.bottom
    }

    Component.onCompleted: page.refresh()

    Connections {
        target: immichApi
        onSearchResultsReceived: page.processAssets(results)
        onFavoritesToggled: {
            var updated = allAssets
            for (var i = 0; i < updated.length; i++) {
                if (assetIds.indexOf(updated[i].id) > -1) updated[i].isFavorite = isFavorite
            }
            allAssets = updated.slice()
            groupedAssets = AssetGroupHelper.groupByMonthAndDate(allAssets)
            page.clearSelection()
            notification.show(isFavorite ? (updated.length === 1
                //% "Added asset to favorites"
                ? qsTrId("notification.addedAssetToFavorites")
                //% "Added %1 assets to favorites"
                : qsTrId("notification.addedAssetsToFavorites").arg(updated.length)) : (updated.length === 1
                //% "Removed asset from favorites"
                ? qsTrId("notification.removedAssetFromFavorites")
                //% "Removed %1 assets from favorites"
                : qsTrId("notification.removedAssetsFromFavorites").arg(updated.length)))
        }
        onAssetVisibilityChanged: {
            if (visibility === "archive") {
                //% "Moved to archive"
                notification.show(qsTrId("notification.movedToArchive"))
            } else if (visibility === "locked") {
                //% "Moved to locked folder"
                notification.show(qsTrId("notification.movedToLockedFolder"))
            }
            page.clearSelection()
            page.refresh()
        }
        onAssetsDeleted: page.refresh()
    }
}
