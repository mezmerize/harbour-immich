import QtQuick 2.6
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0
import harbour.immich.models 1.0
import "../components"

Dialog {
    id: albumPickerDialog

    property var assetIds: []
    property string selectedAlbumId: ""
    property string newAlbumName: ""
    property bool createNew: false
    property string filterText: ""
    property string activeFilter: "all"
    property int filteredCount: 0
    property var loadedAlbums: []

    function applyFilter() {
        immichApi.fetchAlbums(activeFilter)
    }

    function updateFilteredCount() {
        if (filterText.length === 0) {
            filteredCount = filteredAlbums.count
            return
        }
        var count = 0
        for (var i = 0; i < loadedAlbums.length; i++) {
            var album = loadedAlbums[i]
            if (album.albumName && album.albumName.toLowerCase().indexOf(filterText) !== -1) {
                count++
            }
        }
        filteredCount = count
    }

    onFilterTextChanged: updateFilteredCount()

    canAccept: selectedAlbumId !== "" || (createNew && newAlbumName.length > 0)

    onAccepted: {
        if (createNew && newAlbumName.length > 0) {
            immichApi.createAlbum(newAlbumName, "")
        } else if (selectedAlbumId !== "") {
            immichApi.addAssetsToAlbum(selectedAlbumId, assetIds)
        }
    }

    Connections {
        target: immichApi
        onAlbumCreated: immichApi.addAssetsToAlbum(albumId, assetIds)
        onAlbumsReceived: {
            if (albumPickerDialog.status !== PageStatus.Active) return
            albumPickerDialog.loadedAlbums = albums
            albumPickerDialog.updateFilteredCount()
            scrollToTopTimer.restart()
        }
    }

    AlbumFilterModel {
        id: filteredAlbums
        sourceAlbumModel: albumModel
        filterText: albumPickerDialog.filterText
    }

    SilicaGridView {
        id: albumGrid
        anchors.fill: parent
        clip: true
        model: filteredAlbums
        currentIndex: -1
        cellWidth: width / (albumPickerDialog.isPortrait ? 2 : 4)
        cellHeight: cellWidth + Theme.fontSizeSmall + Theme.fontSizeExtraSmall + 2 * Theme.paddingMedium + Theme.paddingSmall
        cacheBuffer: Math.round(cellHeight * 3)

        header: Column {
            width: albumGrid.width

            DialogHeader {
                //% "Select or create album"
                title: qsTrId("albumPickerPage.selectOrCreate")
                //% "Add"
                acceptText: qsTrId("albumPickerPage.add")
            }

            SectionHeader {
                //% "Create new album"
                text: qsTrId("albumPickerPage.createNew")
            }

            TextField {
                id: newAlbumField
                width: parent.width
                //% "Album name"
                placeholderText: qsTrId("albumPickerPage.albumName")
                //% "New album name"
                label: qsTrId("albumPickerPage.newAlbumName")
                text: albumPickerDialog.newAlbumName
                onTextChanged: {
                    if (albumPickerDialog.newAlbumName !== text) albumPickerDialog.newAlbumName = text
                    if (text.length > 0) {
                        albumPickerDialog.createNew = true
                        albumPickerDialog.selectedAlbumId = ""
                    } else {
                        albumPickerDialog.createNew = false
                    }
                }
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: {
                    if (text.length > 0) {
                        albumPickerDialog.accept()
                    }
                }
            }

            SectionHeader {
                //% "Existing albums"
                text: qsTrId("albumPickerPage.existingAlbums")
                visible: albumGrid.count > 0
            }

            // Album type filter row
            AlbumFilterBar {
                width: albumGrid.width
                activeFilter: albumPickerDialog.activeFilter
                onFilterActivated: {
                    if (albumPickerDialog.activeFilter !== filter) {
                        albumPickerDialog.activeFilter = filter
                        albumPickerDialog.applyFilter()
                    }
                }
            }

            SearchField {
                id: albumFilterField
                width: albumGrid.width
                //% "Filter albums..."
                placeholderText: qsTrId("albumPickerPage.filter")
                onTextChanged: albumPickerDialog.filterText = text.toLowerCase()
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        delegate: BackgroundItem {
            id: albumDelegate
            width: albumGrid.cellWidth
            height: albumGrid.cellHeight

            Item {
                anchors.fill: parent
                anchors.leftMargin: Theme.paddingMedium / 2
                anchors.rightMargin: Theme.paddingMedium / 2

                Item {
                    id: gridThumbnailArea
                    width: parent.width
                    height: width

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                        radius: Theme.paddingMedium
                        visible: gridThumbnail.status !== Image.Ready
                    }

                    Icon {
                        anchors.centerIn: parent
                        source: "image://theme/icon-m-image"
                        visible: gridThumbnail.status !== Image.Ready
                    }

                    Image {
                        id: gridThumbnail
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: albumThumbnailAssetId ? "image://immich/thumbnail/" + albumThumbnailAssetId : ""
                        asynchronous: true
                        sourceSize.width: width
                        sourceSize.height: height
                        visible: status === Image.Ready
                        layer.enabled: status === Image.Ready
                        layer.effect: OpacityMask {
                            maskSource: Item {
                                width: gridThumbnail.width
                                height: gridThumbnail.height

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.paddingMedium
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: albumId === albumPickerDialog.selectedAlbumId ? Theme.rgba(Theme.highlightBackgroundColor, 0.2) : "transparent"
                        border.width: albumId === albumPickerDialog.selectedAlbumId ? 2 : 0
                        border.color: Theme.highlightColor
                        radius: Theme.paddingMedium
                        z: 10
                    }
                }

                Label {
                    id: gridNameLabel
                    anchors.top: gridThumbnailArea.bottom
                    anchors.topMargin: Theme.paddingSmall
                    width: parent.width
                    text: albumName
                    color: (albumDelegate.highlighted || albumId === albumPickerDialog.selectedAlbumId) ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    truncationMode: TruncationMode.Fade
                }

                Label {
                    anchors.top: gridNameLabel.bottom
                    width: parent.width
                    text: (assetCount === 1
                        //% "1 asset"
                        ? qsTrId("albumPickerPage.asset")
                        //% "%1 assets"
                        : qsTrId("albumPickerPage.assets").arg(assetCount)) + (isOwned ? "" : " · " +
                        //% "Shared by %1"
                        qsTrId("albumPickerPage.sharedBy").arg(ownerName))
                    color: (albumDelegate.highlighted || albumId === albumPickerDialog.selectedAlbumId) ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }

            onClicked: {
                if (albumPickerDialog.selectedAlbumId !== albumId) {
                    albumPickerDialog.selectedAlbumId = albumId
                    albumPickerDialog.createNew = false
                    albumPickerDialog.newAlbumName = ""
                } else {
                    albumPickerDialog.selectedAlbumId = ""
                }
            }
        }

        footer: Item {
            width: albumGrid.width
            property bool shown: albumGrid.count === 0 || (albumPickerDialog.filterText.length > 0 && albumPickerDialog.filteredCount === 0)
            height: shown ? Math.max(Theme.itemSizeHuge, (albumPickerDialog.isPortrait ? Screen.height : Screen.width) - (albumGrid.headerItem ? albumGrid.headerItem.height : 0)) : 0

            EmptyState {
                anchors.fill: parent
                visible: parent.shown
                iconSource: "image://theme/icon-m-folder"
                message: albumPickerDialog.filterText.length > 0
                    //% "No albums match filter"
                    ? qsTrId("albumPickerPage.noAlbumsMatch")
                    //% "No albums yet"
                    : qsTrId("albumPickerPage.noAlbums")
            }
        }

        VerticalScrollDecorator {}
    }

    Timer {
        id: scrollToTopTimer
        interval: 1
        onTriggered: albumGrid.positionViewAtBeginning()
    }

    onStatusChanged: if (status === PageStatus.Active) applyFilter()
}
