import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
   id: memoriesBar
   width: parent.width
   height: memoriesRow.height + Theme.paddingMedium * 2
   visible: memoriesModel.count > 0

   property bool loading: false

   property int thumbnailSize: settingsManager.memoriesThumbnailSize
   property int baseSize: Math.min(Screen.width, Screen.height)
   property int itemSize: thumbnailSize == 0 ? Math.floor(baseSize / 5) : (thumbnailSize == 1 ? Math.floor(baseSize / 4) : (thumbnailSize == 2 ? Math.floor(baseSize / 3) : Math.floor(baseSize / 2)))

   ListModel {
       id: memoriesModel
   }

   function loadMemories(memories) {
       memoriesModel.clear()
       var currentYear = new Date().getFullYear()
       for (var i = 0; i < memories.length; i++) {
           var memory = memories[i]
           if (memory.type === "on_this_day" && memory.assets && memory.assets.length > 0) {
               // Calculate years ago from the memory data
               var memoryYear = 0
               if (memory.data && memory.data.year) {
                   memoryYear = memory.data.year
               } else if (memory.assets[0].localDateTime) {
                   memoryYear = new Date(memory.assets[0].localDateTime).getFullYear()
               } else if (memory.assets[0].fileCreatedAt) {
                   memoryYear = new Date(memory.assets[0].fileCreatedAt).getFullYear()
               }
               var yearsAgo = currentYear - memoryYear
               if (yearsAgo <= 0) yearsAgo = 1
               var title = yearsAgo === 1
                    //% "A year ago"
                    ? qsTrId("memoriesBar.yearAgo")
                    //% "%1 years ago"
                    : qsTrId("memoriesBar.yearsAgo").arg(yearsAgo)
               memoriesModel.append({
                   memoryId: memory.id,
                   title: title,
                   yearsAgo: yearsAgo,
                   assetsJson: JSON.stringify(memory.assets),
                   thumbnailId: memory.assets[0].id,
                   assetCount: memory.assets.length
               })
           }
       }
   }

   Rectangle {
       anchors.fill: parent
       color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
   }

   Column {
       id: memoriesRow
       width: parent.width
       anchors.verticalCenter: parent.verticalCenter
       spacing: Theme.paddingSmall

       Row {
           x: Theme.horizontalPageMargin
           spacing: Theme.paddingSmall

           Icon {
               source: "image://theme/icon-m-clock"
               width: Theme.iconSizeSmall
               height: Theme.iconSizeSmall
               anchors.verticalCenter: parent.verticalCenter
           }

           Label {
               //% "On This Day"
               text: qsTrId("memoriesBar.onThisDay")
               font.pixelSize: Theme.fontSizeSmall
               font.bold: true
               color: Theme.highlightColor
               anchors.verticalCenter: parent.verticalCenter
           }
       }

       SilicaListView {
           id: memoriesList
           width: parent.width
           height: memoriesBar.itemSize + Theme.paddingSmall
           orientation: ListView.Horizontal
           clip: true
           spacing: Theme.paddingMedium
           leftMargin: Theme.horizontalPageMargin
           rightMargin: Theme.horizontalPageMargin
           cacheBuffer: 256  // Limit cache to prevent memory issues

           model: memoriesModel

           delegate: BackgroundItem {
               id: memoryDelegate
               width: memoriesBar.itemSize + Theme.paddingLarge
               height: memoriesBar.itemSize + Theme.paddingSmall

               Column {
                   anchors.fill: parent
                   spacing: Theme.paddingSmall / 2

                   Rectangle {
                       width: memoriesBar.itemSize
                       height: memoriesBar.itemSize
                       anchors.horizontalCenter: parent.horizontalCenter
                       color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                       radius: Theme.paddingSmall

                       Image {
                           anchors.fill: parent
                           anchors.margins: 2
                           source: model.thumbnailId ? "image://immich/thumbnail/" + model.thumbnailId : ""
                           fillMode: Image.PreserveAspectCrop
                           asynchronous: true
                           sourceSize.width: memoriesBar.itemSize * 2
                           sourceSize.height: memoriesBar.itemSize * 2

                           Rectangle {
                               anchors.fill: parent
                               color: "transparent"
                               radius: Theme.paddingSmall - 2
                               border.width: 2
                               border.color: Theme.highlightColor
                           }
                       }

                       Rectangle {
                           anchors.bottom: parent.bottom
                           anchors.right: parent.right
                           anchors.margins: Theme.paddingSmall / 2
                           width: countLabel.width + Theme.paddingSmall
                           height: countLabel.height + Theme.paddingSmall / 2
                           radius: height / 2
                           color: Theme.rgba(Theme.highlightDimmerColor, 0.8)
                           visible: model.assetCount > 1

                           Label {
                               id: countLabel
                               anchors.centerIn: parent
                               text: model.assetCount
                               font.pixelSize: Theme.fontSizeTiny
                               color: Theme.primaryColor
                           }
                       }
                   }

                   Label {
                       anchors.horizontalCenter: parent.horizontalCenter
                       text: model.title
                       font.pixelSize: Theme.fontSizeTiny
                       color: Theme.secondaryColor
                       truncationMode: TruncationMode.Fade
                       width: parent.width
                       horizontalAlignment: Text.AlignHCenter
                   }
               }

               onClicked: {
                   var assetsArray = JSON.parse(model.assetsJson)
                   pageStack.push(Qt.resolvedUrl("../pages/MemoryDetailPage.qml"), {
                       memoryTitle: model.title,
                       assets: assetsArray
                   })
               }
           }

           HorizontalScrollDecorator {}
       }
   }

   BusyIndicator {
       anchors.centerIn: parent
       running: memoriesBar.loading && memoriesModel.count === 0
       size: BusyIndicatorSize.Small
   }

   Label {
       anchors.centerIn: parent
       //% "No memories for today"
       text: qsTrId("memoriesBar.noMemories")
       color: Theme.secondaryColor
       font.pixelSize: Theme.fontSizeSmall
       visible: !memoriesBar.loading && memoriesModel.count === 0 && memoriesBar.visible
   }
}



