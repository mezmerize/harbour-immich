import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"
import "../components/TimelineHelper.js" as TimelineHelper
import "../components/SharedLinksHelper.js" as SharedLinksHelper

Page {
    id: page

    property string linkId: ""
    property string linkTitle: getTitle()
    property string linkDescription: getDescription()
    property var linkData: ({})
    property bool loading: false
    property string albumId: (linkData && linkData.album) ? linkData.album.id : ""
    property string contextId: "shared-" + (linkId || "")
    property var heroAssetIds: []
    property string dateRange: ""
    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property string activeFilter: "taken"
    property string sortOrder: "desc"
    property bool showFavorites: false
    property var queryParams: ({"albumId": albumId, "order": sortOrder})
    property bool heroInitialized: false
    property bool showDateRange: dateRange !== "" && sharedLinkModel.totalCount > 0 && activeFilter === "taken" && !showFavorites

    function getTitle() {
        //% "Individual share"
        return SharedLinksHelper.shareTitle(linkData, qsTrId("albumShareDetailPage.title"))
    }

    function getDescription() {
        return SharedLinksHelper.shareDescription(linkData, getTitle())
    }

    function refresh() {
        loading = true
        immichApi.fetchSharedLink(linkId)
    }

    function reloadFromLinkData() {
        sharedLinkModel.clear()
        sharedLinkModel.setLoading(true)
        heroInitialized = false
        var showCreatedAt = page.activeFilter === "created"
        sharedLinkModel.setGroupByCreatedAt(showCreatedAt)
        var params = {"albumId": albumId, "order": sortOrder}
        if (showFavorites) params["isFavorite"] = "true"
        if (showCreatedAt) params["orderBy"] = "createdAt"
        queryParams = params
        immichApi.fetchTimelineBuckets(contextId, queryParams)
    }

    function updateHeroIds() {
        if (heroInitialized) return
        var ids = TimelineHelper.getHeroIds(sharedLinkModel)
        if (ids.length > 0) {
            heroAssetIds = ids
            heroInitialized = true
            scrollToTopTimer.restart()
        }
    }

    function updateDateRange() {
        if (linkData && linkData.album) dateRange = TimelineHelper.computeDateRange(linkData.album.startDate, linkData.album.endDate)
    }

    TimelineModel {
        id: sharedLinkModel
    }

    Timer {
        id: scrollToTopTimer
        interval: 50
        repeat: false
        onTriggered: bucketsList.positionViewAtBeginning()
    }

    SilicaListView {
        id: bucketsList
        anchors.fill: parent
        clip: true
        cacheBuffer: Math.max(height * 2, 2000)
        model: sharedLinkModel

        PullDownMenu {
            enabled: sharedLinkModel.selectedCount === 0

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
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.bottomMargin: Theme.paddingLarge
                    spacing: Theme.paddingSmall / 2

                    Label {
                        width: parent.width
                        text: page.getTitle()
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.bold: true
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        visible: page.getDescription() !== ""
                        width: parent.width
                        text: page.getDescription()
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Row {
                        spacing: Theme.paddingMedium

                        Label {
                            text: sharedLinkModel.totalCount === 1
                                //% "1 asset"
                                ? qsTrId("albumShareDetailPage.asset")
                                //% "%1 assets"
                                : qsTrId("albumShareDetailPage.assets").arg(sharedLinkModel.totalCount)
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
                    title: page.getTitle()
                }

                Label {
                    visible: page.getDescription() !== ""
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: page.getDescription()
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }

                Row {
                    x: Theme.horizontalPageMargin
                    spacing: Theme.paddingMedium

                    Label {
                        text: sharedLinkModel.totalCount === 1 ? qsTrId("albumShareDetailPage.asset") : qsTrId("albumShareDetailPage.assets").arg(sharedLinkModel.totalCount)
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

        delegate: TimelineBucketDelegate {
            width: bucketsList.width
            bucketIndex: index
            bucketKey: sharedLinkModel.getBucketTimeBucket(index)
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
            assetModel: sharedLinkModel


            onAssetClicked: {
                pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                    assetId: assetId,
                    isFavorite: isFavorite,
                    isVideo: isVideo,
                    thumbhash: thumbhash,
                    assetModel: sharedLinkModel,
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

    LoadingIndicator {
        anchors {
            left: bucketsList.left
            right: bucketsList.right
            bottom: bucketsList.bottom
            top: bucketsList.top
            topMargin: heroAssetIds.length > 0 ? page.height / 2 : 0
        }
        loading: page.loading || (sharedLinkModel.loading && sharedLinkModel.bucketCount === 0)
    }

    EmptyState {
        anchors {
            left: bucketsList.left
            right: bucketsList.right
            bottom: bucketsList.bottom
            top: bucketsList.top
            topMargin: heroAssetIds.length > 0 ? page.height / 2 : 0
        }
        visible: !page.loading && !sharedLinkModel.loading && sharedLinkModel.totalCount === 0
        iconSource: "image://theme/icon-m-link"
        //% "No assets in this share"
        message: qsTrId("albumShareDetailPage.noAssets")
    }

    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        selectedCount: sharedLinkModel.selectedCount
        allAreFavorites: sharedLinkModel.selectedCount > 0 && sharedLinkModel.areAllSelectedFavorites()
        hasAnyFavorites: sharedLinkModel.selectedCount > 0 && sharedLinkModel.areAnySelectedFavorites()
        canStack: sharedLinkModel.selectedCount > 1 && !sharedLinkModel.isAnySelectedAStack() && !sharedLinkModel.hasSelectedOtherOwner()
        hasSelectedOtherOwner: sharedLinkModel.selectedCount > 0 && sharedLinkModel.hasSelectedOtherOwner()
        showArchive: true

        onStackSelected: {
            var selectedIds = sharedLinkModel.getSelectedAssetIds()
            immichApi.createStack(selectedIds)
        }
        onAddToFavorites: {
            var selectedIds = sharedLinkModel.getSelectedAssetIds()
            immichApi.toggleFavorite(selectedIds, true)
        }
        onRemoveFromFavorites: {
            var selectedIds = sharedLinkModel.getSelectedAssetIds()
            immichApi.toggleFavorite(selectedIds, false)
        }
        onShare: {
            var selectedIds = sharedLinkModel.getSelectedAssetIds()
            pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                assetIds: selectedIds,
                shareType: "INDIVIDUAL"
            })
        }
        onAddToAlbum: {
            var dialog = pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
                assetIds: sharedLinkModel.getSelectedAssetIds()
            })
            dialog.accepted.connect(function() {
                sharedLinkModel.clearSelection()
            })
        }
        onClearSelection: sharedLinkModel.clearSelection()
        onDownload: {
            var selectedIds = sharedLinkModel.getSelectedAssetIds()
            for (var i = 0; i < selectedIds.length; i++) {
                immichApi.downloadAsset(selectedIds[i])
            }
            sharedLinkModel.clearSelection()
            notification.show(selectedIds.length === 1
                //% "Downloading asset..."
                ? qsTrId("notification.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("notification.downloadingAssets").arg(selectedIds.length))
        }
        onDeleteSelected: {
            var selectedIds = sharedLinkModel.getSelectedAssetIds()
            deleteRemorse.execute(selectedIds.length === 1
                //% "Deleting asset"
                ? qsTrId("notification.deletingAsset")
                //% "Deleting %1 assets"
                : qsTrId("notification.deletingAssets").arg(selectedIds.length), function() {
                    immichApi.deleteAssets(selectedIds)
                    sharedLinkModel.clearSelection()
            })
        }
        onMoveToArchive: {
            var selectedIds = sharedLinkModel.getSelectedAssetIds()
            immichApi.changeAssetVisibility(selectedIds, "archive")
            sharedLinkModel.clearSelection()
        }
        onMoveToLockedFolder: {
            var selectedIds = sharedLinkModel.getSelectedAssetIds()
            immichApi.changeAssetVisibility(selectedIds, "locked")
            sharedLinkModel.clearSelection()
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
        anchors.bottom: parent.bottom
    }

    Component.onCompleted: {
        sharedLinkModel.setServerUrl(authManager.serverUrl)
        sharedLinkModel.setUserId(authManager.userId)
        page.refresh()
    }

    Connections {
        target: immichApi
        onSharedLinkReceived: {
            if (linkId !== link.id) return
            linkData = link
            loading = false
            page.reloadFromLinkData()
        }
        onTimelineBucketsReceived: {
            if (context !== page.contextId) return
            sharedLinkModel.loadBuckets(buckets)
            sharedLinkModel.setLoading(false)
            page.updateDateRange()
            if (sharedLinkModel.getBucketCount() > 0) sharedLinkModel.requestBucketLoad(0)
        }
        onTimelineBucketReceived: {
            if (context !== page.contextId) return
            sharedLinkModel.loadBucketAssets(timeBucket, bucketData)
            page.updateHeroIds()
        }
        onFavoritesToggled: sharedLinkModel.updateFavorites(assetIds, isFavorite)
    }

    Connections {
        target: sharedLinkModel
        onBucketLoadRequested: {
            immichApi.fetchTimelineBucket(page.contextId, timeBucket, page.queryParams)
        }
    }
}
