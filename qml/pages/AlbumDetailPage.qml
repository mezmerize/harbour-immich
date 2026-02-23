import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
   id: page

   property string albumId
   property string albumName
   property int assetCount
   property bool selectionMode: false
   property var selectedAssets: []
   property bool allSelectedAreFavorites: false

   function updateAllSelectedAreFavorites() {
       if (selectedAssets.length === 0) {
           allSelectedAreFavorites = false
           return
       }
       for (var i = 0; i < albumDetailModel.count; i++) {
           var item = albumDetailModel.get(i)
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
       selectedAssets = selectedAssets // trigger property change
       if (selectedAssets.length === 0) {
           selectionMode = false
       }
       updateAllSelectedAreFavorites()
   }

   function clearSelection() {
       selectedAssets = []
       selectionMode = false
   }

   SilicaGridView {
       id: gridView
       anchors.top: parent.top
       anchors.left: parent.left
       anchors.right: parent.right
       anchors.bottom: selectionActionBar.visible ? selectionActionBar.top : parent.bottom

       PullDownMenu {
           enabled: !page.selectionMode

           MenuItem {
               //% "Refresh"
               text: qsTrId("albumDetailPage.refresh")
               visible: !page.selectionMode
               onClicked: {
                   albumDetailModel.setLoading(true)
                   immichApi.fetchAlbumDetails(albumId)
               }
           }

           MenuItem {
               //% "Information"
               text: qsTrId("albumDetailPage.information")
               visible: !page.selectionMode
               onClicked: {
                   pageStack.push(Qt.resolvedUrl("AlbumInfoPage.qml"), {
                       albumId: albumId
                   })
               }
           }

           MenuItem {
               //% "Share album"
               text: qsTrId("albumDetailPage.share")
               visible: !page.selectionMode
               onClicked: {
                   pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                       albumId: albumId,
                       shareType: "ALBUM"
                   })
               }
           }
       }

       header: PageHeader {
           //% "%1 asset(s) selected"
           title: page.selectionMode ? qsTrId("albumDetailPage.assetsSelected").arg(page.selectedAssets.length) : albumName
           //% "%1 asset(s)"
           description: page.selectionMode ? "" : qsTrId("albumDetailPage.assets").arg(assetCount)
       }

       property int assetsPerRow: page.isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)

       cellWidth: width / assetsPerRow
       cellHeight: cellWidth

       model: ListModel {
           id: albumDetailModel

           property bool loading: false

           function setLoading(value) {
               loading = value
           }
       }

       delegate: AssetGridItem {
           id: albumGridItem
           width: gridView.cellWidth
           height: gridView.cellHeight
           assetId: model.assetId
           isFavorite: model.isFavorite
           isSelected: page.selectedAssets.indexOf(model.assetId) > -1
           isVideo: model.isVideo
           thumbhash: model.thumbhash || ""

           onClicked: {
               if (page.selectionMode) {
                   page.toggleAssetSelection(model.assetId)
               } else {
                   // Build array of album assets for navigation
                   var assets = []
                   for (var i = 0; i < albumDetailModel.count; i++) {
                       var item = albumDetailModel.get(i)
                       assets.push({
                           id: item.assetId,
                           isFavorite: item.isFavorite,
                           isVideo: item.isVideo,
                           thumbhash: item.thumbhash || ""
                       })
                   }

                   if (model.isVideo) {
                       pageStack.push(Qt.resolvedUrl("VideoPlayerPage.qml"), {
                           videoId: model.assetId,
                           isFavorite: model.isFavorite,
                           currentIndex: index,
                           albumAssets: assets
                       })
                   } else {
                       pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                           assetId: model.assetId,
                           isFavorite: model.isFavorite,
                           isVideo: model.isVideo,
                           thumbhash: model.thumbhash || "",
                           currentIndex: index,
                           albumAssets: assets
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

       footer: Item {
           width: gridView.width
           height: albumDetailModel.loading ? Theme.itemSizeLarge : 0
           visible: albumDetailModel.loading

           BusyIndicator {
               anchors.centerIn: parent
               running: albumDetailModel.loading
               size: BusyIndicatorSize.Large
           }
       }

       ViewPlaceholder {
           enabled: gridView.count === 0 && !albumDetailModel.loading
           //% "No assets in this album"
           text: qsTrId("albumDetailPage.noAssets")
       }

       VerticalScrollDecorator {}
   }

   Component.onCompleted: {
       albumDetailModel.setLoading(true)
       immichApi.fetchAlbumDetails(albumId)
   }

   Connections {
       target: immichApi
       onAlbumDetailsReceived: {
           if (details.id === albumId) {
               albumDetailModel.clear()
               var assets = details.assets
               for (var i = 0; i < assets.length; i++) {
                   var asset = assets[i]
                   albumDetailModel.append({
                       assetId: asset.id,
                       isFavorite: asset.isFavorite || false,
                       isVideo: asset.type === "VIDEO",
                       thumbhash: asset.thumbhash || ""
                   })
               }
               albumDetailModel.setLoading(false)
           }
       }

       onFavoritesToggled: {
           // Update model items
           for (var i = 0; i < albumDetailModel.count; i++) {
               var item = albumDetailModel.get(i)
               if (assetIds.indexOf(item.assetId) > -1) {
                   albumDetailModel.setProperty(i, "isFavorite", isFavorite)
               }
           }
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
           //% "Downloading %1 asset(s)..."
           notification.show(qsTrId("albumDetailPage.downloading").arg(page.selectedAssets.length))
       }
       onDeleteSelected: {
           immichApi.deleteAssets(page.selectedAssets)
           page.clearSelection()
       }
   }

   ScrollToTopButton {
       targetFlickable: gridView
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
