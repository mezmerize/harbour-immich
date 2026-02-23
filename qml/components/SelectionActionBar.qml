import QtQuick 2.0
import Sailfish.Silica 1.0

ListItem {
   id: actionBar
   width: parent.width
   contentHeight: Theme.itemSizeLarge
   _backgroundColor: "transparent"
   menu: moreMenu

   property int selectedCount: 0
   property bool hasAnyFavorites: false
   property bool allAreFavorites: false

   signal addToFavorites()
   signal removeFromFavorites()
   signal share()
   signal addToAlbum()
   signal clearSelection()
   signal download()
   signal deleteSelected()

   Rectangle {
       anchors.left: parent.left
       anchors.right: parent.right
       anchors.bottom: parent.bottom
       height: actionBar.contentHeight
       color: Theme.rgba(Theme.highlightDimmerColor, 0.95)

       // Top border
       Rectangle {
           anchors.top: parent.top
           anchors.left: parent.left
           anchors.right: parent.right
           height: 1
           color: Theme.rgba(Theme.highlightColor, 0.3)
       }
   }

   Row {
       anchors.left: parent.left
       anchors.right: parent.right
       anchors.bottom: parent.bottom
       height: actionBar.contentHeight
       anchors.leftMargin: Theme.horizontalPageMargin
       anchors.rightMargin: Theme.horizontalPageMargin

       // Favorite toggle
       IconButton {
           width: parent.width / 4
           height: parent.height
           icon.source: allAreFavorites ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"
           onClicked: {
               if (allAreFavorites) {
                   removeFromFavorites()
               } else {
                   addToFavorites()
               }
           }

           Label {
               anchors.bottom: parent.bottom
               anchors.bottomMargin: Theme.paddingSmall
               anchors.horizontalCenter: parent.horizontalCenter
               text: allAreFavorites
                    //% "Unfav"
                    ? qsTrId("selectionActionBar.unfav")
                    //% "Favorite"
                    : qsTrId("selectionActionBar.favorite")
               font.pixelSize: Theme.fontSizeTiny
               color: Theme.secondaryColor
           }
       }

       // Share
       IconButton {
           width: parent.width / 4
           height: parent.height
           icon.source: "image://theme/icon-m-share"
           onClicked: share()

           Label {
               anchors.bottom: parent.bottom
               anchors.bottomMargin: Theme.paddingSmall
               anchors.horizontalCenter: parent.horizontalCenter
               //% "Share"
               text: qsTrId("selectionActionBar.share")
               font.pixelSize: Theme.fontSizeTiny
               color: Theme.secondaryColor
           }
       }

       // Add to album
       IconButton {
           width: parent.width / 4
           height: parent.height
           icon.source: "image://theme/icon-m-add"
           onClicked: addToAlbum()

           Label {
               anchors.bottom: parent.bottom
               anchors.bottomMargin: Theme.paddingSmall
               anchors.horizontalCenter: parent.horizontalCenter
               //% "Album"
               text: qsTrId("selectionActionBar.album")
               font.pixelSize: Theme.fontSizeTiny
               color: Theme.secondaryColor
           }
       }

       // More menu
       IconButton {
           id: moreButton
           width: parent.width / 4
           height: parent.height
           icon.source: "image://theme/icon-m-other"
           onClicked: actionBar.openMenu()

           Label {
               anchors.bottom: parent.bottom
               anchors.bottomMargin: Theme.paddingSmall
               anchors.horizontalCenter: parent.horizontalCenter
               //% "More"
               text: qsTrId("selectionActionBar.more")
               font.pixelSize: Theme.fontSizeTiny
               color: Theme.secondaryColor
           }
       }
   }

   Component {
       id: moreMenu

       ContextMenu {
           MenuItem {
               //% "Clear selection"
               text: qsTrId("selectionActionBar.clear")
               onClicked: clearSelection()
           }

           MenuItem {
               //% "Download"
               text: qsTrId("selectionActionBar.download")
               onClicked: download()
           }

           MenuItem {
               //% "Delete"
               text: qsTrId("selectionActionBar.delete")
               onClicked: deleteSelected()
           }
       }
   }

   // Selection counter
   Label {
       anchors.bottom: parent.bottom
       anchors.bottomMargin: actionBar.contentHeight - Theme.paddingSmall - height
       anchors.horizontalCenter: parent.horizontalCenter
       //% "%1 selected"
       text: qsTrId("selectionActionBar.selected").arg(selectedCount)
       font.pixelSize: Theme.fontSizeExtraSmall
       color: Theme.highlightColor
   }
}
