import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"
import "../components/TimelineHelper.js" as TimelineHelper

Page {
    id: page

    property string partnerId
    property string partnerName
    property bool inTimeline: false

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property string activeFilter: "taken"
    property string sortOrder: "desc"
    property string contextId: "partner-" + partnerId
    property var queryParams: ({"userId": partnerId, "order": sortOrder})
    property var heroAssetIds: []
    property bool heroInitialized: false

    TimelineModel {
        id: partnerModel
    }

    function refresh() {
        partnerModel.clear()
        partnerModel.setLoading(true)
        heroInitialized = false
        var showCreatedAt = page.activeFilter === "created"
        var params = {"userId": partnerId, "order": sortOrder}
        if (showCreatedAt) params["orderBy"] = "createdAt"
        queryParams = params
        immichApi.fetchTimelineBuckets(contextId, queryParams)
    }

    function updateHeroIds() {
        if (heroInitialized) return
        var ids = TimelineHelper.getHeroIds(partnerModel)
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
        model: partnerModel

        PullDownMenu {
            enabled: partnerModel.selectedCount === 0

            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }

            MenuItem {
                text: inTimeline
                    //% "Hide from timeline"
                    ? qsTrId("pullDownMenu.hideFromTimeline")
                    //% "Show in timeline"
                    : qsTrId("pullDownMenu.showOnTimeline")
                onClicked: {
                    inTimeline = !inTimeline
                    immichApi.updatePartner(partnerId, inTimeline)
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
                        //% "%1's assets"
                        text: qsTrId("partnerAssetsPage.title").arg(partnerName)
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.bold: true
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        text: partnerModel.totalCount === 1
                            //% "1 asset"
                            ? qsTrId("partnerAssetsPage.asset")
                            //% "%1 assets"
                            : qsTrId("partnerAssetsPage.assets").arg(partnerModel.totalCount)
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryHighlightColor
                    }
                }
            }

            Column {
                width: parent.width
                visible: heroAssetIds.length === 0

                PageHeader {
                    title: qsTrId("partnerAssetsPage.title").arg(partnerName)
                }
            }

            FilterBar {
                favoritesButtonVisible: false
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
            bucketKey: partnerModel.getBucketTimeBucket(index)
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
            assetModel: partnerModel

            onAssetClicked: {
                pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                    assetId: assetId,
                    isFavorite: isFavorite,
                    isVideo: isVideo,
                    thumbhash: thumbhash,
                    assetModel: partnerModel,
                    currentIndex: currentIndex,
                    partnerShowInTimeline: inTimeline
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
        loading: partnerModel.loading && partnerModel.bucketCount === 0
        //% "Loading assets..."
        message: qsTrId("partnerAssetsPage.loading")
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
        visible: !partnerModel.loading && partnerModel.totalCount === 0
        //% "No assets"
        message: qsTrId("partnerAssetsPage.noAssets")
    }

    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: partnerModel.selectedCount > 0
        selectedCount: partnerModel.selectedCount
        allAreFavorites: partnerModel.selectedCount > 0 && partnerModel.areAllSelectedFavorites()
        hasSelectedOtherOwner: partnerModel.selectedCount > 0 && partnerModel.hasSelectedOtherOwner()

        onShare: pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
            assetIds: partnerModel.getSelectedAssetIds(),
            shareType: "INDIVIDUAL"
        })
        onAddToAlbum: pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
            assetIds: partnerModel.getSelectedAssetIds()
        })
        onClearSelection: partnerModel.clearSelection()
        onDownload: {
            var ids = partnerModel.getSelectedAssetIds()
            for (var i = 0; i < ids.length; i++) {
                immichApi.downloadAsset(ids[i])
            }
            partnerModel.clearSelection()
            notification.show(ids.length === 1
                //% "Downloading asset..."
                ? qsTrId("notification.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("notification.downloadingAssets").arg(ids.length))
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
        anchors.bottom: partnerModel.selectedCount > 0 ? selectionActionBar.top : parent.bottom
    }

    Component.onCompleted: {
        partnerModel.setServerUrl(authManager.serverUrl)
        partnerModel.setUserId(authManager.userId)
        page.refresh()
    }

    Connections {
        target: immichApi
        onTimelineBucketsReceived: {
            if (context !== page.contextId) return
            partnerModel.loadBuckets(buckets)
            partnerModel.setLoading(false)
            if (partnerModel.getBucketCount() > 0) {
                partnerModel.requestBucketLoad(0)
            }
        }
        onTimelineBucketReceived: {
            if (context !== page.contextId) return
            partnerModel.loadBucketAssets(timeBucket, bucketData)
            page.updateHeroIds()
        }
    }

    Connections {
        target: partnerModel
        onBucketLoadRequested: immichApi.fetchTimelineBucket(page.contextId, timeBucket, page.queryParams)
    }
}
