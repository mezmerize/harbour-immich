import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
   id: settingsPage

   property var serverStats: null
   property var serverAbout: null

   Component.onCompleted: {
       immichApi.fetchServerStatistics()
       immichApi.fetchServerAbout()
   }

   Connections {
       target: immichApi
       onServerStatisticsReceived: {
           settingsPage.serverStats = stats
       }
       onServerAboutReceived: {
           settingsPage.serverAbout = about
       }
   }

   function formatBytes(bytes) {
       if (bytes === 0) return "0 B"
       var k = 1024
       var sizes = ['B', 'KB', 'MB', 'GB', 'TB']
       var i = Math.floor(Math.log(bytes) / Math.log(k))
       return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
   }

   SilicaFlickable {
       anchors.fill: parent
       contentHeight: column.height

       PullDownMenu {
           MenuItem {
               //% "Search"
               text: qsTrId("settingsPage.search")
               onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
           }

           MenuItem {
               //% "Albums"
               text: qsTrId("settingsPage.albums")
               onClicked: pageStack.push(Qt.resolvedUrl("AlbumsPage.qml"))
           }

           MenuItem {
               //% "Timeline"
               text: qsTrId("settingsPage.timeline")
               onClicked: pageStack.replaceAbove(null, Qt.resolvedUrl("TimelinePage.qml"))
           }
       }

       Column {
           id: column
           width: settingsPage.width
           spacing: Theme.paddingMedium

           PageHeader {
               //% "Settings"
               title: qsTrId("settingsPage.settings")
           }

           SectionHeader {
               //% "Display"
               text: qsTrId("settingsPage.display")
           }

           Slider {
               width: parent.width
               //% "Assets per row (portrait)"
               label: qsTrId("settingsPage.assetsPerRow")
               minimumValue: 2
               maximumValue: 6
               stepSize: 1
               value: settingsManager.assetsPerRow
               valueText: value
               onValueChanged: {
                   if (value !== settingsManager.assetsPerRow) {
                       settingsManager.assetsPerRow = value
                   }
               }
           }

           ComboBox {
               //% "Detail viewer quality"
               label: qsTrId("settingsPage.detailQuality")
               //% "Controls image quality when viewing photos in full screen. Preview is faster and uses less data, Original shows the full resolution image."
               description: qsTrId("settingsPage.detailQualityInfo")
               currentIndex: settingsManager.detailQuality === "original" ? 1 : 0
               menu: ContextMenu {
                   //% "Preview (faster, less data)"
                   MenuItem { text: qsTrId("settingsPage.detailQualityPreview") }
                   //% "Original (full resolution)"
                   MenuItem { text: qsTrId("settingsPage.detailQualityOriginal") }
               }
               onCurrentIndexChanged: {
                   var quality = currentIndex === 1 ? "original" : "preview"
                   if (quality !== settingsManager.detailQuality) {
                       settingsManager.detailQuality = quality
                   }
               }
           }

           TextSwitch {
               //% "Show memories bar"
               text: qsTrId("settingsPage.showMemoriesBar")
               //% "Display memories at the top of the timeline."
               description: qsTrId("settingsPage.showMemoriesBarInfo")
               checked: settingsManager.showMemoriesBar
               onCheckedChanged: {
                   settingsManager.showMemoriesBar = checked
               }
           }

           ComboBox {
               //% "Memories thumbnail size"
               label: qsTrId("settingsPage.memoriesThumbnailSize")
               //% "Controls appearance size of the memory thumbnails on Timeline page."
               description: qsTrId("settingsPage.memoriesThumbnailSizeInfo")
               currentIndex: settingsManager.memoriesThumbnailSize
               enabled: settingsManager.showMemoriesBar
               menu: ContextMenu {
                   //% "Small"
                   MenuItem { text: qsTrId("settingsPage.memoriesThumbnailSizeSmall") }
                   //% "Medium"
                   MenuItem { text: qsTrId("settingsPage.memoriesThumbnailSizeMedium") }
                   //% "Large"
                   MenuItem { text: qsTrId("settingsPage.memoriesThumbnailSizeLarge") }
                   //% "Largest"
                   MenuItem { text: qsTrId("settingsPage.memoriesThumbnailSizeLargest") }
               }
               onCurrentIndexChanged: {
                   if (currentIndex !== settingsManager.memoriesThumbnailSize) {
                       settingsManager.memoriesThumbnailSize = currentIndex
                   }
               }
           }

           ComboBox {
               //% "Scroll to top button position"
               label: qsTrId("settingsPage.scrollToTopPosition")
               //% "Controls position of the scroll to top button on the pages which display assets in lists exceeding the viewport height."
               description: qsTrId("settingsPage.scrollToTopPositionInfo")
               currentIndex: {
                   var pos = settingsManager.scrollToTopPosition
                   if (pos === "left") return 0
                   if (pos === "center") return 1
                   if (pos === "right") return 2
                   return 2
               }
               menu: ContextMenu {
                   //% "Left"
                   MenuItem { text: qsTrId("settingsPage.scrollToTopPositionLeft") }
                   //% "Center"
                   MenuItem { text: qsTrId("settingsPage.scrollToTopPositionCenter") }
                   //% "Right"
                   MenuItem { text: qsTrId("settingsPage.scrollToTopPositionRight") }
               }
               onCurrentIndexChanged: {
                   var pos = ["left", "center", "right"][currentIndex]
                   if (pos !== settingsManager.scrollToTopPosition) {
                       settingsManager.scrollToTopPosition = pos
                   }
               }
           }

           SectionHeader {
               //% "Account"
               text: qsTrId("settingsPage.account")
           }

           DetailItem {
               //% "Server"
               label: qsTrId("settingsPage.server")
               value: authManager.serverUrl
           }

           DetailItem {
               //% "Email"
               label: qsTrId("settingsPage.email")
               value: authManager.email
           }

           Button {
               anchors.horizontalCenter: parent.horizontalCenter
               //% "Logout"
               text: qsTrId("settingsPage.logout")
               onClicked: {
                   //% "Logging out"
                   remorse.execute(qsTrId("settingsPage.loggingOut"), function() {
                       authManager.logout()
                       pageStack.clear()
                       pageStack.push(Qt.resolvedUrl("ServerPage.qml"))
                   })
               }
           }

           SectionHeader {
               //% "Server Statistics"
               text: qsTrId("settingsPage.serverStatistics")
           }

           DetailItem {
               //% "Total photos"
               label: qsTrId("settingsPage.totalPhotos")
               //% "Loading..."
               value: serverStats ? serverStats.photos : qsTrId("settingsPage.totalPhotosLoading")
           }

           DetailItem {
               //% "Total videos"
               label: qsTrId("settingsPage.totalVideos")
               //% "Loading..."
               value: serverStats ? serverStats.videos : qsTrId("settingsPage.totalVideosLoading")
           }

           DetailItem {
               //% "Storage used"
               label: qsTrId("settingsPage.storageUsed")
               //% "Loading..."
               value: serverStats ? formatBytes(serverStats.usage) : qsTrId("settingsPage.storageUsedLoading")
           }

           DetailItem {
               //% "Total assets"
               label: qsTrId("settingsPage.totalAssets")
               //% "Loading..."
               value: serverStats ? (serverStats.photos + serverStats.videos) : qsTrId("settingsPage.totalAssetsLoading")
           }

           Button {
               anchors.horizontalCenter: parent.horizontalCenter
               //% "Refresh statistics"
               text: qsTrId("settingsPage.refreshStatistics")
               onClicked: {
                   settingsPage.serverStats = null
                   immichApi.fetchServerStatistics()
               }
           }

           SectionHeader {
               //% "About Server"
               text: qsTrId("settingsPage.aboutServer")
           }

           BackgroundItem {
               width: parent.width
               height: serverVersionItem.height
               enabled: serverAbout && serverAbout.versionUrl
               onClicked: {
                   if (serverAbout && serverAbout.versionUrl) {
                       Qt.openUrlExternally(serverAbout.versionUrl)
                   }
               }

               DetailItem {
                   id: serverVersionItem
                   //% "Server version"
                   label: qsTrId("settingsPage.serverVersion")
                   //% "Loading..."
                   value: serverAbout ? serverAbout.version : qsTrId("settingsPage.serverVersionLoading")
               }
           }

           SectionHeader {
               //% "About Application"
               text: qsTrId("settingsPage.aboutApplication")
           }

           DetailItem {
               //% "Version"
               label: qsTrId("settingsPage.version")
               value: "0.1.0"
           }

           DetailItem {
               //% "Loaded assets"
               label: qsTrId("settingsPage.loadedAssets")
               value: timelineModel.totalCount
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               wrapMode: Text.WordWrap
               color: Theme.secondaryColor
               font.pixelSize: Theme.fontSizeSmall
               //% "Harbour Immich - A native Immich client for Sailfish OS"
               text: qsTrId("settingsPage.applicationInfo")
           }

           Item {
               width: parent.width
               height: Theme.paddingLarge
           }
       }

       VerticalScrollDecorator {}
   }

   RemorsePopup {
       id: remorse
   }
}
