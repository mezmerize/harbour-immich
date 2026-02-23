import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
   id: page

   property string memoryTitle: ""
   property var assets: []
   property int currentIndex: 0
   property bool slideshowRunning: false

   Timer {
       id: slideshowTimer
       interval: 3000
       repeat: true
       running: slideshowRunning && page.status === PageStatus.Active
       onTriggered: {
           if (assets && assets.length > 1) {
               currentIndex = (currentIndex + 1) % assets.length
           }
       }
   }

   SilicaFlickable {
       anchors.fill: parent
       contentHeight: column.height

       PullDownMenu {
           MenuItem {
               //% "Show in timeline"
               text: qsTrId("memoryDetailPage.showInTimeline")
               enabled: assets && assets.length > 0 && assets[currentIndex]
               onClicked: {
                   var asset = assets[currentIndex]
                   if (asset && asset.id) {
                       var assetDate = asset.localDateTime || asset.fileCreatedAt || ""
                       pageStack.pop(pageStack.find(function(p) {
                           return p.objectName === "timelinePage"
                       }))
                       timelineModel.scrollToAsset(asset.id, assetDate)
                   }
               }
           }

           MenuItem {
               //% "Show similar assets"
               text: qsTrId("memoryDetailPage.showSimilar")
               enabled: assets && assets.length > 0 && assets[currentIndex]
               onClicked: {
                   var asset = assets[currentIndex]
                   if (asset && asset.id) {
                       pageStack.push(Qt.resolvedUrl("SearchResultsPage.qml"), {
                            smartSearchAssetId: asset.id
                       })
                   }
               }
           }

           MenuItem {
               text: slideshowRunning
                     //% "Stop Slideshow"
                     ? qsTrId("memoryDetailPage.stopSlideshow")
                     //% "Start Slideshow"
                     : qsTrId("memoryDetailPage.startSlideshow")
               visible: assets && assets.length > 1
               onClicked: slideshowRunning = !slideshowRunning
           }
       }

       Column {
           id: column
           width: parent.width
           spacing: Theme.paddingMedium

           PageHeader {
               title: memoryTitle
           }

           // Main slideshow view
           Item {
               width: parent.width
               height: page.height - Theme.itemSizeLarge * 3

               Image {
                   id: mainThumbhash
                   anchors.fill: parent
                   anchors.margins: Theme.paddingSmall
                   fillMode: Image.PreserveAspectFit
                   source: (assets && assets.length > 0 && assets[currentIndex] && assets[currentIndex].thumbhash) ? "image://thumbhash/" + assets[currentIndex].thumbhash : ""
                   visible: mainImage.status !== Image.Ready
                   asynchronous: false
                   smooth: true
                   cache: true
               }

               Image {
                   id: mainImage
                   anchors.fill: parent
                   anchors.margins: Theme.paddingSmall
                   source: (assets && assets.length > 0 && assets[currentIndex]) ?
                           "image://immich/original/" + assets[currentIndex].id : ""
                   fillMode: Image.PreserveAspectFit
                   asynchronous: true
                   sourceSize.width: page.width
                   sourceSize.height: page.height

                   BusyIndicator {
                       anchors.centerIn: parent
                       running: mainImage.status === Image.Loading && !mainThumbhash.source.toString()
                       size: BusyIndicatorSize.Medium
                   }

                   // Tap to open full view
                   MouseArea {
                       anchors.fill: parent
                       onClicked: {
                           if (!assets || assets.length === 0) return
                           var asset = assets[currentIndex]
                           if (!asset) return
                           var isVideo = asset.type === "VIDEO"
                           if (isVideo) {
                               pageStack.push(Qt.resolvedUrl("VideoPlayerPage.qml"), {
                                   videoId: asset.id,
                                   isFavorite: asset.isFavorite || false
                               })
                           } else {
                               pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                                   assetId: asset.id,
                                   isFavorite: asset.isFavorite || false,
                                   isVideo: false
                               })
                           }
                       }
                   }
               }

               // Navigation arrows
               IconButton {
                   anchors.left: parent.left
                   anchors.verticalCenter: parent.verticalCenter
                   icon.source: "image://theme/icon-m-left"
                   visible: assets && assets.length > 1
                   onClicked: {
                       slideshowRunning = false
                       currentIndex = (currentIndex - 1 + assets.length) % assets.length
                   }
               }

               IconButton {
                   anchors.right: parent.right
                   anchors.verticalCenter: parent.verticalCenter
                   icon.source: "image://theme/icon-m-right"
                   visible: assets && assets.length > 1
                   onClicked: {
                       slideshowRunning = false
                       currentIndex = (currentIndex + 1) % assets.length
                   }
               }
           }

           // Asset counter
           Label {
               anchors.horizontalCenter: parent.horizontalCenter
               text: assets && assets.length > 0 ?
                     //% "%1 / %2"
                     qsTrId("memoryDetailPage.assetCounter").arg(currentIndex + 1).arg(assets.length) : ""
               color: Theme.secondaryColor
               font.pixelSize: Theme.fontSizeSmall
           }

           // Thumbnail strip
           SilicaListView {
               id: thumbnailStrip
               width: parent.width
               height: Theme.itemSizeMedium
               orientation: ListView.Horizontal
               clip: true
               spacing: Theme.paddingSmall
               leftMargin: Theme.horizontalPageMargin
               rightMargin: Theme.horizontalPageMargin

               model: assets ? assets.length : 0

               delegate: BackgroundItem {
                   width: Theme.itemSizeMedium
                   height: Theme.itemSizeMedium
                   highlighted: index === currentIndex

                   Image {
                       id: stripThumbhash
                       anchors.fill: parent
                       anchors.margins: 2
                       fillMode: Image.PreserveAspectCrop
                       source: (assets && assets[index] && assets[index].thumbhash) ? "image://thumbhash/" + assets[index].thumbhash : ""
                       visible: stripThumbnail.status !== Image.Ready
                       asynchronous: false
                       smooth: true
                       cache: true
                   }

                   Image {
                       id: stripThumbnail
                       anchors.fill: parent
                       anchors.margins: 2
                       source: (assets && assets[index]) ? "image://immich/thumbnail/" + assets[index].id : ""
                       fillMode: Image.PreserveAspectCrop
                       asynchronous: true
                       sourceSize.width: 128
                       sourceSize.height: 128

                       Rectangle {
                           anchors.fill: parent
                           color: "transparent"
                           border.width: index === currentIndex ? 3 : 0
                           border.color: Theme.highlightColor
                       }
                   }

                   onClicked: {
                       slideshowRunning = false
                       currentIndex = index
                   }
               }

               HorizontalScrollDecorator {}
           }

           Item {
               width: parent.width
               height: Theme.paddingLarge
           }
       }

       VerticalScrollDecorator {}
   }
}
