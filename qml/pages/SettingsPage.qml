import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
   id: settingsPage

   property var serverStats: null
   property var serverAbout: null
   property bool statsLoading: false
   property bool aboutLoading: false
   property bool statsFailed: false
   property bool aboutFailed: false

   Component.onCompleted: {
       statsLoading = true
       aboutLoading = true
       immichApi.fetchServerStatistics()
       immichApi.fetchServerAbout()
   }

   Connections {
       target: immichApi
       onServerStatisticsReceived: {
           settingsPage.serverStats = stats
           settingsPage.statsLoading = false
       }
       onServerAboutReceived: {
           settingsPage.serverAbout = about
           settingsPage.aboutLoading = false
       }
       onErrorOccurred: {
           if (statsLoading && !serverStats) {
               statsFailed = true
               statsLoading = false
           }
           if (aboutLoading && !serverAbout) {
               aboutFailed = true
               aboutLoading = false
           }
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
               currentIndex: settingsManager.detailQuality === "fullsize" ? 1 : 0
               menu: ContextMenu {
                   //% "Preview (faster, less data)"
                   MenuItem { text: qsTrId("settingsPage.detailQualityPreview") }
                   //% "Original (full resolution)"
                   MenuItem { text: qsTrId("settingsPage.detailQualityOriginal") }
               }
               onCurrentIndexChanged: {
                   var quality = currentIndex === 1 ? "fullsize" : "preview"
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
               //% "Cover"
               text: qsTrId("settingsPage.cover")
           }

           TextSwitch {
               //% "Show assets on cover"
               text: qsTrId("settingsPage.coverShowAssets")
               //% "Display photos on the app cover instead of the default icon."
               description: qsTrId("settingsPage.coverShowAssetsInfo")
               checked: settingsManager.coverShowAssets
               onCheckedChanged: {
                   settingsManager.coverShowAssets = checked
               }
           }

           TextSwitch {
               //% "Slideshow rotation"
               text: qsTrId("settingsPage.coverSlideshow")
               //% "Continuously rotate through images while the cover is visible. When off, the image changes only once when the app is minimized."
               description: qsTrId("settingsPage.coverSlideshowInfo")
               enabled: settingsManager.coverShowAssets
               checked: settingsManager.coverSlideshow
               onCheckedChanged: {
                   settingsManager.coverSlideshow = checked
               }
           }

           SectionHeader {
              //% "Downloads"
              text: qsTrId("settingsPage.downloads")
           }

           ValueButton {
               //% "Downloads folder"
               label: qsTrId("settingsPage.downloadsFolder")
               value: settingsManager.downloadFolder.split("/").pop()
               //% "Folder where downloaded photos and videos will be saved."
               description: qsTrId("settingsPage.downloadsFolderInfo")
               onClicked: {
                   pageStack.push(Qt.resolvedUrl("../components/DownloadFolderDialog.qml"))
               }
           }

           SectionHeader {
              //% "Backup"
              text: qsTrId("settingsPage.backup")
           }

           TextSwitch {
              //% "Automatic backup"
              text: qsTrId("settingsPage.backupEnabled")
              //% "Automatically back up photos and videos from selected folders to your Immich server."
              description: qsTrId("settingsPage.backupEnabledInfo")
              checked: settingsManager.backupEnabled
              onCheckedChanged: {
                  backupManager.enabled = checked
              }
           }

           // Backup status
           Column {
              x: Theme.horizontalPageMargin
              width: parent.width - 2 * Theme.horizontalPageMargin
              spacing: Theme.paddingSmall
              visible: settingsManager.backupEnabled

              Row {
                  width: parent.width
                  spacing: Theme.paddingMedium

                  Icon {
                      source: backupManager.running ? "image://theme/icon-s-sync" : "image://theme/icon-s-cloud-download"
                      width: Theme.iconSizeSmall
                      height: Theme.iconSizeSmall
                      anchors.verticalCenter: parent.verticalCenter
                  }

                  Label {
                      anchors.verticalCenter: parent.verticalCenter
                      font.pixelSize: Theme.fontSizeSmall
                      color: Theme.highlightColor
                      text: {
                          if (backupManager.currentFile) {
                              //% "Backing up: %1"
                              return qsTrId("settingsPage.backingUp").arg(backupManager.currentFile)
                          }
                          if (backupManager.running) {
                              //% "Backup active"
                              return qsTrId("settingsPage.backupActive")
                          }
                          //% "Backup idle"
                          return qsTrId("settingsPage.backupIdle")
                      }
                  }
              }

              // Progress bar (visible during upload)
              Item {
                  width: parent.width
                  height: Theme.paddingSmall
                  visible: backupManager.currentFile !== ""

                  Rectangle {
                      width: parent.width
                      height: parent.height
                      color: Theme.rgba(Theme.highlightColor, 0.2)
                      radius: height / 2
                  }

                  Rectangle {
                      width: parent.width * backupManager.currentProgress
                      height: parent.height
                      color: Theme.highlightColor
                      radius: height / 2
                      Behavior on width { NumberAnimation { duration: 200 } }
                  }
              }

              Row {
                  width: parent.width
                  spacing: Theme.paddingLarge

                  Label {
                      font.pixelSize: Theme.fontSizeExtraSmall
                      color: Theme.secondaryColor
                      //% "Backed up: %1"
                      text: qsTrId("settingsPage.backedUpCount").arg(backupManager.backedUpCount)
                  }

                  Label {
                      font.pixelSize: Theme.fontSizeExtraSmall
                      color: Theme.secondaryColor
                      //% "Pending: %1"
                      text: qsTrId("settingsPage.pendingCount").arg(backupManager.pendingCount)
                  }

                  Label {
                      font.pixelSize: Theme.fontSizeExtraSmall
                      color: backupManager.failedCount > 0 ? "#ff4444" : Theme.secondaryColor
                      //% "Failed: %1"
                      text: qsTrId("settingsPage.failedCount").arg(backupManager.failedCount)
                  }
              }
           }

           // Backup folders
           BackgroundItem {
              width: parent.width
              visible: settingsManager.backupEnabled
              onClicked: pageStack.push(Qt.resolvedUrl("FolderPickerPage.qml"))

              Row {
                  x: Theme.horizontalPageMargin
                  width: parent.width - 2 * Theme.horizontalPageMargin
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Theme.paddingMedium

                  Icon {
                      source: "image://theme/icon-m-folder"
                      width: Theme.iconSizeMedium
                      height: Theme.iconSizeMedium
                      anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium

                      Label {
                          //% "Watched folders"
                          text: qsTrId("settingsPage.watchedFolders")
                          color: Theme.primaryColor
                      }

                      Label {
                          width: parent.width
                          //% "%1 folder(s) selected"
                          text: qsTrId("settingsPage.foldersSelected").arg(settingsManager.backupFolders.length)
                          font.pixelSize: Theme.fontSizeExtraSmall
                          color: Theme.secondaryColor
                      }
                  }
              }
           }

           TextSwitch {
              visible: settingsManager.backupEnabled
              //% "Back up photos on cellular"
              text: qsTrId("settingsPage.backupPhotosOnCellular")
              //% "Allow photo backup when not connected to Wi-Fi."
              description: qsTrId("settingsPage.backupPhotosOnCellularInfo")
              checked: settingsManager.backupPhotosOnCellular
              onCheckedChanged: {
                  settingsManager.backupPhotosOnCellular = checked
              }
           }

           TextSwitch {
              visible: settingsManager.backupEnabled
              //% "Back up videos on cellular"
              text: qsTrId("settingsPage.backupVideosOnCellular")
              //% "Allow video backup when not connected to Wi-Fi."
              description: qsTrId("settingsPage.backupVideosOnCellularInfo")
              checked: settingsManager.backupVideosOnCellular
              onCheckedChanged: {
                  settingsManager.backupVideosOnCellular = checked
              }
           }

           TextSwitch {
              visible: settingsManager.backupEnabled
              //% "Only while charging"
              text: qsTrId("settingsPage.backupOnlyWhileCharging")
              //% "Only run backup when the device is connected to a charger."
              description: qsTrId("settingsPage.backupOnlyWhileChargingInfo")
              checked: settingsManager.backupOnlyWhileCharging
              onCheckedChanged: {
                  settingsManager.backupOnlyWhileCharging = checked
              }
           }

           TextSwitch {
              visible: settingsManager.backupEnabled
              //% "Delete after backup"
              text: qsTrId("settingsPage.backupDeleteAfter")
              //% "Remove photos and videos from device after successful backup."
              description: qsTrId("settingsPage.backupDeleteAfterInfo")
              checked: settingsManager.backupDeleteAfter
              onCheckedChanged: {
                  settingsManager.backupDeleteAfter = checked
              }
           }

           TextSwitch {
               visible: settingsManager.backupEnabled
               //% "Auto-disable after backup
               text: qsTrId("settingsPage.backupAutoDisable")
               //% "Automatically turn off backup after all pending files have been uploaded."
               description: qsTrId("settingsPage.backupAutoDisableInfo")
               checked: settingsManager.backupAutoDisable
               onCheckedChanged: {
                   settingsManager.backupAutoDisable = checked
               }
           }

           TextSwitch {
               visible: settingsManager.backupEnabled
               //% "Skip asset verification"
               text: qsTrId("settingsPage.backupSkipVerification")
               //% "Skip checking of assets against the server before uploading. Faster scanning, but duplicates are only detected by the server during upload."
               description: qsTrId("settingsPage.backupSkipVerificationInfo")
               checked: settingsManager.backupSkipVerification
               onCheckedChanged: {
                   settingsManager.backupSkipVerification = checked
               }
           }

           // Scan interval
           ComboBox {
               visible: settingsManager.backupEnabled
               //% "Scan interval"
               label: qsTrId("settingsPage.backupScanInterval")
               //% "How often to scan for new files. Shorter intervals may impact battery life."
               description: qsTrId("settingsPage.backupScanIntervalInfo")
               currentIndex: {
                   var mins = settingsManager.backupScanInterval
                   if (mins <= 30) return 0
                   if (mins <= 60) return 1
                   if (mins <= 240) return 2
                   return 3
               }
               menu: ContextMenu {
                   MenuItem {
                       //% "30 minutes"
                       text: qsTrId("settingsPage.backupScanInterval30")
                       onClicked: settingsManager.backupScanInterval = 30
                   }
                   MenuItem {
                       //% "1 hour"
                       text: qsTrId("settingsPage.backupScanInterval60")
                       onClicked: settingsManager.backupScanInterval = 60
                   }
                   MenuItem {
                       //% "4 hours"
                       text: qsTrId("settingsPage.backupScanInterval240")
                       onClicked: settingsManager.backupScanInterval = 240
                   }
                   MenuItem {
                       //% "8 hours"
                       text: qsTrId("settingsPage.backupScanInterval480")
                       onClicked: settingsManager.backupScanInterval = 480
                   }
               }
           }

           // Backup from date
           ValueButton {
               visible: settingsManager.backupEnabled
               //% "Back up files from"
               label: qsTrId("settingsPage.backupFromDate")
               //% "All files (no limit)"
               value: settingsManager.backupFromDate ? Qt.formatDate(new Date(settingsManager.backupFromDate), "dd MMM yyyy") : qsTrId("settingsPage.backupFromDateAll")
               onClicked: {
                   var currentDate = settingsManager.backupFromDate ? new Date(settingsManager.backupFromDate) : new Date()
                   var dialog = pageStack.push("Sailfish.Silica.DatePickerDialog", {
                       date: currentDate
                   })
                   dialog.accepted.connect(function() {
                       settingsManager.backupFromDate = dialog.date.toISOString().substring(0, 10)
                   })
               }
               onPressAndHold: {
                   settingsManager.backupFromDate = ""
               }
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               visible: settingsManager.backupEnabled
               //% "Only back up files modified after this date. Long press to clear."
               text: qsTrId("settingsPage.backupFromDateInfo")
               font.pixelSize: Theme.fontSizeExtraSmall
               color: Theme.secondaryColor
               wrapMode: Text.WordWrap
           }

           Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Theme.paddingMedium
              visible: settingsManager.backupEnabled

              Button {
                  //% "Scan now"
                  text: qsTrId("settingsPage.backupScanNow")
                  onClicked: backupManager.scanNow()
              }

              Button {
                  //% "Retry failed"
                  text: qsTrId("settingsPage.backupRetryFailed")
                  enabled: backupManager.failedCount > 0
                  onClicked: backupManager.retryFailed()
              }
           }

           // Clear database button
           Button {
               anchors.horizontalCenter: parent.horizontalCenter
               visible: settingsManager.backupEnabled
               //% "Clear backup database"
               text: qsTrId("settingsPage.backupClearDb")
               color: "#ff4444"
               onClicked: {
                   //% "Clearing backup database"
                   remorse.execute(qsTrId("settingsPage.backupClearDbRemorse"), function() {
                       backupManager.clearDatabase()
                   })
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

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               visible: statsFailed && !serverStats
               //% "Server statistics are not available at the moment."
               text: qsTrId("settingsPage.serverStatisticsNotAvailable")
               font.pixelSize: Theme.fontSizeSmall
               color: Theme.secondaryHighlightColor
               wrapMode: Text.WordWrap
               horizontalAlignment: Text.AlignHCenter
           }

           DetailItem {
               visible: !statsFailed || serverStats
               //% "Total photos"
               label: qsTrId("settingsPage.totalPhotos")
               //% "Loading..."
               value: serverStats ? serverStats.photos : qsTrId("settingsPage.totalPhotosLoading")
           }

           DetailItem {
               visible: !statsFailed || serverStats
               //% "Total videos"
               label: qsTrId("settingsPage.totalVideos")
               //% "Loading..."
               value: serverStats ? serverStats.videos : qsTrId("settingsPage.totalVideosLoading")
           }

           DetailItem {
               visible: !statsFailed || serverStats
               //% "Storage used"
               label: qsTrId("settingsPage.storageUsed")
               //% "Loading..."
               value: serverStats ? formatBytes(serverStats.usage) : qsTrId("settingsPage.storageUsedLoading")
           }

           DetailItem {
               visible: !statsFailed || serverStats
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
                   settingsPage.statsFailed = false
                   settingsPage.statsLoading = true
                   immichApi.fetchServerStatistics()
               }
           }

           SectionHeader {
               //% "About Server"
               text: qsTrId("settingsPage.aboutServer")
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               visible: aboutFailed && !serverAbout
               //% "Server version info is not available at the moment."
               text: qsTrId("settingsPage.aboutServerNotAvailable")
               font.pixelSize: Theme.fontSizeSmall
               color: Theme.secondaryHighlightColor
               wrapMode: Text.WordWrap
               horizontalAlignment: Text.AlignHCenter
           }

           BackgroundItem {
               width: parent.width
               height: serverVersionItem.height
               visible: !aboutFailed || serverAbout
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
               value: "0.2.1"
           }

           DetailItem {
               //% "Loaded assets"
               label: qsTrId("settingsPage.loadedAssets")
               value: timelineModel.totalCount
           }

           Button {
               anchors.horizontalCenter: parent.horizontalCenter
               //% "View application logs"
               text: qsTrId("settingsPage.viewLogs")
               onClicked: pageStack.push(Qt.resolvedUrl("LogViewerPage.qml"))
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               wrapMode: Text.WordWrap
               horizontalAlignment: Text.AlignHCenter
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

   Connections {
       target: backupManager
       onServerSyncComplete: {
           //% "Verified: %1 already on server, %2 new to upload"
           notification.show(qsTrId("settingsPage.serverSyncResult").arg(matched).arg(pending))
       }
       onDatabaseCleared: {
           //% "Backup database cleared"
           notification.show(qsTrId("settingsPage.dbCleared"))
       }
       onMediaTypesFetchFailed: {
           //% "Could not fetch supported media types from server. Backup disabled.
           notification.showError(qsTrId("settingsPage.mediaTypesFetchFailed"))
       }
   }

   NotificationBanner {
       id: notification
       anchors.bottom: parent.bottom
       z: 10
   }
}
