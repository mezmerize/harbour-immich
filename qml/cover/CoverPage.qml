import QtQuick 2.0
import Sailfish.Silica 1.0


CoverBackground {
   id: cover

   property var memories: []
   property int currentMemoryIndex: 0
   property int currentAssetIndex: 0

   // Memories slideshow background
   Image {
       id: memoriesImage
       anchors.fill: parent
       fillMode: Image.PreserveAspectCrop
       asynchronous: true
       opacity: status === Image.Ready ? 1.0 : 0
       source: {
           if (memories.length > 0 && memories[currentMemoryIndex] &&
               memories[currentMemoryIndex].assets &&
               memories[currentMemoryIndex].assets[currentAssetIndex]) {
               return "image://immich/thumbnail/" + memories[currentMemoryIndex].assets[currentAssetIndex].id
           }
           return ""
       }

       Behavior on opacity { FadeAnimation { duration: 500 } }
   }

   // Darkening overlay for text readability
   Rectangle {
       anchors.fill: parent
       color: memoriesImage.source != "" ? Theme.rgba("black", 0.3) : "transparent"
   }

   // Fallback icon when no memories
   Image {
       id: coverIcon
       anchors.centerIn: parent
       source: "image://theme/icon-l-image"
       opacity: memoriesImage.source == "" ? 0.6 : 0
       visible: opacity > 0
   }

   Column {
       anchors.bottom: parent.bottom
       anchors.bottomMargin: Theme.paddingMedium
       anchors.left: parent.left
       anchors.leftMargin: Theme.paddingMedium
       anchors.right: parent.right
       anchors.rightMargin: Theme.paddingMedium
       spacing: Theme.paddingSmall / 2

       Label {
           id: memoryTitle
           width: parent.width
           text: {
               if (memories.length > 0 && memories[currentMemoryIndex]) {
                   var memory = memories[currentMemoryIndex]
                   var currentYear = new Date().getFullYear()
                   var memoryYear = 0
                   if (memory.data && memory.data.year) {
                       memoryYear = memory.data.year
                   } else if (memory.assets && memory.assets[0] && memory.assets[0].fileCreatedAt) {
                       memoryYear = new Date(memory.assets[0].fileCreatedAt).getFullYear()
                   }
                   var yearsAgo = currentYear - memoryYear
                   if (yearsAgo <= 0) yearsAgo = 1
                   //% "%1 year(s) ago"
                   return qsTrId("coverPage.yearsAgo").arg(yearsAgo)
               }
               return ""
           }
           font.pixelSize: Theme.fontSizeSmall
           font.bold: true
           color: Theme.primaryColor
           visible: memories.length > 0
           truncationMode: TruncationMode.Fade
       }

       Label {
           width: parent.width
           text: "Immich"
           font.pixelSize: Theme.fontSizeMedium
           color: Theme.primaryColor
       }
   }

   // Slideshow timer
   Timer {
       id: slideshowTimer
       interval: 5000
       running: cover.status === Cover.Active && memories.length > 0
       repeat: true
       onTriggered: {
           if (memories.length === 0) return

           var currentMemory = memories[currentMemoryIndex]
           if (currentMemory && currentMemory.assets) {
               // Move to next asset in current memory
               if (currentAssetIndex < currentMemory.assets.length - 1) {
                   currentAssetIndex++
               } else {
                   // Move to next memory
                   currentAssetIndex = 0
                   currentMemoryIndex = (currentMemoryIndex + 1) % memories.length
               }
           }
       }
   }

   CoverActionList {
       enabled: authManager.isAuthenticated


       CoverAction {
           iconSource: "image://theme/icon-cover-refresh"
           onTriggered: {
               immichApi.fetchTimelineBuckets(false, "desc")
               immichApi.fetchMemories()
           }
       }
   }

   Connections {
       target: immichApi
       onMemoriesReceived: function(memoriesData) {
           // Filter only "on_this_day" memories with assets
           var filtered = []
           for (var i = 0; i < memoriesData.length; i++) {
               var memory = memoriesData[i]
               if (memory.type === "on_this_day" && memory.assets && memory.assets.length > 0) {
                   filtered.push(memory)
               }
           }
           cover.memories = filtered
           currentMemoryIndex = 0
           currentAssetIndex = 0
       }
   }

   Component.onCompleted: {
       if (authManager.isAuthenticated) {
           immichApi.fetchMemories()
       }
   }
}



