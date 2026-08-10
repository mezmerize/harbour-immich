import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"
import "../components/TimelineHelper.js" as TimelineHelper

Page {
    id: page

    property string personId
    property string personName
    property string personBirthDate
    property string thumbnailPath
    property bool personIsFavorite: false
    property bool personIsHidden: false

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property string activeFilter: "taken"
    property string sortOrder: "desc"
    property bool showFavorites: false
    property string contextId: "person-" + personId
    property var queryParams: ({"personId": personId, "withStacked": "true", "order": sortOrder})

    property var heroAssetIds: []
    property bool heroInitialized: false

    TimelineModel {
        id: personModel
    }

    function refresh() {
        personModel.clear()
        personModel.setLoading(true)
        heroInitialized = false
        var params = {"personId": personId, "withStacked": "true", "order": sortOrder}
        var showCreatedAt = page.activeFilter === "created"
        personModel.setGroupByCreatedAt(showCreatedAt)
        if (showFavorites) params["isFavorite"] = "true"
        if (showCreatedAt) params["orderBy"] = "createdAt"
        queryParams = params
        immichApi.fetchTimelineBuckets(contextId, queryParams)
    }

    function updateHeroIds() {
        if (heroInitialized) return
        var ids = TimelineHelper.getHeroIds(personModel)
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
        model: personModel

        PullDownMenu {
            enabled: personModel.selectedCount === 0

            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }

            MenuItem {
                //% "Edit person"
                text: qsTrId("pullDownMenu.editPerson")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("../components/EditPersonDialog.qml"), {
                        personName: personName,
                        personBirthDate: personBirthDate,
                        personIsFavorite: personIsFavorite,
                        personIsHidden: personIsHidden
                    })
                    dialog.accepted.connect(function() {
                        personName = dialog.newName
                        personBirthDate = dialog.newBirthday
                        personIsFavorite = dialog.newFavorite
                        personIsHidden = dialog.newHidden
                        immichApi.updatePerson(personId, { "name": personName, "isFavorite": personIsFavorite, "isHidden": personIsHidden })
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

                Row {
                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: Theme.paddingLarge
                        rightMargin: Theme.horizontalPageMargin
                    }
                    spacing: Theme.paddingMedium

                    Icon {
                        width: Theme.iconSizeMedium
                        height: Theme.iconSizeMedium
                        source: "image://theme/icon-m-incognito"
                        visible: page.personIsHidden
                    }

                    Icon {
                        width: Theme.iconSizeMedium
                        height: Theme.iconSizeMedium
                        source: "image://theme/icon-m-favorite-selected"
                        visible: page.personIsFavorite
                    }
                }

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
                        //% "Unknown"
                        text: personName || qsTrId("personDetailPage.unknown")
                        font.pixelSize: Theme.fontSizeExtraLarge; font.bold: true
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        width: parent.width
                        visible: personBirthDate !== ""
                        text: personBirthDate !== "" ? Qt.formatDate(new Date(personBirthDate), "dd.MM.yyyy") : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                    }

                    Row {
                        spacing: Theme.paddingMedium

                        Label {
                            text: personModel.totalCount === 1
                                //% "1 asset"
                                ? qsTrId("personDetailPage.asset")
                                //% "%1 assets"
                                : qsTrId("personDetailPage.assets").arg(personModel.totalCount)
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryHighlightColor
                        }
                    }
                }
            }

            // No hero images (most likely due to no assets at all)
            Column {
                width: parent.width
                visible: heroAssetIds.length === 0

                PageHeader {
                    title: personName || qsTrId("personDetailPage.unknown")
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: personBirthDate !== ""
                    text: personBirthDate !== "" ? Qt.formatDate(new Date(personBirthDate), "dd.MM.yyyy") : ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: personModel.totalCount > 0
                    text: personModel.totalCount === 1 ? qsTrId("personDetailPage.asset") : qsTrId("personDetailPage.assets").arg(personModel.totalCount)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
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
            bucketKey: personModel.getBucketTimeBucket(index)
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
            assetModel: personModel

            onAssetClicked: {
                pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                    assetId: assetId,
                    isFavorite: isFavorite,
                    isVideo: isVideo,
                    thumbhash: thumbhash,
                    assetModel: personModel,
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
        loading: personModel.loading && personModel.bucketCount === 0
        //% "Loading assets..."
        message: qsTrId("personDetailPage.loading")
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
        visible: !personModel.loading && personModel.totalCount === 0
        iconSource: "image://theme/icon-m-people"
        //% "No assets"
        message: qsTrId("personDetailPage.noAssets")
    }

    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: personModel.selectedCount > 0
        selectedCount: personModel.selectedCount
        allAreFavorites: personModel.selectedCount > 0 && personModel.areAllSelectedFavorites()
        hasSelectedOtherOwner: personModel.selectedCount > 0 && personModel.hasSelectedOtherOwner()
        showArchive: true

        onAddToFavorites: immichApi.toggleFavorite(personModel.getSelectedAssetIds(), true)
        onRemoveFromFavorites: immichApi.toggleFavorite(personModel.getSelectedAssetIds(), false)
        onShare: pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
            assetIds: personModel.getSelectedAssetIds(),
            shareType: "INDIVIDUAL"
        })
        onAddToAlbum: pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
            assetIds: personModel.getSelectedAssetIds()
        })
        onClearSelection: personModel.clearSelection()
        onDownload: {
            var ids = personModel.getSelectedAssetIds()
            for (var i = 0; i < ids.length; i++)
                immichApi.downloadAsset(ids[i])
            personModel.clearSelection()
            notification.show(ids.length === 1
                //% "Downloading asset..."
                ? qsTrId("notification.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("notification.downloadingAssets").arg(ids.length))
        }
        onDeleteSelected: {
            var selectedIds = personModel.getSelectedAssetIds()
            deleteRemorse.execute(selectedIds.length > 1
                //% "Deleting %1 assets"
                ? qsTrId("notification.deletingAssets").arg(selectedIds.length)
                //% "Deleting asset"
                : qsTrId("notification.deletingAsset"), function() {
                    immichApi.deleteAssets(selectedIds)
                    personModel.clearSelection()
            })
        }
        onMoveToArchive: immichApi.changeAssetVisibility(personModel.getSelectedAssetIds(), "archive")
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
        anchors.bottom: personModel.selectedCount > 0 ? selectionActionBar.top : parent.bottom
    }

    Component.onCompleted: {
        personModel.setServerUrl(authManager.serverUrl)
        personModel.setUserId(authManager.userId)
        page.refresh()
    }

    Connections {
        target: immichApi
        onTimelineBucketsReceived: {
            if (context !== page.contextId) return
            personModel.loadBuckets(buckets)
            personModel.setLoading(false)
            // Request first bucket to populate hero images
            if (personModel.getBucketCount() > 0) {
                personModel.requestBucketLoad(0)
            }
        }
        onTimelineBucketReceived: {
            if (context !== page.contextId) return
            personModel.loadBucketAssets(timeBucket, bucketData)
            page.updateHeroIds()
        }
        onFavoritesToggled: {
            personModel.updateFavorites(assetIds, isFavorite)
            personModel.clearSelection()
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
        onPersonUpdated: {
            if (personId === page.personId)
                //% "Person updated"
                notification.show(qsTrId("notification.personUpdated"))
        }
        onAssetVisibilityChanged: {
            if (visibility === "archive") {
                //% "Moved to archive"
                notification.show(qsTrId("notification.movedToArchive"))
            } else if (visibility === "locked") {
                //% "Moved to locked folder"
                notification.show(qsTrId("notification.movedToLockedFolder"))
            }
            personModel.clearSelection()
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
        target: personModel
        onBucketLoadRequested: {
            immichApi.fetchTimelineBucket(page.contextId, timeBucket, page.queryParams)
        }
    }
}
