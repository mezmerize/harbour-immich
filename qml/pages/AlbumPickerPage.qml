import QtQuick 2.0
import Sailfish.Silica 1.0
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
        if (activeFilter === "shared") {
            immichApi.fetchAlbums("true")
        } else if (activeFilter === "mine") {
            immichApi.fetchAlbums("false")
        } else {
            immichApi.fetchAlbums()
        }
    }

    function updateFilteredCount() {
        if (filterText.length === 0) {
            filteredCount = listView.count
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

    SilicaListView {
        id: listView
        anchors.fill: parent
        clip: true
        model: albumModel

        header: Column {
            width: listView.width

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
                visible: listView.count > 0
            }

            // Album type filter row
            AlbumFilterBar {
                visible: listView.count > 0
                width: listView.width
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
                width: listView.width
                //% "Filter albums..."
                placeholderText: qsTrId("albumPickerPage.filter")
                visible: listView.count > 5
                onTextChanged: albumPickerDialog.filterText = text.toLowerCase()
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            Label {
                x: Theme.horizontalPageMargin
                width: listView.width - 2 * Theme.horizontalPageMargin
                text: filterText.length > 0 ? (filteredCount === 1
                    //% "1 result"
                    ? qsTrId("albumPickerPage.result")
                    //% "%1 results"
                    : qsTrId("albumPickerPage.results").arg(filteredCount)) : (listView.count === 1
                    //% "1 album"
                    ? qsTrId("albumPickerPage.album")
                    //% "%1 albums"
                    : qsTrId("albumPickerPage.albums").arg(listView.count))
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                visible: listView.count > 5
            }
        }

        delegate: ListItem {
            id: albumListItem

            property bool matchesFilter: albumPickerDialog.filterText.length === 0 || albumName.toLowerCase().indexOf(albumPickerDialog.filterText) !== -1

            contentHeight: matchesFilter ? Theme.itemSizeMedium : 0
            visible: matchesFilter
            highlighted: down || albumPickerDialog.selectedAlbumId === albumId

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingMedium
                visible: albumListItem.matchesFilter

                Icon {
                    source: "image://theme/icon-m-folder"
                    width: Theme.iconSizeMedium
                    height: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        text: albumName
                        color: albumListItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }

                    Label {
                        text: assetCount === 1
                            //% "1 asset"
                            ? qsTrId("albumPickerPage.asset")
                            //% "%1 assets"
                            : qsTrId("albumPickerPage.assets").arg(assetCount || 0)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryColor
                    }
                }
            }

            onClicked: {
                albumPickerDialog.selectedAlbumId = albumId
                albumPickerDialog.createNew = false
                albumPickerDialog.newAlbumName = ""
            }
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            text: filterText.length > 0
                //% "No albums match filter"
                ? qsTrId("albumPickerPage.noAlbumsMatch")
                //% "No albums yet"
                : qsTrId("albumPickerPage.noAlbums")
            color: Theme.secondaryColor
            visible: listView.count === 0 || (filterText.length > 0 && filteredCount === 0)
            wrapMode: Text.Wrap
        }

        VerticalScrollDecorator {}
    }

    Timer {
        id: scrollToTopTimer
        interval: 1
        onTriggered: listView.positionViewAtBeginning()
    }

    onStatusChanged: if (status === PageStatus.Active) applyFilter()
}
