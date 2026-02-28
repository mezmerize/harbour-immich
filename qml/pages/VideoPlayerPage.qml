import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.6

Page {
   id: page

   property string videoId
   property bool isFavorite: false
   property int currentIndex: -1
   property var albumAssets: null
   property var assetInfo: null

   allowedOrientations: Orientation.All

   // Transparent flickable for PullDownMenu only
   SilicaFlickable {
       anchors.fill: parent
       contentHeight: parent.height

       PullDownMenu {
           MenuItem {
               //% "Information"
               text: qsTrId("videoPlayerPage.information")
               onClicked: {
                   pageStack.push(Qt.resolvedUrl("AssetInfoPage.qml"), {
                       assetId: videoId,
                       assetInfo: page.assetInfo
                   })
               }
           }

           MenuItem {
               //% "Show in timeline"
               text: qsTrId("videoPlayerPage.showInTimeline")
               onClicked: {
                   pageStack.pop(pageStack.find(function(p) {
                       return p.objectName === "timelinePage"
                   }))
                   timelineModel.scrollToAsset(videoId, "")
               }
           }

           MenuItem {
               text: isFavorite
                     //% "Remove from favorites"
                     ? qsTrId("videoPlayerPage.removeFromFavorites")
                       //% "Add to favorites"
                     : qsTrId("videoPlayerPage.addToFavorites")
               onClicked: {
                   immichApi.toggleFavorite([videoId], !isFavorite)
                   isFavorite = !isFavorite
               }
           }
       }
   }

   // Video player and controls - outside flickable for proper positioning
   Rectangle {
       anchors.fill: parent
       color: "black"
       z: -1

       Video {
           id: videoPlayer
           anchors.fill: parent
           source: videoId ? "image://immich/original/" + videoId : ""
           autoPlay: false

           MouseArea {
               anchors.fill: parent
               onClicked: {
                   if (videoPlayer.playbackState === MediaPlayer.PlayingState) {
                       videoPlayer.pause()
                   } else {
                       videoPlayer.play()
                   }
               }
           }
       }

       // Play/Pause overlay
       Rectangle {
           anchors.centerIn: parent
           width: Theme.itemSizeHuge
           height: Theme.itemSizeHuge
           radius: width / 2
           color: Theme.rgba(Theme.highlightBackgroundColor, 0.5)
           visible: videoPlayer.playbackState !== MediaPlayer.PlayingState || !controlsHideTimer.running

           Image {
               anchors.centerIn: parent
               source: videoPlayer.playbackState === MediaPlayer.PlayingState ? "image://theme/icon-m-pause" : "image://theme/icon-m-play"
           }

           MouseArea {
               anchors.fill: parent
               onClicked: {
                   if (videoPlayer.playbackState === MediaPlayer.PlayingState) {
                       videoPlayer.pause()
                   } else {
                       videoPlayer.play()
                       controlsHideTimer.restart()
                   }
               }
           }
       }

       // Controls bar at bottom
       Rectangle {
           id: controlsBar
           anchors.bottom: parent.bottom
           width: parent.width
           height: controlsColumn.height + Theme.paddingLarge * 2
           color: Theme.rgba(Theme.highlightDimmerColor, 0.8)
           visible: videoPlayer.playbackState !== MediaPlayer.PlayingState || !controlsHideTimer.running

           Column {
               id: controlsColumn
               anchors.left: parent.left
               anchors.right: parent.right
               anchors.bottom: parent.bottom
               anchors.margins: Theme.paddingLarge
               spacing: Theme.paddingSmall

               Slider {
                   id: progressSlider
                   width: parent.width
                   minimumValue: 0
                   maximumValue: Math.max(1, videoPlayer.duration)
                   value: videoPlayer.position
                   enabled: videoPlayer.seekable
                   handleVisible: false

                   onReleased: {
                       videoPlayer.seek(value)
                   }

                   Label {
                       anchors.left: parent.left
                       anchors.bottom: parent.top
                       anchors.bottomMargin: Theme.paddingSmall
                       text: formatTime(videoPlayer.position)
                       font.pixelSize: Theme.fontSizeSmall
                       color: Theme.primaryColor
                   }

                   Label {
                       anchors.right: parent.right
                       anchors.bottom: parent.top
                       anchors.bottomMargin: Theme.paddingSmall
                       text: formatTime(videoPlayer.duration)
                       font.pixelSize: Theme.fontSizeSmall
                       color: Theme.primaryColor
                   }
               }

               Row {
                   anchors.horizontalCenter: parent.horizontalCenter
                   spacing: Theme.paddingLarge

                   IconButton {
                       icon.source: "image://theme/icon-m-10s-back"
                       onClicked: {
                           videoPlayer.seek(Math.max(0, videoPlayer.position - 10000))
                       }
                   }

                   IconButton {
                       icon.source: videoPlayer.playbackState === MediaPlayer.PlayingState ? "image://theme/icon-m-pause" : "image://theme/icon-m-play"
                       onClicked: {
                           if (videoPlayer.playbackState === MediaPlayer.PlayingState) {
                               videoPlayer.pause()
                           } else {
                               videoPlayer.play()
                               controlsHideTimer.restart()
                           }
                       }
                   }

                   IconButton {
                       icon.source: "image://theme/icon-m-10s-forward"
                       onClicked: {
                           videoPlayer.seek(Math.min(videoPlayer.duration, videoPlayer.position + 10000))
                       }
                   }
               }
           }
       }

       Timer {
           id: controlsHideTimer
           interval: 3000
           running: false
       }

       BusyIndicator {
           anchors.centerIn: parent
           running: videoPlayer.status === MediaPlayer.Loading || videoPlayer.status === MediaPlayer.Buffering
           size: BusyIndicatorSize.Large
       }

       Label {
           anchors.centerIn: parent
           visible: videoPlayer.status === MediaPlayer.InvalidMedia || videoPlayer.status === MediaPlayer.UnknownStatus
           //% "Failed to load video"
           text: qsTrId("videoPlayerPage.failed")
           color: Theme.highlightColor
           font.pixelSize: Theme.fontSizeLarge
       }
   }

   function formatTime(milliseconds) {
       var seconds = Math.floor(milliseconds / 1000)
       var minutes = Math.floor(seconds / 60)
       var hours = Math.floor(minutes / 60)

       seconds = seconds % 60
       minutes = minutes % 60

       if (hours > 0) {
           return hours + ":" + pad(minutes) + ":" + pad(seconds)
       } else {
           return minutes + ":" + pad(seconds)
       }
   }

   function pad(num) {
       return (num < 10 ? "0" : "") + num
   }

   Connections {
       target: immichApi
       onAssetInfoReceived: {
           if (info.id === videoId) {
               page.assetInfo = info
           }
       }
   }

   Component.onCompleted: {
       immichApi.getAssetInfo(videoId)
       videoPlayer.play()
       controlsHideTimer.start()
   }
}
