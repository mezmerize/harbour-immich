import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
  id: page

  property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
  property real thumbnailSize: width / assetsPerRow

  // Filter state: "all", "shared", "mine"
  property string activeFilter: "all"

  // Sort state
  property string sortField: "endDate"
  property bool sortAscending: false

  // Sort field mapping (index matches ComboBox MenuItem order)
  property var sortOptions: [
      { field: "endDate" },
      { field: "startDate" },
      { field: "albumName" },
      { field: "assetCount" },
      { field: "updatedAt" },
      { field: "createdAt" }
  ]

  function applySorting() {
      albumModel.sortAlbums(sortField, sortAscending)
  }

  function applyFilter() {
      if (activeFilter === "shared") {
          immichApi.fetchAlbums("true")
      } else if (activeFilter === "mine") {
          immichApi.fetchAlbums("false")
      } else {
          immichApi.fetchAlbums()
      }
  }

  SilicaListView {
      id: listView
      anchors.fill: parent
      clip: true
      model: albumModel

      PullDownMenu {
          MenuItem {
              //% "Settings"
              text: qsTrId("albumsPage.settings")
              onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
          }

          MenuItem {
              //% "Search"
              text: qsTrId("albumsPage.search")
              onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
          }

          MenuItem {
              //% "Timeline"
              text: qsTrId("albumsPage.timeline")
              onClicked: pageStack.replaceAbove(null, Qt.resolvedUrl("TimelinePage.qml"))
          }

          MenuItem {
              //% "Refresh"
              text: qsTrId("albumsPage.refresh")
              onClicked: page.applyFilter()
          }
      }

      header: Column {
          width: listView.width

          PageHeader {
              //% "Albums"
              title: qsTrId("albumsPage.albums")
          }

          // Sort row
          Item {
              width: listView.width
              height: Theme.itemSizeExtraSmall

              BackgroundItem {
                  id: sortOrderButton
                  anchors.right: parent.right
                  anchors.rightMargin: Theme.horizontalPageMargin
                  anchors.verticalCenter: parent.verticalCenter
                  width: Theme.itemSizeSmall
                  height: Theme.itemSizeExtraSmall

                  Rectangle {
                      anchors.fill: parent
                      radius: Theme.paddingSmall
                      color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                  }

                  Icon {
                      anchors.centerIn: parent
                      source: page.sortAscending ? "image://theme/icon-m-up" : "image://theme/icon-m-down"
                      width: Theme.iconSizeSmall
                      height: Theme.iconSizeSmall
                  }

                  onClicked: {
                      page.sortAscending = !page.sortAscending
                      page.applySorting()
                  }
              }

              ComboBox {
                  id: sortCombo
                  anchors.left: parent.left
                  anchors.right: sortOrderButton.left
                  anchors.verticalCenter: parent.verticalCenter
                  //% "Sort by"
                  label: qsTrId("albumsPage.sortBy")
                  currentIndex: 0

                  menu: ContextMenu {
                      //% "Most recent photo"
                      MenuItem { text: qsTrId("albumsPage.sortEndDate") }
                      //% "Oldest photo"
                      MenuItem { text: qsTrId("albumsPage.sortStartDate") }
                      //% "Album title"
                      MenuItem { text: qsTrId("albumsPage.sortAlbumName") }
                      //% "Number of assets"
                      MenuItem { text: qsTrId("albumsPage.sortAssetCount") }
                      //% "Last modified"
                      MenuItem { text: qsTrId("albumsPage.sortUpdatedAt") }
                      //% "Created date"
                      MenuItem { text: qsTrId("albumsPage.sortCreatedAt") }
                  }

                  onCurrentIndexChanged: {
                      if (currentIndex >= 0 && currentIndex < page.sortOptions.length) {
                          page.sortField = page.sortOptions[currentIndex].field
                          page.applySorting()
                      }
                  }
              }
          }

          // Quick filters row
          Item {
              width: listView.width
              height: Theme.itemSizeExtraSmall + Theme.paddingMedium

              Row {
                  id: filterRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Theme.horizontalPageMargin
                  anchors.rightMargin: Theme.horizontalPageMargin
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Theme.paddingSmall

                  Repeater {
                      model: [
                          //% "All"
                          { id: "all", label: qsTrId("albumsPage.filterAll"), icon: "image://theme/icon-m-folder" },
                          //% "Shared with me"
                          { id: "shared", label: qsTrId("albumsPage.filterSharedWithMe"), icon: "image://theme/icon-m-share" },
                          //% "My albums"
                          { id: "mine", label: qsTrId("albumsPage.filterMyAlbums"), icon: "image://theme/icon-m-person" }
                      ]

                      BackgroundItem {
                          width: (filterRow.width - 2 * Theme.paddingSmall) / 3
                          height: Theme.itemSizeExtraSmall
                          highlighted: page.activeFilter === modelData.id

                          Rectangle {
                              anchors.fill: parent
                              radius: Theme.paddingSmall
                              color: page.activeFilter === modelData.id ?
                                     Theme.rgba(Theme.highlightBackgroundColor, 0.4) :
                                     Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                              border.width: page.activeFilter === modelData.id ? 1 : 0
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
                                  color: page.activeFilter === modelData.id ? Theme.highlightColor : Theme.primaryColor
                              }

                              Label {
                                  text: modelData.label
                                  font.pixelSize: Theme.fontSizeExtraSmall
                                  color: page.activeFilter === modelData.id ? Theme.highlightColor : Theme.primaryColor
                                  anchors.verticalCenter: parent.verticalCenter
                              }
                          }

                          onClicked: {
                              if (page.activeFilter !== modelData.id) {
                                  page.activeFilter = modelData.id
                                  page.applyFilter()
                              }
                          }
                      }
                  }
              }
          }
      }

      delegate: ListItem {
          id: listItem
          contentHeight: page.thumbnailSize + 2 * Theme.paddingMedium

          Row {
              anchors.fill: parent
              anchors.margins: Theme.paddingMedium
              spacing: Theme.paddingMedium

              Item {
                  width: page.thumbnailSize
                  height: width

                  Image {
                      id: albumThumbnail
                      anchors.fill: parent
                      fillMode: Image.PreserveAspectCrop
                      source: albumThumbnailAssetId ? "image://immich/thumbnail/" + albumThumbnailAssetId : ""
                      asynchronous: true

                      Rectangle {
                          anchors.fill: parent
                          color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                          visible: albumThumbnail.status !== Image.Ready
                      }

                      Image {
                          anchors.centerIn: parent
                          source: "image://theme/icon-m-image"
                          visible: albumThumbnail.status !== Image.Ready
                      }
                  }

                  Rectangle {
                      anchors.bottom: parent.bottom
                      anchors.right: parent.right
                      anchors.margins: Theme.paddingSmall
                      width: countLabel.width + Theme.paddingMedium
                      height: countLabel.height + Theme.paddingSmall
                      radius: Theme.paddingSmall
                      color: Theme.rgba(Theme.highlightBackgroundColor, 0.9)

                      Label {
                          id: countLabel
                          anchors.centerIn: parent
                          text: assetCount
                          font.pixelSize: Theme.fontSizeSmall
                          font.bold: true
                          color: Theme.primaryColor
                      }
                  }
              }

              Column {
                  width: parent.width - page.thumbnailSize - 3 * Theme.paddingMedium
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Theme.paddingSmall

                  Label {
                      width: parent.width
                      text: albumName
                      color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                      font.pixelSize: Theme.fontSizeMedium
                      truncationMode: TruncationMode.Fade
                  }

                  Label {
                      width: parent.width
                      text: assetCount === 1
                            //% "1 asset"
                            ? qsTrId("albumsPage.asset")
                            //% "%1 assets"
                            : qsTrId("albumsPage.assets").arg(assetCount)
                      color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                      font.pixelSize: Theme.fontSizeSmall
                  }

                  Label {
                      width: parent.width
                      text: isOwned
                            //% "Owned"
                            ? qsTrId("albumsPage.owned")
                            //% "Shared by %1"
                            : qsTrId("albumsPage.sharedBy").arg(ownerName)
                      color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                      font.pixelSize: Theme.fontSizeExtraSmall
                      truncationMode: TruncationMode.Fade
                  }
              }
          }

          onClicked: {
              pageStack.push(Qt.resolvedUrl("AlbumDetailPage.qml"), {
                  albumId: albumId,
                  albumName: albumName,
                  assetCount: assetCount
              })
          }
      }

      ViewPlaceholder {
          enabled: listView.count === 0
          //% "No albums"
          text: qsTrId("albumsPage.noAlbums")
          //% "Pull down to refresh"
          hintText: qsTrId("albumsPage.noAlbumsHint")
      }


      VerticalScrollDecorator {}
  }

  ScrollToTopButton {
      targetFlickable: listView
  }

  Connections {
      target: immichApi
      onAlbumsReceived: {
          page.applySorting()
      }
  }

  Component.onCompleted: {
      page.applyFilter()
  }
}
