import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../components/AssetGroupHelper.js" as AssetGroupHelper

Page {
    id: page

    property string albumId
    property string albumName
    property string albumDescription: ""
    property int assetCount
    property bool selectionMode: false
    property var selectedAssets: []
    property bool allSelectedAreFavorites: false
    property bool sortNewestFirst: true
    property bool loading: true

    // Grouped assets data
    property var allAssets: []       // flat list for navigation
    property var groupedAssets: []   // [{monthYear, groups: [{displayDate, assets: [...]}]}]
    property var heroAssetIds: []    // random asset IDs for hero rotation
    property string dateRange: ""

    function updateAllSelectedAreFavorites() {
        if (selectedAssets.length === 0) {
            allSelectedAreFavorites = false
            return
        }
        for (var i = 0; i < allAssets.length; i++) {
            if (selectedAssets.indexOf(allAssets[i].id) > -1 && !allAssets[i].isFavorite) {
                allSelectedAreFavorites = false
                return
            }
        }
        allSelectedAreFavorites = true
    }

    function toggleAssetSelection(assetId) {
        var index = selectedAssets.indexOf(assetId)
        if (index > -1) {
            selectedAssets.splice(index, 1)
        } else {
            selectedAssets.push(assetId)
        }
        selectedAssets = selectedAssets
        if (selectedAssets.length === 0) {
            selectionMode = false
        }
        updateAllSelectedAreFavorites()
    }

    function clearSelection() {
        selectedAssets = []
        selectionMode = false
    }

    function isAssetSelected(assetId) {
        return selectedAssets.indexOf(assetId) > -1
    }

    function processAlbumDetails(details) {
        albumName = details.albumName || albumName
        albumDescription = details.description || ""
        assetCount = details.assetCount || 0

        var r = AssetGroupHelper.processResults(details.assets || [], !sortNewestFirst)
        allAssets = r.allAssets
        heroAssetIds = r.heroAssetIds
        dateRange = r.dateRange
        groupedAssets = r.groupedAssets
        loading = false
    }

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: page.width / assetsPerRow

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
                text: qsTrId("albumDetailPage.refresh")
                onClicked: {
                    page.loading = true
                    immichApi.fetchAlbumDetails(albumId)
                }
            }

            MenuItem {
                //% "Information"
                text: qsTrId("albumDetailPage.information")
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("AlbumInfoPage.qml"), {
                        albumId: albumId
                    })
                }
            }

            MenuItem {
                //% "Share album"
                text: qsTrId("albumDetailPage.share")
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                        albumId: albumId,
                        shareType: "ALBUM"
                    })
                }
            }

            MenuItem {
                text: sortNewestFirst
                    //% "Show oldest first"
                    ? qsTrId("albumDetailPage.showOldestFirst")
                    //% "Show newest first"
                    : qsTrId("albumDetailPage.showNewestFirst")
                onClicked: {
                    sortNewestFirst = !sortNewestFirst
                    page.loading = true
                    immichApi.fetchAlbumDetails(albumId)
                }
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
                            text: assetCount === 1
                                //% "1 asset"
                                ? qsTrId("albumDetailPage.asset")
                                //% "%1 assets"
                                : qsTrId("albumDetailPage.assets").arg(assetCount)
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
                        text: assetCount === 1 ? qsTrId("albumDetailPage.asset") : qsTrId("albumDetailPage.assets").arg(assetCount)
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

            // Loading indicator
            Item {
                width: parent.width
                height: page.loading ? Theme.itemSizeLarge : 0
                visible: page.loading

                BusyIndicator {
                    anchors.centerIn: parent
                    running: page.loading
                    size: BusyIndicatorSize.Large
                }
            }

            // Grouped assets
            Repeater {
                model: groupedAssets

                Column {
                    width: contentColumn.width
                    spacing: 0

                    property var monthData: modelData

                    // Month+Year header
                    Rectangle {
                        width: parent.width
                        height: Theme.itemSizeSmall
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            text: monthData.monthYear
                            font.pixelSize: Theme.fontSizeLarge
                            font.bold: true
                            color: Theme.highlightColor
                        }
                    }

                    // Date sub-groups
                    Repeater {
                        model: monthData.groups

                        Column {
                            width: contentColumn.width
                            spacing: 0

                            property var subGroupData: modelData

                            // Date header with selection button
                            Rectangle {
                                width: parent.width
                                height: Theme.itemSizeExtraSmall
                                color: "transparent"

                                property bool isSubGroupSelected: {
                                    if (!subGroupData || !subGroupData.assets || page.selectedAssets.length === 0) return false
                                    for (var i = 0; i < subGroupData.assets.length; i++) {
                                        if (!page.isAssetSelected(subGroupData.assets[i].id)) {
                                            return false
                                        }
                                    }
                                    return true
                                }

                                Label {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.horizontalPageMargin
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: subGroupData ? subGroupData.displayDate : ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.secondaryHighlightColor
                                }

                                IconButton {
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon.source: parent.isSubGroupSelected ? "image://theme/icon-m-remove" : "image://theme/icon-m-add"
                                    icon.color: parent.isSubGroupSelected ? Theme.errorColor : Theme.primaryColor

                                    onClicked: {
                                        if (!subGroupData || !subGroupData.assets) return
                                        var assets = subGroupData.assets
                                        if (parent.isSubGroupSelected) {
                                            for (var i = 0; i < assets.length; i++) {
                                                if (page.isAssetSelected(assets[i].id)) {
                                                    page.toggleAssetSelection(assets[i].id)
                                                }
                                            }
                                        } else {
                                            if (!page.selectionMode) page.selectionMode = true
                                            for (var i = 0; i < assets.length; i++) {
                                                if (!page.isAssetSelected(assets[i].id)) {
                                                    page.toggleAssetSelection(assets[i].id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Asset grid for this date
                            Flow {
                                width: parent.width

                                Repeater {
                                    model: subGroupData ? subGroupData.assets : null

                                    AssetGridItem {
                                        width: page.cellSize
                                        height: page.cellSize
                                        assetId: modelData.id
                                        isFavorite: modelData.isFavorite
                                        isSelected: page.selectedAssets.length >= 0 && page.isAssetSelected(modelData.id)
                                        isVideo: modelData.isVideo
                                        thumbhash: modelData.thumbhash || ""
                                        duration: modelData.duration || ""

                                        onClicked: {
                                            if (page.selectionMode) {
                                                page.toggleAssetSelection(modelData.id)
                                            } else {
                                                var navAssets = []
                                                for (var i = 0; i < allAssets.length; i++) {
                                                    navAssets.push({
                                                        id: allAssets[i].id,
                                                        isFavorite: allAssets[i].isFavorite,
                                                        isVideo: allAssets[i].isVideo,
                                                        thumbhash: allAssets[i].thumbhash
                                                    })
                                                }
                                                if (modelData.isVideo) {
                                                    pageStack.push(Qt.resolvedUrl("VideoPlayerPage.qml"), {
                                                        videoId: modelData.id,
                                                        isFavorite: isFavorite,
                                                        currentIndex: modelData.assetIndex,
                                                        albumAssets: navAssets,
                                                        albumId: page.albumId
                                                    })
                                                } else {
                                                    pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                                                        assetId: modelData.id,
                                                        isFavorite: isFavorite,
                                                        isVideo: modelData.isVideo,
                                                        thumbhash: modelData.thumbhash || "",
                                                        currentIndex: modelData.assetIndex,
                                                        albumAssets: navAssets,
                                                        albumId: page.albumId
                                                    })
                                                }
                                            }
                                        }

                                        onPressAndHold: {
                                            if (!page.selectionMode) page.selectionMode = true
                                            page.toggleAssetSelection(modelData.id)
                                        }

                                        onAddToSelection: {
                                            if (!page.selectionMode) page.selectionMode = true
                                            page.toggleAssetSelection(modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    // Empty state
    Item {
        anchors.fill: flickable
        visible: !page.loading && allAssets.length === 0

        Column {
            anchors.centerIn: parent
            spacing: Theme.paddingLarge

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "image://theme/icon-m-folder"
                color: Theme.highlightColor
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                //% "No assets in this album"
                text: qsTrId("albumDetailPage.noAssets")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    Component.onCompleted: {
        immichApi.fetchAlbumDetails(albumId)
    }

    Connections {
        target: immichApi
        onAlbumDetailsReceived: {
            if (details.id === albumId) {
                page.processAlbumDetails(details)
            }
        }

        onAlbumUpdated: {
            if (albumId === page.albumId) {
                page.albumName = albumName
                page.albumDescription = description
            }
        }

        onFavoritesToggled: {
            // Update local asset data
            var updated = allAssets
            for (var i = 0; i < updated.length; i++) {
                if (assetIds.indexOf(updated[i].id) > -1) {
                    updated[i].isFavorite = isFavorite
                }
            }
            allAssets = updated.slice()
            groupedAssets = AssetGroupHelper.groupByMonthAndDate(allAssets)
            page.clearSelection()
            notification.show(isFavorite
                //% "Added to favorites"
                ? qsTrId("albumDetailPage.addedToFavorites")
                //% "Removed from favorites"
                : qsTrId("albumDetailPage.removedFromFavorites"))
        }

        onAssetsDeleted: {
            immichApi.fetchAlbumDetails(albumId)
            notification.show(assetIds.length === 1
                //% "Deleted asset"
                ? qsTrId("albumDetailPage.deletedAsset")
                //% "Deleted %1 assets"
                : qsTrId("albumDetailPage.deletedAssets").arg(assetIds.length))
        }

        onAssetsRemovedFromAlbum: {
            if (albumId === page.albumId) {
                immichApi.fetchAlbumDetails(page.albumId)
            }
        }

        onAssetVisibilityChanged: {
            if (visibility === "archive") {
                //% "Moved to archive"
                notification.show(qsTrId("albumDetailPage.movedToArchive"))
            } else if (visibility === "locked") {
                //% "Moved to locked folder"
                notification.show(qsTrId("albumDetailPage.movedToLockedFolder"))
            }
            immichApi.fetchAlbumDetails(page.albumId)
        }
    }

    // Selection Action Bar
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
        onShare: {
            pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                assetIds: page.selectedAssets,
                shareType: "INDIVIDUAL"
            })
        }
        onAddToAlbum: {
            pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
                assetIds: page.selectedAssets
            })
        }
        onClearSelection: page.clearSelection()
        onDownload: {
            for (var i = 0; i < page.selectedAssets.length; i++) {
                immichApi.downloadAsset(page.selectedAssets[i])
            }
            page.clearSelection()
            notification.show(page.selectedAssets.length === 1
                //% "Downloading asset..."
                ? qsTrId("albumDetailPage.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("albumDetailPage.downloadingAssets").arg(page.selectedAssets.length))
        }
        onDeleteSelected: {
            var selectedIds = page.selectedAssets.slice()
                deleteRemorse.execute(selectedIds.length > 1
                    //% "Deleting %1 assets
                    ? qsTrId("albumDetailPage.deletingAssets").arg(selectedIds.length)
                    //% "Deleting asset
                    : qsTrId("albumDetailPage.deletingAsset"), function() {
                immichApi.deleteAssets(page.selectedAssets)
                page.clearSelection()
            })
        }
        onMoveToArchive: {
            immichApi.changeAssetVisibility(page.selectedAssets, "archive")
            page.clearSelection()
        }
        onMoveToLockedFolder: {
            immichApi.changeAssetVisibility(page.selectedAssets, "locked")
            page.clearSelection()
        }
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
}
