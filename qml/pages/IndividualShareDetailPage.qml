import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"
import "../components/AssetGroupHelper.js" as AssetGroupHelper
import "../components/SharedLinksHelper.js" as SharedLinksHelper

Page {
    id: page

    property string linkId: ""
    property string linkTitle: getTitle()
    property string linkDescription: getDescription()
    property var linkData: ({})
    property bool selectionMode: false
    property var selectedAssets: []
    property bool allSelectedAreFavorites: false
    property bool loading: false
    property string activeFilter: "taken"
    property string sortOrder: "desc"
    property bool showFavorites: false
    property var allAssets: []
    property var groupedAssets: []
    property var heroAssetIds: []
    property string dateRange: ""
    property int totalCount: 0
    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property bool showDateRange: dateRange !== "" && totalCount > 0 && activeFilter === "taken" && !showFavorites

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
        if (index > -1) selectedAssets.splice(index, 1)
        else selectedAssets.push(assetId)
        selectedAssets = selectedAssets
        if (selectedAssets.length === 0) selectionMode = false
        updateAllSelectedAreFavorites()
    }

    function clearSelection() {
        selectedAssets = []
        selectionMode = false
    }

    function isAssetSelected(assetId) {
        return selectedAssets.indexOf(assetId) > -1
    }

    function refresh() {
        loading = true
        immichApi.fetchSharedLink(linkId)
    }

    function getTitle() {
        //% "Individual share"
        return SharedLinksHelper.shareTitle(linkData, qsTrId("individualShareDetailPage.title"))
    }

    function getDescription() {
        return SharedLinksHelper.shareDescription(linkData, getTitle())
    }

    function processAssets() {
        var results = []
        var raw = linkData.assets || []
        for (var i = 0; i < raw.length; i++) results.push(raw[i])
        var r = AssetGroupHelper.processResults(results, sortOrder === "asc", showFavorites, activeFilter === "created")
        allAssets = r.allAssets
        if (r.heroAssetIds.length > 0) heroAssetIds = r.heroAssetIds
        dateRange = r.dateRange
        groupedAssets = AssetGroupHelper.buildGroupedAssets(allAssets, assetsPerRow)
        totalCount = r.totalCount
        loading = false
        scrollToTopTimer.restart()
    }

    onAssetsPerRowChanged: groupedAssets = AssetGroupHelper.buildGroupedAssets(allAssets, assetsPerRow)

    Timer {
        id: scrollToTopTimer
        interval: 50
        repeat: false
        onTriggered: flickable.positionViewAtBeginning()
    }

    SilicaListView {
        id: flickable
        anchors.fill: parent
        clip: true
        cacheBuffer: Math.max(height * 2, 2000)
        pixelAligned: true
        model: page.groupedAssets

        PullDownMenu {
            enabled: !page.selectionMode

            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }
        }

        header: Column {
            width: flickable.width

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
                        text: linkTitle
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.bold: true
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        visible: linkDescription !== ""
                        width: parent.width
                        text: linkDescription
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Row {
                        spacing: Theme.paddingMedium

                        Label {
                            text: totalCount === 1
                                //% "1 asset"
                                ? qsTrId("individualShareDetailPage.asset")
                                //% "%1 assets"
                                : qsTrId("individualShareDetailPage.assets").arg(totalCount)
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

            Column {
                width: parent.width
                visible: heroAssetIds.length === 0

                PageHeader {
                    title: linkTitle
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: linkTitle
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }

                Label {
                    visible: linkDescription !== ""
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: linkDescription
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }

                Row {
                    x: Theme.horizontalPageMargin
                    spacing: Theme.paddingMedium

                    Label {
                        text: totalCount === 1 ? qsTrId("individualShareDetailPage.asset") : qsTrId("individualShareDetailPage.assets").arg(totalCount)
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

        delegate: GroupedAssetListDelegate {
            width: flickable.width
            rowData: modelData
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
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

        footer: Item {
            width: parent.width
            height: Theme.paddingLarge
        }

        VerticalScrollDecorator {}
    }

    LoadingIndicator {
        anchors {
            left: flickable.left
            right: flickable.right
            bottom: flickable.bottom
            top: flickable.top
            topMargin: heroAssetIds.length > 0 ? page.height / 2 : 0
        }
        loading: page.loading && allAssets.length === 0
    }

    EmptyState {
        anchors {
            left: flickable.left
            right: flickable.right
            bottom: flickable.bottom
            top: flickable.top
            topMargin: heroAssetIds.length > 0 ? page.height / 2 : 0
        }
        visible: !page.loading && allAssets.length === 0
        iconSource: "image://theme/icon-m-link"
        //% "No assets in this share"
        message: qsTrId("individualShareDetailPage.noAssets")
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
        onSharedLinkReceived: {
            if (linkId !== link.id) return
            linkData = link
            page.processAssets()
        }
        onFavoritesToggled: {
            var updated = allAssets
            for (var i = 0; i < updated.length; i++) {
                if (assetIds.indexOf(updated[i].id) > -1) updated[i].isFavorite = isFavorite
            }
            allAssets = updated.slice()
            groupedAssets = AssetGroupHelper.buildGroupedAssets(allAssets, assetsPerRow)
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
