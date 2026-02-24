import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
   id: page

   property var searchParams: ({})
   property string smartSearchAssetId: ""
   property var personIds: []
   property string searchTitle: ""
   property var searchAssets: []
   property bool selectionMode: false
   property var selectedAssets: []
   property bool allSelectedAreFavorites: false

   function updateAllSelectedAreFavorites() {
       if (selectedAssets.length === 0) {
           allSelectedAreFavorites = false
           return
       }
       for (var i = 0; i < searchResultsModel.count; i++) {
           var item = searchResultsModel.get(i)
           if (selectedAssets.indexOf(item.assetId) > -1 && !item.isFavorite) {
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

   function buildAssetsArray() {
       var assets = []
       for (var i = 0; i < searchResultsModel.count; i++) {
           var item = searchResultsModel.get(i)
           assets.push({
               id: item.assetId,
               isFavorite: item.isFavorite,
               isVideo: item.isVideo,
               thumbhash: item.thumbhash || ""
           })
       }
       searchAssets = assets
   }

   SilicaGridView {
       id: resultsGrid
       anchors.top: parent.top
       anchors.left: parent.left
       anchors.right: parent.right
       anchors.bottom: selectionActionBar.visible ? selectionActionBar.top : parent.bottom

       property int assetsPerRow: page.isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)

       cellWidth: width / assetsPerRow
       cellHeight: cellWidth

       PullDownMenu {
           MenuItem {
               //% "Refresh"
               text: qsTrId("searchResultsPage.refresh")
               onClicked: {
                   searchResultsModel.clear()
                   searchBusy.running = true
                   if (smartSearchAssetId !== "") {
                       immichApi.smartSearch(smartSearchAssetId)
                   } else {
                       immichApi.searchByParameters(searchParams)
                   }
               }
           }
       }

       header: PageHeader {
           //% "Search Results"
           title: searchTitle !== "" ? searchTitle : qsTrId("searchResultsPage.searchResults")
           description: resultsGrid.count === 1
                //% "1 result"
                ? qsTrId("searchResultsPage.result")
                //% "%1 results"
                : qsTrId("searchResultsPage.results").arg(resultsGrid.count)
       }

       model: ListModel {
           id: searchResultsModel
       }

       delegate: AssetGridItem {
           id: searchGridItem
           width: resultsGrid.cellWidth
           height: resultsGrid.cellHeight
           assetId: model.assetId
           isFavorite: model.isFavorite
           isSelected: page.selectedAssets.indexOf(model.assetId) > -1
           isVideo: model.isVideo
           thumbhash: model.thumbhash || ""

           onClicked: {
               if (page.selectionMode) {
                   page.toggleAssetSelection(model.assetId)
               } else {
                   buildAssetsArray()
                   if (isVideo) {
                       pageStack.push(Qt.resolvedUrl("VideoPlayerPage.qml"), {
                           videoId: assetId,
                           isFavorite: isFavorite,
                           currentIndex: index,
                           albumAssets: searchAssets
                       })
                   } else {
                       pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                           assetId: assetId,
                           isFavorite: isFavorite,
                           isVideo: isVideo,
                           thumbhash: model.thumbhash || "",
                           currentIndex: index,
                           albumAssets: searchAssets
                       })
                   }
               }
           }

           onPressAndHold: {
               if (!page.selectionMode) {
                   page.selectionMode = true
                   page.toggleAssetSelection(model.assetId)
               }
           }

           onAddToSelection: {
               if (!page.selectionMode) {
                   page.selectionMode = true
                   page.toggleAssetSelection(model.assetId)
               }
           }
       }

       ViewPlaceholder {
           enabled: resultsGrid.count === 0 && !searchBusy.running
           //% "No results found"
           text: qsTrId("searchResultsPage.noResults")
           //% "Try adjusting your search filters"
           hintText: qsTrId("searchResultsPage.noResultsHint")
       }

       VerticalScrollDecorator {}
   }

   BusyIndicator {
       id: searchBusy
       anchors.centerIn: parent
       running: false
       size: BusyIndicatorSize.Large
   }

   Connections {
       target: immichApi

       onSearchResultsReceived: {
           searchBusy.running = false
           searchResultsModel.clear()

           for (var i = 0; i < results.length; i++) {
               var asset = results[i]
               searchResultsModel.append({
                   assetId: asset.id,
                   isFavorite: asset.isFavorite || false,
                   isVideo: asset.type === "VIDEO",
                   thumbhash: asset.thumbhash || ""
               })
           }
       }

       onFavoritesToggled: {
           // Update model items
           for (var i = 0; i < searchResultsModel.count; i++) {
               var item = searchResultsModel.get(i)
               if (assetIds.indexOf(item.assetId) > -1) {
                   searchResultsModel.setProperty(i, "isFavorite", isFavorite)
               }
           }
           notification.show(isFavorite
                //% "Added to favorites"
                ? qsTrId("searchResultsPage.addedToFavorites")
                //% "Removed from favorites"
                : qsTrId("searchResultsPage.removedFromFavorites"))
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
                ? qsTrId("searchResultsPage.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("searchResultsPage.downloadingAssets").arg(page.selectedAssets.length))
       }
       onDeleteSelected: {
           immichApi.deleteAssets(page.selectedAssets)
           page.clearSelection()
       }
   }

   ScrollToTopButton {
       targetFlickable: resultsGrid
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

   Component.onCompleted: {
       searchBusy.running = true
       if (smartSearchAssetId !== "") {
           immichApi.smartSearch(smartSearchAssetId)
       } else {
           if (personIds.length > 0) {
               var params = searchParams || {}
               params.personIds = personIds
               searchParams = params
           }
           immichApi.searchByParameters(searchParams)
       }
   }
}
