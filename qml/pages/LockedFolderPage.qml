import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"
import "../components/TimelineHelper.js" as TimelineHelper

Page {
    id: page

    property bool authenticated: false
    property bool loadingStatus: true
    property bool pinExists: false
    property bool checkingPin: false
    property string enteredPin: ""
    property bool creatingPin: false
    property string firstPin: ""

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property string activeFilter: "all"
    property string sortOrder: "desc"
    property string contextId: "locked"
    property var queryParams: ({"visibility": "locked", "order": sortOrder})
    property var heroAssetIds: []
    property bool heroInitialized: false

    TimelineModel {
        id: lockedModel
    }

    function loadLockedAssets() {
        var params = {"visibility": "locked", "order": sortOrder}
        if (activeFilter === "favorites") params["isFavorite"] = "true"
        queryParams = params
        lockedModel.clear()
        lockedModel.setLoading(true)
        heroInitialized = false
        immichApi.fetchTimelineBuckets(contextId, queryParams)
    }

    function updateHeroIds() {
        if (heroInitialized) return
        var ids = TimelineHelper.getHeroIds(lockedModel)
        if (ids.length > 0) {
            heroAssetIds = ids
            heroInitialized = true
            scrollToTopTimer.restart()
        }
    }

    function pinEntryLabel() {
        if (loadingStatus) return ""
        if (!pinExists) {
            if (creatingPin) {
                //% "Re-enter your 6-digit PIN to confirm"
                return qsTrId("lockedFolderPage.confirmPin")
            }
            //% "Create a 6-digit PIN for your locked folder"
            return qsTrId("lockedFolderPage.createNewPin")
        }
        //% "Enter your 6-digit PIN to access the locked folder"
        return qsTrId("lockedFolderPage.enterPin")
    }

    Timer {
        id: scrollToTopTimer
        interval: 50
        repeat: false
        onTriggered: bucketsList.positionViewAtBeginning()
    }

    // PIN entry view (not authenticated)
    SilicaFlickable {
        id: pinFlickable
        anchors.fill: parent
        contentHeight: pinColumn.height
        visible: !authenticated

        Column {
            id: pinColumn
            width: parent.width

            PageHeader {
                //% "Locked Folder"
                title: qsTrId("lockedFolderPage.lockedFolder")
            }

            Column {
                width: parent.width
                spacing: Theme.paddingLarge

                Item {
                    width: 1
                    height: Theme.paddingLarge * 2
                }

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: "image://theme/icon-m-device-lock"
                    color: Theme.highlightColor
                }

                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: page.loadingStatus
                    size: BusyIndicatorSize.Medium
                    visible: page.loadingStatus
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    horizontalAlignment: Text.AlignHCenter
                    text: page.pinEntryLabel()
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeMedium
                    wrapMode: Text.WordWrap
                    visible: !page.loadingStatus
                }

                // PIN dots display
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.paddingLarge
                    visible: !page.loadingStatus

                    Repeater {
                        model: 6
                        Rectangle {
                            width: Theme.iconSizeSmall
                            height: width
                            radius: width / 2
                            color: index < enteredPin.length ? Theme.highlightColor : "transparent"
                            border.width: 2
                            border.color: Theme.highlightColor
                        }
                    }
                }

                // Number pad
                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 3
                    spacing: Theme.paddingMedium

                    Repeater {
                        model: [1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 0, -2]

                        BackgroundItem {
                            width: Theme.itemSizeLarge
                            height: Theme.itemSizeLarge
                            enabled: modelData !== -1

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: parent.highlighted ? Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity) : Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                                visible: modelData !== -1
                            }

                            Label {
                                anchors.centerIn: parent
                                text: modelData >= 0 ? modelData.toString() : ""
                                font.pixelSize: Theme.fontSizeExtraLarge
                                color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                                visible: modelData >= 0
                            }

                            // Backspace icon
                            Icon {
                                anchors.centerIn: parent
                                source: "image://theme/icon-m-backspace"
                                visible: modelData === -2
                            }

                            onClicked: {
                                if (modelData >= 0) {
                                    if (enteredPin.length < 6) {
                                        enteredPin = enteredPin + modelData.toString()
                                        if (enteredPin.length === 6) {
                                            if (pinExists) {
                                                // Verify existing PIN
                                                checkingPin = true
                                                immichApi.verifyPinCode(enteredPin)
                                            } else if (!creatingPin) {
                                                // First entry of new PIN
                                                firstPin = enteredPin
                                                enteredPin = ""
                                                creatingPin = true
                                            } else {
                                                // Confirmation entry
                                                if (enteredPin === firstPin) {
                                                    checkingPin = true
                                                    immichApi.createPinCode(enteredPin)
                                                } else {
                                                    enteredPin = ""
                                                    firstPin = ""
                                                    creatingPin = false
                                                    //% "PINs to do not match, try again"
                                                    notification.show(qsTrId("notification.pinMismatch"))
                                                }
                                            }
                                        }
                                    }
                                } else if (modelData === -2) {
                                    if (enteredPin.length > 0) {
                                        enteredPin = enteredPin.substring(0, enteredPin.length - 1)
                                    }
                                }
                            }
                        }
                    }
                }

                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    running: checkingPin
                    size: BusyIndicatorSize.Medium
                    visible: checkingPin
                }
            }
        }
    }

    // Authenticated: bucket-based asset list
    SilicaListView {
        id: bucketsList
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: selectionActionBar.visible ? selectionActionBar.top : parent.bottom
        clip: true
        cacheBuffer: Math.max(height * 2, 2000)
        model: lockedModel
        visible: authenticated

        PullDownMenu {
            enabled: lockedModel.selectedCount === 0

            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.loadLockedAssets()
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
                        //% "Locked Folder"
                        text: qsTrId("lockedFolderPage.lockedFolder")
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.bold: true
                        color: Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        text: lockedModel.totalCount === 1
                            //% "1 asset"
                            ? qsTrId("lockedFolderPage.asset")
                            //% "%1 assets"
                            : qsTrId("lockedFolderPage.assets").arg(lockedModel.totalCount)
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryHighlightColor
                    }
                }
            }

            Column {
                width: parent.width
                visible: heroAssetIds.length === 0

                PageHeader {
                    title: qsTrId("lockedFolderPage.lockedFolder")
                }
            }

            TimelineFilterBar {
                activeFilter: page.activeFilter
                sortOrder: page.sortOrder
                onFilterActivated: {
                    page.activeFilter = filter
                    page.loadLockedAssets()
                }
                onSortOrderToggled: {
                    page.sortOrder = order
                    page.loadLockedAssets()
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
            bucketKey: lockedModel.getBucketTimeBucket(index)
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
            assetModel: lockedModel

            onAssetClicked: {
                pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                    assetId: assetId,
                    isFavorite: isFavorite,
                    isVideo: isVideo,
                    thumbhash: thumbhash,
                    isLockedAsset: true
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
        loading: authenticated && lockedModel.loading && lockedModel.bucketCount === 0
        //% "Loading locked folder assets..."
        message: qsTrId("lockedFolderPage.loading")
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
        visible: authenticated && !lockedModel.loading && lockedModel.totalCount === 0
        iconSource: "image://theme/icon-m-device-lock"
        //% "Locked folder is empty"
        message: qsTrId("lockedFolderPage.noAssets")
    }

    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: authenticated && lockedModel.selectedCount > 0
        selectedCount: lockedModel.selectedCount
        allAreFavorites: lockedModel.selectedCount > 0 && lockedModel.areAllSelectedFavorites()
        hasSelectedOtherOwner: lockedModel.selectedCount > 0 && lockedModel.hasSelectedOtherOwner()
        isLockedFolderPage: true

        onAddToFavorites: immichApi.toggleFavorite(lockedModel.getSelectedAssetIds(), true)
        onRemoveFromFavorites: immichApi.toggleFavorite(lockedModel.getSelectedAssetIds(), false)
        onShare: pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
            assetIds: lockedModel.getSelectedAssetIds(),
            shareType: "INDIVIDUAL"
        })
        onAddToAlbum: pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
            assetIds: lockedModel.getSelectedAssetIds()
        })
        onClearSelection: lockedModel.clearSelection()
        onDownload: {
            var ids = lockedModel.getSelectedAssetIds()
            for (var i = 0; i < ids.length; i++) {
                immichApi.downloadAsset(ids[i])
            }
            lockedModel.clearSelection()
            notification.show(ids.length === 1
                //% "Downloading asset..."
                ? qsTrId("notification.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("notification.downloadingAssets").arg(ids.length))
        }
        onDeleteSelected: {
            var ids = lockedModel.getSelectedAssetIds()
            deleteRemorse.execute(ids.length > 1
                //% "Deleting %1 assets"
                ? qsTrId("notification.deletingAssets").arg(ids.length)
                //% "Deleting asset"
                : qsTrId("notification.deletingAsset"), function() {
                    immichApi.deleteAssets(ids)
                    lockedModel.clearSelection()
            })
        }
        onRemoveFromLockedFolder: {
            immichApi.changeAssetVisibility(lockedModel.getSelectedAssetIds(), "timeline")
            lockedModel.clearSelection()
        }
    }

    RemorsePopup {
        id: deleteRemorse
    }

    NotificationBanner {
        id: notification
        anchors.bottom: lockedModel.selectedCount > 0 ? selectionActionBar.top : parent.bottom
    }

    Component.onCompleted: {
        lockedModel.setServerUrl(authManager.serverUrl)
        lockedModel.setUserId(authManager.userId)
        immichApi.fetchAuthStatus()
    }

    Connections {
        target: immichApi
        onAuthStatusReceived: {
            page.loadingStatus = false
            page.pinExists = pinCodeExists
        }
        onPinCodeVerified: {
            checkingPin = false
            if (success) {
                authenticated = true
                loadLockedAssets()
            } else {
                enteredPin = ""
                //% "Invalid PIN"
                notification.show(qsTrId("notification.invalidPin"))
            }
        }
        onPinCodeCreated: {
            //% "PIN created successfully"
            notification.show(qsTrId("notification.pinCreated"))
            pinExists = true
            immichApi.verifyPinCode(enteredPin)
        }
        onTimelineBucketsReceived: {
            if (context !== page.contextId) return
            if (authenticated) {
                lockedModel.loadBuckets(buckets)
                lockedModel.setLoading(false)
                if (lockedModel.getBucketCount() > 0) {
                    lockedModel.requestBucketLoad(0)
                }
            }
        }
        onTimelineBucketReceived: {
            if (context !== page.contextId) return
            if (authenticated) {
                lockedModel.loadBucketAssets(timeBucket, bucketData)
                page.updateHeroIds()
            }
        }
        onAssetsDeleted: {
            if (authenticated) {
                page.loadLockedAssets()
                notification.show(assetIds.length === 1
                    //% "Deleted asset"
                    ? qsTrId("notification.deletedAsset")
                    //% "Deleted %1 assets"
                    : qsTrId("notification.deletedAssets").arg(assetIds.length))

            }
        }
        onAssetVisibilityChanged: {
            if (authenticated) {
                if (visibility === "timeline") {
                    //% "Removed from locked folder"
                    notification.show(qsTrId("notification.removedFromLockedFolder"))
                } else if (visibility === "archive") {
                    //% "Moved to archive"
                    notification.show(qsTrId("notification.movedToLockedFolder"))
                }
                page.loadLockedAssets()
            }
            lockedModel.clearSelection()
        }
    }

    Connections {
        target: lockedModel
        onBucketLoadRequested: {
            immichApi.fetchTimelineBucket(page.contextId, timeBucket, page.queryParams)
        }
    }
}
