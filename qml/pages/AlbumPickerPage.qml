import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
  id: albumPickerDialog

  property var assetIds: []
  property string selectedAlbumId: ""
  property string newAlbumName: ""
  property bool createNew: false
  property string filterText: ""
  property string activeAlbumFilter: "all"
  property int filteredCount: albumModel.rowCount()

  function applyAlbumFilter() {
      if (activeAlbumFilter === "shared") {
          immichApi.fetchAlbums("true")
      } else if (activeAlbumFilter === "mine") {
          immichApi.fetchAlbums("false")
      } else {
          immichApi.fetchAlbums()
      }
  }

  function updateFilteredCount() {
      if (filterText.length === 0) {
          filteredCount = albumModel.rowCount()
          return
      }
      var count = 0
      for (var i = 0; i < albumModel.rowCount(); i++) {
          var name = albumModel.data(albumModel.index(i, 0), Qt.UserRole + 2) // AlbumNameRole
          if (name && name.toString().toLowerCase().indexOf(filterText) !== -1) {
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
      onAlbumCreated: {
          immichApi.addAssetsToAlbum(albumId, assetIds)
      }
  }

  SilicaFlickable {
      anchors.fill: parent
      contentHeight: column.height

      Column {
          id: column
          width: parent.width

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
              onTextChanged: {
                  albumPickerDialog.newAlbumName = text
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
              visible: albumModel.rowCount() > 0
          }

          // Album type filter row
          Item {
              width: parent.width
              height: Theme.itemSizeExtraSmall + Theme.paddingMedium
              visible: albumModel.rowCount() > 0

              Row {
                  id: albumFilterRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Theme.horizontalPageMargin
                  anchors.rightMargin: Theme.horizontalPageMargin
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Theme.paddingSmall

                  Repeater {
                      model: [
                          //% "All"
                          { id: "all", label: qsTrId("albumPickerPage.filterAll"), icon: "image://theme/icon-m-folder" },
                          //% "Shared with me"
                          { id: "shared", label: qsTrId("albumPickerPage.filterSharedWithMe"), icon: "image://theme/icon-m-share" },
                          //% "My albums"
                          { id: "mine", label: qsTrId("albumPickerPage.filterMyAlbums"), icon: "image://theme/icon-m-person" }
                      ]

                      BackgroundItem {
                          width: (albumFilterRow.width - 2 * Theme.paddingSmall) / 3
                          height: Theme.itemSizeExtraSmall
                          highlighted: albumPickerDialog.activeAlbumFilter === modelData.id

                          Rectangle {
                              anchors.fill: parent
                              radius: Theme.paddingSmall
                              color: albumPickerDialog.activeAlbumFilter === modelData.id ?
                                     Theme.rgba(Theme.highlightBackgroundColor, 0.4) :
                                     Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                              border.width: albumPickerDialog.activeAlbumFilter === modelData.id ? 1 : 0
                              border.color: Theme.highlightColor
                          }

                          Row {
                              anchors.centerIn: parent
                              spacing: Theme.paddingSmall

                              Icon {
                                  source: modelData.icon
                                  width: Theme.iconSizeSmall
                                  height: Theme.iconSizeSmall
                                  anchors.verticalCenter: parent.verticalCenter
                                  color: albumPickerDialog.activeAlbumFilter === modelData.id ? Theme.highlightColor : Theme.primaryColor
                              }

                              Label {
                                  text: modelData.label
                                  font.pixelSize: Theme.fontSizeExtraSmall
                                  color: albumPickerDialog.activeAlbumFilter === modelData.id ? Theme.highlightColor : Theme.primaryColor
                                  anchors.verticalCenter: parent.verticalCenter
                              }
                          }

                          onClicked: {
                              if (albumPickerDialog.activeAlbumFilter !== modelData.id) {
                                  albumPickerDialog.activeAlbumFilter = modelData.id
                                  albumPickerDialog.applyAlbumFilter()
                              }
                          }
                      }
                  }
              }
          }

          SearchField {
              id: albumFilterField
              width: parent.width
              //% "Filter albums..."
              placeholderText: qsTrId("albumPickerPage.filter")
              visible: albumModel.rowCount() > 5

              onTextChanged: {
                  albumPickerDialog.filterText = text.toLowerCase()
              }

              EnterKey.iconSource: "image://theme/icon-m-enter-close"
              EnterKey.onClicked: focus = false
          }

          Label {
              x: Theme.horizontalPageMargin
              width: parent.width - 2 * Theme.horizontalPageMargin
              text: filterText.length > 0 ? (filteredCount === 1
                     //% "1 result"
                     ? qsTrId("albumPickerPage.result")
                     //% "%1 results"
                     : qsTrId("albumPickerPage.results").arg(filteredCount)) : (albumModel.rowCount() === 1
                     //% "1 album"
                     ? qsTrId("albumPickerPage.album")
                     //% "%1 albums"
                     : qsTrId("albumPickerPage.albums").arg(albumModel.rowCount()))
              font.pixelSize: Theme.fontSizeExtraSmall
              color: Theme.secondaryColor
              visible: albumModel.rowCount() > 5
          }

          Repeater {
              id: filteredAlbumRepeater
              model: albumModel

              ListItem {
                  id: albumListItem

                  property bool matchesFilter: filterText.length === 0 || albumName.toLowerCase().indexOf(filterText) !== -1

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
                      newAlbumField.text = ""
                  }
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
              visible: albumModel.rowCount() === 0 || (filterText.length > 0 && filteredCount === 0)
              wrapMode: Text.Wrap
          }

          Item {
              width: parent.width
              height: Theme.paddingLarge
          }
      }

      VerticalScrollDecorator {}
  }
}
