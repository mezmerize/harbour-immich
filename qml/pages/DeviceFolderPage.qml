import QtQuick 2.6
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"

Page {
    backgroundColor: __silica_applicationwindow_instance.lightSurface(Theme.rgba(palette.overlayBackgroundColor, 0))
    id: page

    property string folderPath: ""
    property string displayName: ""
    property bool pickMode: false
    property var initialSelectedPaths: []
    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property bool selectionMode: folderModel.selectedCount > 0
    property var heroPaths: []

    signal selectionEdited(var selected, var deselected)

    DeviceFolderModel {
        id: folderModel
        columns: page.assetsPerRow
        onCountChanged: page.updateHeroImages()
    }

    function updateHeroImages() {
        heroPaths = folderModel.heroPaths(8)
    }

    function openAsset(index) {
        pageStack.push(Qt.resolvedUrl("DeviceAssetDetailPage.qml"), {
            model: folderModel,
            initialIndex: index
        })
    }

    function uploadPaths(paths) {
        if (paths.length === 0) return
        immichApi.uploadAssets(paths)
        notification.show(paths.length === 1
            //% "Uploading file"
            ? qsTrId("notification.uploadingFile")
            //% "Uploading %1 files"
            : qsTrId("notification.uploadingFiles").arg(paths.length))
    }

    Component.onCompleted: {
        folderModel.init(backupManager, immichApi)
        folderModel.setFolder(folderPath)
        if (pickMode && initialSelectedPaths.length > 0) folderModel.selectPaths(initialSelectedPaths)
        updateHeroImages()
    }

    SilicaListView {
        id: gridView
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: selectionActionBar.visible ? selectionActionBar.top : parent.bottom
        clip: true
        cacheBuffer: page.height
        model: folderModel

        PullDownMenu {
            backgroundColor: __silica_applicationwindow_instance.lightSurface(Theme.highlightBackgroundColor)
            enabled: !page.selectionMode

            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: folderModel.refresh()
            }

            MenuItem {
                text: folderModel.sortOrder === "desc"
                    //% "Show oldest first"
                    ? qsTrId("pullDownMenu.showOldestFirst")
                    //% "Show newest first"
                    : qsTrId("pullDownMenu.showNewestFirst")
                onClicked: folderModel.sortOrder = (folderModel.sortOrder === "desc" ? "asc" : "desc")
            }
        }

        header: Item {
            width: gridView.width
            height: heroColumn.height

            Column {
                id: heroColumn
                width: parent.width

                // Hero image rotator
                Item {
                    id: hero
                    width: parent.width
                    height: page.heroPaths.length > 0 ? page.height / 2 : 0
                    visible: page.heroPaths.length > 0 && !page.pickMode
                    clip: true

                    HeroImageRotator {
                        anchors.fill: parent
                        assetIds: page.heroPaths
                        sourcePrefix: "image://localthumbnail/crop/"
                        active: page.status === PageStatus.Active
                    }

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
                            text: page.displayName !== "" ? page.displayName : folderModel.folderName
                            font.pixelSize: Theme.fontSizeExtraLarge
                            font.bold: true
                            color: Theme.primaryColor
                            truncationMode: TruncationMode.Fade
                        }

                        Label {
                            text: folderModel.count === 1
                                //% "1 asset"
                                ? qsTrId("deviceFolderPage.asset")
                                //% "%1 assets"
                                : qsTrId("deviceFolderPage.assets").arg(folderModel.count)
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryHighlightColor
                        }
                    }
                }

                // No hero images
                PageHeader {
                    visible: page.heroPaths.length === 0 || page.pickMode
                    title: page.displayName !== "" ? page.displayName : folderModel.folderName
                    description: folderModel.count === 1 ? qsTrId("deviceFolderPage.asset") : qsTrId("deviceFolderPage.assets").arg(folderModel.count)
                }
            }
        }

        delegate: Item {
            id: rowItem
            width: gridView.width

            property int rowType: model.rowType !== undefined ? model.rowType : DeviceFolderModel.RowAssets
            property string rowTitle: model.title || ""
            property var dayIndices: model.indices || []
            property bool allSelected: model.allSelected === true
            property var rowItems: model.items || []

            height: rowType === DeviceFolderModel.RowAssets ? page.cellSize : (rowType === DeviceFolderModel.RowMonthHeader ? Theme.itemSizeSmall : Theme.itemSizeExtraSmall)

            // Group header
            Rectangle {
                anchors.fill: parent
                visible: rowItem.rowType === DeviceFolderModel.RowMonthHeader
                color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: rowItem.rowTitle
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                    color: Theme.highlightColor
                }
            }

            // Subgroup header
            Item {
                id: dayHeader
                anchors.fill: parent
                visible: rowItem.rowType === DeviceFolderModel.RowDayHeader

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: rowItem.rowTitle
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
                }

                IconButton {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: rowItem.allSelected ? "image://theme/icon-m-remove" : "image://theme/icon-m-add"
                    icon.color: rowItem.allSelected ? Theme.errorColor : Theme.primaryColor
                    onClicked: folderModel.setIndicesSelected(rowItem.dayIndices, !rowItem.allSelected)
                }
            }

            // Asset row
            Row {
                visible: rowItem.rowType === DeviceFolderModel.RowAssets

                Repeater {
                    model: rowItem.rowType === DeviceFolderModel.RowAssets ? rowItem.rowItems : null

                    BackgroundItem {
                        id: cell
                        width: page.cellSize
                        height: page.cellSize

                        property var itemData: modelData
                        property int assetIndex: itemData ? itemData.index : -1
                        property bool isSelectedCell: itemData && itemData.selected === true
                        property int backupStatus: itemData ? itemData.status : DeviceFolderModel.StatusUnknown
                        property bool useRemote: false

                        onItemDataChanged: useRemote = false

                        onClicked: {
                            if (page.pickMode || page.selectionMode) {
                                folderModel.toggleSelection(assetIndex)
                            } else {
                                page.openAsset(assetIndex)
                            }
                        }
                        onPressAndHold: {
                            if (!page.selectionMode) {
                                folderModel.toggleSelection(assetIndex)
                            }
                        }

                        Image {
                            id: thumbnailImage
                            anchors.fill: parent
                            anchors.margins: 2
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: false
                            sourceSize.width: Math.ceil(page.cellSize)
                            sourceSize.height: Math.ceil(page.cellSize)
                            source: cell.itemData ? (cell.useRemote && cell.itemData.remoteAssetId ? "image://immich/thumbnail/" + cell.itemData.remoteAssetId : "image://localthumbnail/crop/" + cell.itemData.filePath) : ""

                            onStatusChanged: {
                                if (status === Image.Error && !cell.useRemote &&
                                        cell.itemData && cell.itemData.remoteAssetId) {
                                    cell.useRemote = true
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                                visible: thumbnailImage.status !== Image.Ready
                            }

                            Icon {
                                anchors.centerIn: parent
                                source: cell.itemData && cell.itemData.isVideo ? "image://theme/icon-m-video" : "image://theme/icon-m-image"
                                opacity: 0.6
                                visible: thumbnailImage.status === Image.Error
                            }
                        }

                        // Selection overlay
                        Rectangle {
                            anchors.fill: parent
                            color: cell.isSelectedCell ? Theme.rgba(Theme.highlightBackgroundColor, 0.2) : "transparent"
                            border.width: cell.isSelectedCell ? 2 : 0
                            border.color: Theme.highlightColor
                            z: 10
                        }

                        // Video play indicator
                        Icon {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: Theme.paddingSmall
                            width: Theme.iconSizeSmall
                            height: Theme.iconSizeSmall
                            source: "image://theme/icon-m-play"
                            visible: cell.itemData && cell.itemData.isVideo
                        }

                        // Backup status indicator
                        Icon {
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: Theme.paddingSmall
                            width: Theme.iconSizeSmall
                            height: Theme.iconSizeSmall
                            source: cell.backupStatus === DeviceFolderModel.StatusBackedUp ? "image://theme/icon-s-cloud-download" : "image://theme/icon-s-high-importance"
                            visible: cell.backupStatus !== DeviceFolderModel.StatusUnknown
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    LoadingIndicator {
        anchors.fill: gridView
        loading: folderModel.loading || folderModel.checking
        //% "Checking against server..."
        message: qsTrId("deviceFolderPage.checking")
    }

    EmptyState {
        anchors.fill: gridView
        visible: !folderModel.loading && folderModel.count === 0
        iconSource: "image://theme/icon-m-phone"
        //% "No media files in this folder"
        message: qsTrId("deviceFolderPage.empty")
    }

    // Selection action bar
    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        selectedCount: folderModel.selectedCount
        selectionLocalOnly: true

        onUpload: {
            var paths = folderModel.selectedPaths()
            folderModel.clearSelection()
            page.uploadPaths(paths)
        }
        onDeleteSelected: {
            var paths = folderModel.selectedPaths()
            deleteRemorse.execute(paths.length === 1
                //% "Deleting file from device"
                ? qsTrId("notification.deletingFile")
                //% "Deleting %1 files from device"
                : qsTrId("notification.deletingFiles").arg(paths.length), function() {
                folderModel.removeLocalFiles(paths)
            })
        }
    }

    SelectedCountButton {
        selectedCount: folderModel.selectedCount
        actionBarHeight: selectionActionBar.visible ? selectionActionBar.height : 0
        onClearSelection: folderModel.clearSelection()
    }

    RemorsePopup {
        id: deleteRemorse
    }

    NotificationBanner {
        id: notification
        anchors.bottom: page.selectionMode ? selectionActionBar.top : parent.bottom
        z: 10
    }

    Connections {
        target: folderModel
        onSelectionEdited: {
            if (page.pickMode) page.selectionEdited(selected, deselected)
        }
        onServerCheckFailed: {
            //% "Server check failed"
            notification.showError(qsTrId("notification.checkFailed"))
        }
        onFilesRemoved: {
            removedCount === 1
                //% "Removed file from device"
                ? notification.show(qsTrId("notification.removedFile"))
                //% "Removed %1 files from device"
                : notification.show(qsTrId("notification.removedFiles").arg(removedCount))
        }
    }
}
