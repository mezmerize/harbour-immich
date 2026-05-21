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
               text: qsTrId("pullDownMenu.refresh")
               onClicked: {
                   searchResultsModel.clear()
                   searchBusy.running = true
                   if (smartSearchAssetId !== "") {
                       immichApi.searchSmartByParameters({ "queryAssetId": smartSearchAssetId })
                   } else if (searchParams.isSmartSearch) {
                       immichApi.searchSmartByParameters(searchParams)
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
           duration: model.duration || ""

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

           var items = []
           for (var i = 0; i < results.length; i++) {
               var asset = results[i]
               items.push({
                   assetId: asset.id,
                   isFavorite: asset.isFavorite || false,
                   isVideo: asset.type === "VIDEO",
                   thumbhash: asset.thumbhash || "",
                   duration: asset.duration || "",
                   fileCreatedAt: asset.fileCreatedAt || asset.createdAt || ""
               })
           }
           // Sorting is done after results are received for smart search because there is no server side sorting
           if (searchParams.isSmartSearch && smartSearchAssetId === "") {
               var asc = searchParams.order === "asc"
               items.sort(function(a, b) {
                   if (a.fileCreatedAt < b.fileCreatedAt) return asc ? -1 : 1
                   if (a.fileCreatedAt > b.fileCreatedAt) return asc ? 1 : -1
                   return 0
               })
           }
           for (var j = 0; j < items.length; j++) {
               searchResultsModel.append(items[j])
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
                ? qsTrId("notification.addedToFavorites")
                //% "Removed from favorites"
                : qsTrId("notification.removedFromFavorites"))
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
               immichApi.downloadAsset(page.selectedAssets[i])
           }
           page.clearSelection()
           notification.show(page.selectedAssets.length === 1
                //% "Downloading asset..."
                ? qsTrId("notification.downloadingAsset")
                //% "Downloading %1 assets..."
                : qsTrId("notification.downloadingAssets").arg(page.selectedAssets.length))
       }
       onDeleteSelected: {
           var selectedIds = page.selectedAssets.slice()
           deleteRemorse.execute(selectedIds.length > 1
                //% "Deleting %1 assets
                ? qsTrId("notification.deletingAssets").arg(selectedIds.length)
                //% "Deleting asset
                : qsTrId("notification.deletingAsset"), function() {
                immichApi.deleteAssets(page.selectedAssets)
                page.clearSelection()
           })
       }
   }

   RemorsePopup {
       id: deleteRemorse
   }

   ScrollToTopButton {
       targetFlickable: resultsGrid
       actionBarHeight: selectionActionBar.visible ? selectionActionBar.contentHeight : 0
       forceHidden: selectionActionBar.activeMenuType !== ""
   }

   NotificationBanner {
       id: notification
       anchors.bottom: page.selectionMode ? selectionActionBar.top : parent.bottom
   }

   Component.onCompleted: {
       searchBusy.running = true
       if (smartSearchAssetId !== "") {
           immichApi.searchSmartByParameters({ "queryAssetId": smartSearchAssetId })
       } else {
           if (personIds.length > 0) {
               var params = searchParams || {}
               params.personIds = personIds
               searchParams = params
           }
           if (searchParams.isSmartSearch) {
               immichApi.searchSmartByParameters(searchParams)
           } else {
               immichApi.searchByParameters(searchParams)
           }
       }
   }
}
