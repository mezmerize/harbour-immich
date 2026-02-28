import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
  id: page

  property string albumId
  property string albumName
  property string albumDescription: ""
  property int assetCount
  property bool selectionMode: false
  property var selectedAssets: []
  property bool allSelectedAreFavorites: false
  property bool sortNewestFirst: true
  property bool loading: true

  // Grouped assets data
  property var allAssets: []       // flat list for navigation
  property var groupedAssets: []   // [{monthYear, groups: [{displayDate, assets: [...]}]}]
  property var heroAssetIds: []    // random asset IDs for hero rotation
  property string dateRange: ""

  function updateAllSelectedAreFavorites() {
      if (selectedAssets.length === 0) {
          allSelectedAreFavorites = false
          return
      }
      for (var i = 0; i < allAssets.length; i++) {
          if (selectedAssets.indexOf(allAssets[i].id) > -1 && !allAssets[i].isFavorite) {
              allSelectedAreFavorites = false
              return
          }
      }
      allSelectedAreFavorites = true
  }

  function toggleAssetSelection(assetId) {
      var index = selectedAssets.indexOf(assetId)
      if (index > -1) {
          selectedAssets.splice(index, 1)
      } else {
          selectedAssets.push(assetId)
      }
      selectedAssets = selectedAssets
      if (selectedAssets.length === 0) {
          selectionMode = false
      }
      updateAllSelectedAreFavorites()
  }

  function clearSelection() {
      selectedAssets = []
      selectionMode = false
  }

  function isAssetSelected(assetId) {
      return selectedAssets.indexOf(assetId) > -1
  }

  function processAlbumDetails(details) {
      albumName = details.albumName || albumName
      albumDescription = details.description || ""
      assetCount = details.assetCount || 0

      var assets = details.assets || []
      var parsed = []
      for (var i = 0; i < assets.length; i++) {
          var a = assets[i]
          var dt = a.localDateTime || a.fileCreatedAt || a.createdAt || ""
          parsed.push({
              id: a.id,
              isFavorite: a.isFavorite || false,
              isVideo: a.type === "VIDEO",
              thumbhash: a.thumbhash || "",
              duration: a.duration || "",
              dateTime: dt,
              dateObj: new Date(dt)
          })
      }

      // Sort
      parsed.sort(function(a, b) {
          return sortNewestFirst ? b.dateObj - a.dateObj : a.dateObj - b.dateObj
      })

      allAssets = parsed

      // Pick hero asset IDs (up to 5 random)
      var heroIds = []
      if (parsed.length > 0) {
          var indices = []
          for (var h = 0; h < parsed.length; h++) indices.push(h)
          // Shuffle
          for (var s = indices.length - 1; s > 0; s--) {
              var j = Math.floor(Math.random() * (s + 1))
              var tmp = indices[s]; indices[s] = indices[j]; indices[j] = tmp
          }
          for (var k = 0; k < Math.min(5, indices.length); k++) {
              if (!parsed[indices[k]].isVideo) {
                  heroIds.push(parsed[indices[k]].id)
              }
              if (heroIds.length >= 5) break
          }
          // Fallback: if no non-video found, use first asset
          if (heroIds.length === 0 && parsed.length > 0) {
              heroIds.push(parsed[0].id)
          }
      }
      heroAssetIds = heroIds

      // Calculate date range
      if (parsed.length > 0) {
          var sorted = parsed.slice().sort(function(a, b) { return a.dateObj - b.dateObj })
          var earliest = sorted[0].dateObj
          var latest = sorted[sorted.length - 1].dateObj
          var fmt = function(d) { return Qt.formatDate(d, "dd.MM.yyyy") }
          dateRange = fmt(earliest) + " — " + fmt(latest)
      } else {
          dateRange = ""
      }

      // Group by month+year, then by date
      var monthMap = {}
      var monthOrder = []
      var months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
      for (var g = 0; g < parsed.length; g++) {
          var asset = parsed[g]
          var d = asset.dateObj
          var monthKey = d.getFullYear() + "-" + (d.getMonth() + 1)
          var monthLabel = months[d.getMonth()] + " " + d.getFullYear()
          var dateKey = d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
          var dateLabel = Qt.formatDate(d, "dd.MM.yyyy")

          if (!monthMap[monthKey]) {
              monthMap[monthKey] = { monthYear: monthLabel, dateMap: {}, dateOrder: [] }
              monthOrder.push(monthKey)
          }
          var month = monthMap[monthKey]
          if (!month.dateMap[dateKey]) {
              month.dateMap[dateKey] = { displayDate: dateLabel, assets: [] }
              month.dateOrder.push(dateKey)
          }
          month.dateMap[dateKey].assets.push({
              id: asset.id,
              isFavorite: asset.isFavorite,
              isVideo: asset.isVideo,
              thumbhash: asset.thumbhash,
              duration: asset.duration,
              assetIndex: g
          })
      }

      var result = []
      for (var m = 0; m < monthOrder.length; m++) {
          var mData = monthMap[monthOrder[m]]
          var groups = []
          for (var dd = 0; dd < mData.dateOrder.length; dd++) {
              groups.push(mData.dateMap[mData.dateOrder[dd]])
          }
          result.push({ monthYear: mData.monthYear, groups: groups })
      }
      groupedAssets = result
      loading = false
  }

  property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
  property real cellSize: page.width / assetsPerRow

  SilicaFlickable {
      id: flickable
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: selectionActionBar.visible ? selectionActionBar.top : parent.bottom
      contentHeight: contentColumn.height
      clip: true

      PullDownMenu {
          enabled: !page.selectionMode

          MenuItem {
              //% "Refresh"
              text: qsTrId("albumDetailPage.refresh")
              onClicked: {
                  page.loading = true
                  immichApi.fetchAlbumDetails(albumId)
              }
          }

          MenuItem {
              //% "Edit album"
              text: qsTrId("albumDetailPage.editAlbum")
              onClicked: {
                  pageStack.push(Qt.resolvedUrl("EditAlbumDialog.qml"), {
                      albumId: albumId,
                      albumName: albumName,
                      albumDescription: albumDescription
                  })
              }
          }

          MenuItem {
              //% "Information"
              text: qsTrId("albumDetailPage.information")
              onClicked: {
                  pageStack.push(Qt.resolvedUrl("AlbumInfoPage.qml"), {
                      albumId: albumId
                  })
              }
          }

          MenuItem {
              //% "Share album"
              text: qsTrId("albumDetailPage.share")
              onClicked: {
                  pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                      albumId: albumId,
                      shareType: "ALBUM"
                  })
              }
          }

          MenuItem {
              text: sortNewestFirst
                    //% "Show oldest first"
                    ? qsTrId("albumDetailPage.showOldestFirst")
                    //% "Show newest first"
                    : qsTrId("albumDetailPage.showNewestFirst")
              onClicked: {
                  sortNewestFirst = !sortNewestFirst
                  page.loading = true
                  immichApi.fetchAlbumDetails(albumId)
              }
          }
      }

      Column {
          id: contentColumn
          width: parent.width

          // Hero section
          Item {
              width: parent.width
              height: page.height / 2
              clip: true

              // Background image A
              Image {
                  id: heroImageA
                  anchors.fill: parent
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  smooth: true
                  opacity: 1
                  scale: 1.0
                  source: heroAssetIds.length > 0 ? "image://immich/detail/" + heroAssetIds[0] : ""
              }

              // Background image B (for crossfade)
              Image {
                  id: heroImageB
                  anchors.fill: parent
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  smooth: true
                  opacity: 0
                  scale: 1.0
                  source: ""
              }

              // Slow zoom animation for A
              NumberAnimation {
                  id: zoomAnimA
                  target: heroImageA
                  property: "scale"
                  from: 1.0
                  to: 1.15
                  duration: 8000
                  easing.type: Easing.Linear
              }

              // Slow zoom animation for B
              NumberAnimation {
                  id: zoomAnimB
                  target: heroImageB
                  property: "scale"
                  from: 1.0
                  to: 1.15
                  duration: 8000
                  easing.type: Easing.Linear
              }

              // Crossfade: fade A out, B in
              ParallelAnimation {
                  id: crossfadeToB
                  NumberAnimation { target: heroImageA; property: "opacity"; to: 0; duration: 1500; easing.type: Easing.InOutQuad }
                  NumberAnimation { target: heroImageB; property: "opacity"; to: 1; duration: 1500; easing.type: Easing.InOutQuad }
              }

              // Crossfade: fade B out, A in
              ParallelAnimation {
                  id: crossfadeToA
                  NumberAnimation { target: heroImageA; property: "opacity"; to: 1; duration: 1500; easing.type: Easing.InOutQuad }
                  NumberAnimation { target: heroImageB; property: "opacity"; to: 0; duration: 1500; easing.type: Easing.InOutQuad }
              }

              property int heroIndex: 0
              property bool showingA: true

              Timer {
                  id: heroTimer
                  interval: 6000
                  repeat: true
                  running: heroAssetIds.length > 1 && page.status === PageStatus.Active
                  onTriggered: {
                      var parent = heroImageA.parent
                      parent.heroIndex = (parent.heroIndex + 1) % heroAssetIds.length
                      var nextSource = "image://immich/detail/" + heroAssetIds[parent.heroIndex]

                      if (parent.showingA) {
                          heroImageB.scale = 1.0
                          heroImageB.source = nextSource
                          crossfadeToB.start()
                          zoomAnimB.start()
                      } else {
                          heroImageA.scale = 1.0
                          heroImageA.source = nextSource
                          crossfadeToA.start()
                          zoomAnimA.start()
                      }
                      parent.showingA = !parent.showingA
                  }
              }

              // Start initial zoom
              Component.onCompleted: {
                  if (heroAssetIds.length > 0) {
                      zoomAnimA.start()
                  }
              }

              // Gradient overlay at bottom
              Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: parent.height * 0.6
                  gradient: Gradient {
                      GradientStop { position: 0.0; color: "transparent" }
                      GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightDimmerColor, 0.95) }
                  }
              }

              // Album info overlay
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
                      text: albumName
                      font.pixelSize: Theme.fontSizeExtraLarge
                      font.bold: true
                      color: Theme.primaryColor
                      truncationMode: TruncationMode.Fade
                  }

                  Label {
                      width: parent.width
                      text: albumDescription
                      font.pixelSize: Theme.fontSizeSmall
                      color: Theme.secondaryColor
                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      visible: albumDescription !== ""
                  }

                  Row {
                      spacing: Theme.paddingMedium

                      Label {
                          text: assetCount === 1
                                //% "1 asset"
                                ? qsTrId("albumDetailPage.asset")
                                //% "%1 assets"
                                : qsTrId("albumDetailPage.assets").arg(assetCount)
                          font.pixelSize: Theme.fontSizeExtraSmall
                          color: Theme.secondaryHighlightColor
                      }

                      Label {
                          text: "·"
                          font.pixelSize: Theme.fontSizeExtraSmall
                          color: Theme.secondaryHighlightColor
                          visible: dateRange !== ""
                      }

                      Label {
                          text: dateRange
                          font.pixelSize: Theme.fontSizeExtraSmall
                          color: Theme.secondaryHighlightColor
                          visible: dateRange !== ""
                      }
                  }
              }
          }

          // Loading indicator
          Item {
              width: parent.width
              height: page.loading ? Theme.itemSizeLarge : 0
              visible: page.loading


              BusyIndicator {
                  anchors.centerIn: parent
                  running: page.loading
                  size: BusyIndicatorSize.Large
              }
          }

          // Grouped assets
          Repeater {
              model: groupedAssets

              Column {
                  width: contentColumn.width
                  spacing: 0

                  property var monthData: modelData

                  // Month+Year header
                  Rectangle {
                      width: parent.width
                      height: Theme.itemSizeSmall
                      color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)


                      Label {
                          anchors.left: parent.left
                          anchors.leftMargin: Theme.horizontalPageMargin
                          anchors.verticalCenter: parent.verticalCenter
                          text: monthData.monthYear
                          font.pixelSize: Theme.fontSizeLarge
                          font.bold: true
                          color: Theme.highlightColor
                      }
                  }

                  // Date sub-groups
                  Repeater {
                      model: monthData.groups

                      Column {
                          width: contentColumn.width
                          spacing: 0

                          property var subGroupData: modelData

                          // Date header with selection button
                          Rectangle {
                              width: parent.width
                              height: Theme.itemSizeExtraSmall
                              color: "transparent"

                              property bool isSubGroupSelected: {
                                  if (!subGroupData || !subGroupData.assets || page.selectedAssets.length === 0) return false
                                  for (var i = 0; i < subGroupData.assets.length; i++) {
                                      if (!page.isAssetSelected(subGroupData.assets[i].id)) {
                                          return false
                                      }
                                  }
                                  return true
                              }

                              Label {
                                  anchors.left: parent.left
                                  anchors.leftMargin: Theme.horizontalPageMargin
                                  anchors.verticalCenter: parent.verticalCenter
                                  text: subGroupData ? subGroupData.displayDate : ""
                                  font.pixelSize: Theme.fontSizeSmall
                                  color: Theme.secondaryHighlightColor
                              }

                              IconButton {
                                  anchors.right: parent.right
                                  anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                                  anchors.verticalCenter: parent.verticalCenter
                                  icon.source: parent.isSubGroupSelected ? "image://theme/icon-m-remove" : "image://theme/icon-m-add"
                                  icon.color: parent.isSubGroupSelected ? Theme.errorColor : Theme.primaryColor

                                  onClicked: {
                                      if (!subGroupData || !subGroupData.assets) return
                                      var assets = subGroupData.assets
                                      if (parent.isSubGroupSelected) {
                                          for (var i = 0; i < assets.length; i++) {
                                              if (page.isAssetSelected(assets[i].id)) {
                                                  page.toggleAssetSelection(assets[i].id)
                                              }
                                          }
                                      } else {
                                          if (!page.selectionMode) page.selectionMode = true
                                          for (var i = 0; i < assets.length; i++) {
                                              if (!page.isAssetSelected(assets[i].id)) {
                                                  page.toggleAssetSelection(assets[i].id)
                                              }
                                          }
                                      }
                                  }
                              }
                          }

                          // Asset grid for this date
                          Flow {
                              width: parent.width

                              Repeater {
                                  model: subGroupData ? subGroupData.assets : null

                                  AssetGridItem {
                                      width: page.cellSize
                                      height: page.cellSize
                                      assetId: modelData.id
                                      isFavorite: modelData.isFavorite
                                      isSelected: page.selectedAssets.length >= 0 && page.isAssetSelected(modelData.id)
                                      isVideo: modelData.isVideo
                                      thumbhash: modelData.thumbhash || ""
                                      duration: modelData.duration || ""

                                      onClicked: {
                                          if (page.selectionMode) {
                                              page.toggleAssetSelection(modelData.id)
                                          } else {
                                              var navAssets = []
                                              for (var i = 0; i < allAssets.length; i++) {
                                                  navAssets.push({
                                                      id: allAssets[i].id,
                                                      isFavorite: allAssets[i].isFavorite,
                                                      isVideo: allAssets[i].isVideo,
                                                      thumbhash: allAssets[i].thumbhash
                                                  })
                                              }
                                              if (modelData.isVideo) {
                                                  pageStack.push(Qt.resolvedUrl("VideoPlayerPage.qml"), {
                                                      videoId: modelData.id,
                                                      isFavorite: modelData.isFavorite,
                                                      currentIndex: modelData.assetIndex,
                                                      albumAssets: navAssets
                                                  })
                                              } else {
                                                  pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                                                      assetId: modelData.id,
                                                      isFavorite: modelData.isFavorite,
                                                      isVideo: modelData.isVideo,
                                                      thumbhash: modelData.thumbhash || "",
                                                      currentIndex: modelData.assetIndex,
                                                      albumAssets: navAssets
                                                  })
                                              }
                                          }
                                      }

                                      onPressAndHold: {
                                          if (!page.selectionMode) page.selectionMode = true
                                          page.toggleAssetSelection(modelData.id)
                                      }

                                      onAddToSelection: {
                                          if (!page.selectionMode) page.selectionMode = true
                                          page.toggleAssetSelection(modelData.id)
                                      }
                                  }
                              }
                          }
                      }
                  }
              }
          }

          // Empty state
          Item {
              width: parent.width
              height: visible ? Theme.itemSizeLarge * 2 : 0
              visible: !page.loading && allAssets.length === 0

              Label {
                  anchors.centerIn: parent
                  //% "No assets in this album"
                  text: qsTrId("albumDetailPage.noAssets")
                  color: Theme.secondaryColor
                  font.pixelSize: Theme.fontSizeMedium
              }
          }
      }

      VerticalScrollDecorator {}
  }

  Component.onCompleted: {
      immichApi.fetchAlbumDetails(albumId)
  }

  Connections {
      target: immichApi
      onAlbumDetailsReceived: {
          if (details.id === albumId) {
              page.processAlbumDetails(details)
          }
      }

      onAlbumUpdated: {
          if (albumId === page.albumId) {
              page.albumName = albumName
              page.albumDescription = description
          }
      }

      onFavoritesToggled: {
          notification.show(isFavorite
               //% "Added to favorites"
               ? qsTrId("albumDetailPage.addedToFavorites")
               //% "Removed from favorites"
               : qsTrId("albumDetailPage.removedFromFavorites"))
      }
  }

  // Selection Action Bar
  SelectionActionBar {
      id: selectionActionBar
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      visible: page.selectionMode
      selectedCount: page.selectedAssets.length
      allAreFavorites: page.allSelectedAreFavorites

      onAddToFavorites: immichApi.toggleFavorite(page.selectedAssets, true)
      onRemoveFromFavorites: immichApi.toggleFavorite(page.selectedAssets, false)
      onShare: {
          pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
              assetIds: page.selectedAssets,
              shareType: "INDIVIDUAL"
          })
      }
      onAddToAlbum: {
          pageStack.push(Qt.resolvedUrl("AlbumPickerPage.qml"), {
              assetIds: page.selectedAssets
          })
      }
      onClearSelection: page.clearSelection()
      onDownload: {
          for (var i = 0; i < page.selectedAssets.length; i++) {
              immichApi.downloadAsset(page.selectedAssets[i], page.selectedAssets[i] + ".jpg")
          }
          page.clearSelection()
          notification.show(page.selectedAssets.length === 1
                //% "Downloading asset..."
                ? qsTrId("albumDetailPage.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("albumDetailPage.downloadingAssets").arg(page.selectedAssets.length))
      }
      onDeleteSelected: {
          immichApi.deleteAssets(page.selectedAssets)
          page.clearSelection()
      }
  }

  ScrollToTopButton {
      targetFlickable: flickable
      actionBarHeight: selectionActionBar.visible ? selectionActionBar.contentHeight : 0
      forceHidden: selectionActionBar.menuOpen
  }

  // Notification banner
  Rectangle {
      id: notification
      anchors.bottom: page.selectionMode ? selectionActionBar.top : parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: opacity > 0 ? notificationLabel.height + Theme.paddingLarge * 2 : 0
      color: Theme.rgba(Theme.highlightBackgroundColor, 0.9)
      visible: opacity > 0
      opacity: 0

      Behavior on opacity {
          NumberAnimation { duration: 300 }
      }

      Label {
          id: notificationLabel
          anchors.centerIn: parent
          width: parent.width - Theme.paddingLarge * 2
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
          color: Theme.primaryColor
      }

      function show(message) {
          notificationLabel.text = message
          opacity = 1
          notificationHideTimer.restart()
      }

      Timer {
          id: notificationHideTimer
          interval: 3000
          onTriggered: notification.opacity = 0
      }

      MouseArea {
          anchors.fill: parent
          onClicked: notification.opacity = 0
      }
  }
}
