import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
  id: page

  property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
  property real thumbnailSize: width / assetsPerRow

  // Filter state: "all", "shared", "sharedWithMe", "mine"
  property string activeFilter: "all"
  property var loadedAlbums: []
  property int filteredCount: 0
  property bool sharedSubsetVisible: activeFilter === "shared" || activeFilter === "sharedWithMe"

  // Text filter
  property string filterText: ""

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

  function setActiveFilter(filterId) {
      if (activeFilter !== filterId) {
          activeFilter = filterId
          applyFilter()
      }
  }

  function toggleSharedWithMeFilter() {
      if (activeFilter === "sharedWithMe") {
          setActiveFilter("shared")
      } else {
          setActiveFilter("sharedWithMe")
      }
  }

  function applyFilter() {
      if (activeFilter === "shared" || activeFilter === "sharedWithMe") {
          immichApi.fetchAlbums("true")
      } else if (activeFilter === "mine") {
          immichApi.fetchAlbums("false")
      } else {
          immichApi.fetchAlbums()
      }
  }

  function updateFilteredCount() {
      var count = 0
      for (var i = 0; i < loadedAlbums.length; i++) {
          var album = loadedAlbums[i]
          if (activeFilter === "sharedWithMe" && album.ownerId === authManager.userId) {
              continue
          }
          if (filterText.length > 0 && (!album.albumName || album.albumName.toLowerCase().indexOf(filterText) === -1)) {
              continue
          }
          count++
      }
      filteredCount = count
  }

  onFilterTextChanged: updateFilteredCount()

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
              //% "Library"
              text: qsTrId("albumsPage.library")
              onClicked: pageStack.push(Qt.resolvedUrl("LibraryPage.qml"))
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

          Item {
              width: listView.width
              height: filterRow.implicitHeight + Theme.paddingSmall

              Row {
                  id: filterRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Theme.horizontalPageMargin
                  anchors.rightMargin: Theme.horizontalPageMargin
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Theme.paddingSmall

                  Repeater {
                      id: filterRepeater
                      model: [
                          //% "All"
                          { id: "all", label: qsTrId("albumsPage.filterAll"), icon: "image://theme/icon-m-folder" },
                          //% "Shared"
                          { id: "shared", label: qsTrId("albumsPage.filterShared"), icon: "image://theme/icon-m-share" },
                          //% "My albums"
                          { id: "mine", label: qsTrId("albumsPage.filterMyAlbums"), icon: "image://theme/icon-m-person" }
                      ]

                      BackgroundItem {
                          width: (filterRow.width - filterRow.spacing * (filterRepeater.count - 1)) / filterRepeater.count
                          height: Theme.itemExtraSizeSmall
                          highlighted: modelData.id === "shared" ? page.activeFilter === "shared" || page.activeFilter === "sharedWithMe" : page.activeFilter === modelData.id

                          Rectangle {
                              anchors.fill: parent
                              radius: Theme.paddingSmall
                              color: (modelData.id === "shared" ? page.activeFilter === "shared" || page.activeFilter === "sharedWithMe" : page.activeFilter === modelData.id) ? Theme.rgba(Theme.highlightBackgroundColor, 0.4) : Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                              border.width: (modelData.id === "shared" ? page.activeFilter === "shared" || page.activeFilter === "sharedWithMe" : page.activeFilter === modelData.id) ? 1 : 0
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
                                  color: (modelData.id === "shared" ? page.activeFilter === "shared" || page.activeFilter === "sharedWithMe" : page.activeFilter === modelData.id) ? Theme.highlightColor : Theme.primaryColor
                              }

                              Label {
                                  text: modelData.label
                                  font.pixelSize: Theme.fontSizeExtraSmall
                                  color: (modelData.id === "shared" ? page.activeFilter === "shared" || page.activeFilter === "sharedWithMe" : page.activeFilter === modelData.id) ? Theme.highlightColor : Theme.primaryColor
                                  anchors.verticalCenter: parent.verticalCenter
                                  truncationMode: TruncationMode.Fade
                              }
                          }

                          onClicked: page.setActiveFilter(modelData.id)
                      }
                  }
              }
          }

          // Sort row
          Item {
              width: listView.width
              height: Theme.itemSizeExtraSmall

              BackgroundItem {
                  id: sortOrderButton
                  anchors.right: page.sharedSubsetVisible ? sharedWithMeButton.left : parent.right
                  anchors.rightMargin: page.sharedSubsetVisible ? Theme.paddingSmall : Theme.horizontalPageMargin
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

              BackgroundItem {
                  id: sharedWithMeButton
                  anchors.right: parent.right
                  anchors.rightMargin: Theme.horizontalPageMargin
                  anchors.verticalCenter: parent.verticalCenter
                  width: visible ? Theme.itemSizeSmall : 0
                  height: Theme.itemSizeExtraSmall
                  visible: page.sharedSubsetVisible
                  highlighted: page.activeFilter === "sharedWithMe"

                  Rectangle {
                      anchors.fill: parent
                      radius: Theme.paddingSmall
                      color: page.activeFilter === "sharedWithMe" ? Theme.rgba(Theme.highlightBackgroundColor, 0.4) : Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                      border.width: page.activeFilter === "sharedWithMe" ? 1 : 0
                      border.color: Theme.highlightColor
                  }

                  Icon {
                      anchors.centerIn: parent
                      source: "image://theme/icon-m-message"
                      width: Theme.iconSizeSmall
                      height: Theme.iconSizeSmall
                      color: page.activeFilter === "sharedWithMe" ? Theme.highlightColor : Theme.primaryColor
                  }

                  onClicked: page.toggleSharedWithMeFilter()
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

          SearchField {
              id: albumSearchField
              width: listView.width
              visible: listView.count > 5
              //% "Filter albums..."
              placeholderText: qsTrId("albumsPage.filter")
              onTextChanged: page.filterText = text.toLowerCase()
              EnterKey.iconSource: "image://theme/icon-m-enter-close"
              EnterKey.onClicked: focus = false
          }
      }

      delegate: ListItem {
          id: listItem

          property bool matchesFilter: page.filterText.length === 0 || albumName.toLowerCase().indexOf(page.filterText) !== -1
          property bool matchesAlbumFilter: page.activeFilter !== "sharedWithMe" || !isOwned

          contentHeight: matchesFilter && matchesAlbumFilter ? page.thumbnailSize + 2 * Theme.paddingMedium : 0
          visible: matchesFilter && matchesAlbumFilter

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

      // Empty state
      Column {
          width: parent.width
          spacing: Theme.paddingLarge
          visible: filteredCount === 0
          anchors.verticalCenter: parent.verticalCenter

          Icon {
              anchors.horizontalCenter: parent.horizontalCenter
              source: page.activeFilter === "all" ? "image://theme/icon-m-folder" : page.activeFilter === "shared" ? "image://theme/icon-m-share" : page.activeFilter === "sharedWithMe" ? "image://theme/icon-m-message" : "image://theme/icon-m-person"
              color: Theme.highlightColor
          }

          Label {
              x: Theme.horizontalPageMargin
              width: parent.width - 2 * Theme.horizontalPageMargin
              text: page.activeFilter === "all"
                    //% "No albums"
                    ? qsTrId("albumsPage.noAlbums") : page.activeFilter === "shared"
                    //% "No shared albums"
                    ? qsTrId("albumsPage.noSharedAlbums") : page.activeFilter === "sharedWithMe"
                    //% "No albums shared with you"
                    ? qsTrId("albumsPage.noSharedWithMeAlbums")
                    //% "No personal albums"
                    : qsTrId("albumsPage.noMyAlbums")
              font.pixelSize: Theme.fontSizeLarge
              color: Theme.highlightColor
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
          }

          Label {
              x: Theme.horizontalPageMargin
              width: parent.width - 2 * Theme.horizontalPageMargin
              text: page.activeFilter === "all"
                    //% "Pull down to refresh or create albums in Immich"
                    ? qsTrId("albumsPage.noAllAlbumsHint") : page.activeFilter === "shared"
                    //% "Shared albums will appear here"
                    ? qsTrId("albumsPage.noSharedAlbumsHint") : page.activeFilter === "sharedWithMe"
                    //% "Albums shared with you will appear here"
                    ? qsTrId("albumsPage.noSharedWithMeAlbumsHint")
                    //% "Create an album in Immich to see it here"
                    : qsTrId("albumsPage.noMyAlbumsHint")
              font.pixelSize: Theme.fontSizeSmall
              color: Theme.secondaryHighlightColor
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
          }
      }

      VerticalScrollDecorator {}
  }

  ScrollToTopButton {
      targetFlickable: listView
  }

  Timer {
      id: scrollToTopTimer
      interval: 1
      onTriggered: listView.positionViewAtBeginning()
  }

  Connections {
      target: immichApi
      onAlbumsReceived: {
          page.loadedAlbums = albums
          page.applySorting()
          page.updateFilteredCount()
          scrollToTopTimer.restart()
      }
      onAlbumUpdated: {
          albumModel.updateAlbumMetadata(albumId, albumName, albumThumbnailAssetId)
      }
  }

  Component.onCompleted: {
      page.applyFilter()
  }
}
