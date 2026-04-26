import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.6
import QtFeedback 5.0
import "../components"

Page {
   id: page

   ThemeEffect {
       id: hapticFeedback
       effect: ThemeEffect.Press
   }

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
               text: qsTrId("pullDownMenu.information")
               onClicked: {
                   pageStack.push(Qt.resolvedUrl("AssetInfoPage.qml"), {
                       assetId: videoId,
                       assetInfo: page.assetInfo
                   })
               }
           }

           MenuItem {
               //% "Show in timeline"
               text: qsTrId("pullDownMenu.showInTimeline")
               onClicked: {
                   pageStack.pop(pageStack.find(function(p) {
                       return p.objectName === "timelinePage"
                   }))
                   timelineModel.scrollToAsset(videoId, "")
               }
           }

           MenuItem {
               //% "Share"
               text: qsTrId("pullDownMenu.share")
               onClicked: {
                   pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
                       shareType: "INDIVIDUAL",
                       assetIds: [videoId]
                   })
               }
           }

           MenuItem {
               //% "Download"
               text: qsTrId("pullDownMenu.download")
               onClicked: {
                   hapticFeedback.play()
                   immichApi.downloadAsset(videoId)
                   //% "Downloading..."
                   notification.show(qsTrId("notification.downloading"))
               }
           }

           MenuItem {
               text: isFavorite
                     //% "Remove from favorites"
                     ? qsTrId("pullDownMenu.removeFromFavorites")
                       //% "Add to favorites"
                     : qsTrId("pullDownMenu.addToFavorites")
               onClicked: {
                   hapticFeedback.play()
                   immichApi.toggleFavorite([videoId], !isFavorite)
               }
           }
       }
   }

   property bool controlsVisible: true

   function toggleControls() {
       if (controlsVisible) {
           controlsVisible = false
           controlsHideTimer.stop()
       } else {
           controlsVisible = true
           if (videoPlayer.playbackState === MediaPlayer.PlayingState) {
               controlsHideTimer.restart()
           }
       }
   }

   function togglePlayback() {
       if (videoPlayer.playbackState === MediaPlayer.PlayingState) {
           videoPlayer.pause()
           controlsVisible = true
           controlsHideTimer.stop()
       } else {
           videoPlayer.play()
           controlsHideTimer.restart()
       }
   }

   Timer {
       id: controlsHideTimer
       interval: 4000
       onTriggered: {
           if (videoPlayer.playbackState === MediaPlayer.PlayingState) {
               controlsVisible = false
           }
       }
   }

   // Video player
   Rectangle {
       anchors.fill: parent
       color: "black"
       z: -1

       Video {
           id: videoPlayer
           anchors.fill: parent
           autoPlay: false
       }

       // Tap area for toggling controls
       MouseArea {
           anchors.fill: parent
           onClicked: toggleControls()
       }

       // Play/Pause center overlay
       Rectangle {
           anchors.centerIn: parent
           width: Theme.itemSizeExtraLarge
           height: Theme.itemSizeExtraLarge
           radius: width / 2
           color: Theme.rgba("black", 0.4)
           visible: controlsVisible
           opacity: controlsVisible ? 1.0 : 0.0
           Behavior on opacity { FadeAnimation { duration: 200 } }

           Image {
               anchors.centerIn: parent
               source: videoPlayer.playbackState === MediaPlayer.PlayingState ? "image://theme/icon-l-pause" : "image://theme/icon-l-play"
           }

           MouseArea {
               anchors.fill: parent
               onClicked: togglePlayback()
           }
       }

       // Controls bar at bottom
       Rectangle {
           id: controlsBar
           anchors.bottom: parent.bottom
           anchors.left: parent.left
           anchors.right: parent.right
           height: controlsContent.height + Theme.paddingMedium * 2
           color: Theme.rgba("black", 0.6)
           visible: controlsVisible
           opacity: controlsVisible ? 1.0 : 0.0
           Behavior on opacity { FadeAnimation { duration: 200 } }

           // Gradient top edge
           Rectangle {
               anchors.bottom: parent.top
               anchors.left: parent.left
               anchors.right: parent.right
               height: Theme.paddingLarge * 2
               gradient: Gradient {
                   GradientStop { position: 0.0; color: "transparent" }
                   GradientStop { position: 1.0; color: Theme.rgba("black", 0.6) }
               }
           }

           Column {
               id: controlsContent
               anchors.left: parent.left
               anchors.right: parent.right
               anchors.bottom: parent.bottom
               anchors.bottomMargin: Theme.paddingMedium
               spacing: Theme.paddingSmall

               // Time row: [position] [slider] [duration]
               Row {
                   anchors.left: parent.left
                   anchors.right: parent.right
                   anchors.leftMargin: Theme.horizontalPageMargin
                   anchors.rightMargin: Theme.horizontalPageMargin
                   spacing: Theme.paddingSmall

                   Label {
                       id: positionLabel
                       width: Math.max(implicitWidth, Theme.itemSizeSmall)
                       anchors.verticalCenter: parent.verticalCenter
                       text: formatTime(videoPlayer.position)
                       font.pixelSize: Theme.fontSizeExtraSmall
                       color: Theme.primaryColor
                       horizontalAlignment: Text.AlignRight
                   }

                   Slider {
                       id: progressSlider
                       width: parent.width - positionLabel.width - durationLabel.width - Theme.paddingSmall * 2
                       anchors.verticalCenter: parent.verticalCenter
                       minimumValue: 0
                       maximumValue: Math.max(1, videoPlayer.duration)
                       value: videoPlayer.position
                       enabled: videoPlayer.seekable
                       handleVisible: true

                       property bool userDragging: false

                       onPressed: {
                           userDragging = true
                           controlsHideTimer.stop()
                       }

                       onReleased: {
                           userDragging = false
                           videoPlayer.seek(value)
                           if (videoPlayer.playbackState === MediaPlayer.PlayingState) {
                               controlsHideTimer.restart()
                           }
                       }
                   }

                   Label {
                       id: durationLabel
                       width: Math.max(implicitWidth, Theme.itemSizeSmall)
                       anchors.verticalCenter: parent.verticalCenter
                       text: formatTime(videoPlayer.duration)
                       font.pixelSize: Theme.fontSizeExtraSmall
                       color: Theme.secondaryColor
                   }
               }

               // Playback controls row
               Row {
                   anchors.horizontalCenter: parent.horizontalCenter
                   spacing: Theme.paddingLarge * 2

                   IconButton {
                       icon.source: "image://theme/icon-m-10s-back"
                       onClicked: {
                           videoPlayer.seek(Math.max(0, videoPlayer.position - 10000))
                           controlsHideTimer.restart()
                       }
                   }

                   IconButton {
                       icon.source: videoPlayer.playbackState === MediaPlayer.PlayingState ? "image://theme/icon-m-pause" : "image://theme/icon-m-play"
                       onClicked: togglePlayback()
                   }

                   IconButton {
                       icon.source: "image://theme/icon-m-10s-forward"
                       onClicked: {
                           videoPlayer.seek(Math.min(videoPlayer.duration, videoPlayer.position + 10000))
                           controlsHideTimer.restart()
                       }
                   }
               }
           }
       }

       // Loading indicator
       BusyIndicator {
           anchors.centerIn: parent
           running: videoPlayer.status === MediaPlayer.Loading || videoPlayer.status === MediaPlayer.Buffering
           size: BusyIndicatorSize.Large
       }

       // Error state
       Column {
           anchors.centerIn: parent
           spacing: Theme.paddingMedium
           visible: videoPlayer.status === MediaPlayer.InvalidMedia || videoPlayer.status === MediaPlayer.UnknownStatus

           Icon {
               anchors.horizontalCenter: parent.horizontalCenter
               source: "image://theme/icon-m-video"
               width: Theme.iconSizeLarge
               height: Theme.iconSizeLarge
               opacity: 0.5
           }

           Label {
               anchors.horizontalCenter: parent.horizontalCenter
               //% "Failed to load video"
               text: qsTrId("videoPlayerPage.failed")
               color: Theme.highlightColor
               font.pixelSize: Theme.fontSizeMedium
           }
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
               if (info.isFavorite !== undefined) {
                   page.isFavorite = info.isFavorite
               }
           }
       }
       onFavoritesToggled: {
           if (assetIds.indexOf(videoId) > -1) {
               page.isFavorite = isFavorite
           }
       }
       onAssetDownloaded: {
           if (assetId === page.videoId) {
               //% "Downloaded to: %1"
               notification.show(qsTrId("notification.downloaded").arg(filePath))
           }
       }
   }

   Component.onCompleted: {
       immichApi.getAssetInfo(videoId)
       immichApi.setVideoSource(videoPlayer, videoId)
       videoPlayer.play()
       controlsHideTimer.start()
   }

   NotificationBanner {
       id: notification
       anchors.bottom: parent.bottom
       z: 10
   }
}
