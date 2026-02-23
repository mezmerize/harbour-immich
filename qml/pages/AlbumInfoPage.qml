import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
   id: page

   property string albumId
   property var albumInfo

   SilicaFlickable {
       anchors.fill: parent
       contentHeight: column.height

       Column {
           id: column
           width: page.width
           spacing: Theme.paddingMedium

           PageHeader {
               //% "Album Information"
               title: qsTrId("albumInfoPage.albumInformation")
           }

           DetailItem {
               //% "Album name"
               label: qsTrId("albumInfoPage.albumName")
               value: albumInfo ? albumInfo.albumName : ""
           }

           DetailItem {
               //% "Description"
               label: qsTrId("albumInfoPage.description")
               //% "No description"
               value: albumInfo && albumInfo.description ? albumInfo.description : qsTrId("albumInfoPage.noDescription")
           }

           DetailItem {
               //% "Created"
               label: qsTrId("albumInfoPage.created")
               value: albumInfo ? Qt.formatDateTime(new Date(albumInfo.createdAt), "dd.MM.yyyy hh:mm") : ""
           }

           DetailItem {
               //% "Updated"
               label: qsTrId("albumInfoPage.updated")
               value: albumInfo ? Qt.formatDateTime(new Date(albumInfo.updatedAt), "dd.MM.yyyy hh:mm") : ""
           }

           DetailItem {
               //% "Owner"
               label: qsTrId("albumInfoPage.owner")
               value: albumInfo && albumInfo.owner ? albumInfo.owner.name : ""
           }

           DetailItem {
               //% "Asset count"
               label: qsTrId("albumInfoPage.assetCount")
               value: albumInfo ? albumInfo.assetCount : ""
           }

           SectionHeader {
               //% "Shared with"
               text: qsTrId("albumInfoPage.sharedWith")
               visible: albumInfo && albumInfo.albumUsers && albumInfo.albumUsers.length > 0
           }

           Repeater {
               model: albumInfo && albumInfo.albumUsers ? albumInfo.albumUsers : []

               DetailItem {
                   label: modelData.user ? modelData.user.name : ""
                   value: modelData.role ? modelData.role : ""
               }
           }

           SectionHeader {
               //% "Sharing"
               text: qsTrId("albumInfoPage.sharing")
               visible: albumInfo && albumInfo.shared
           }

           DetailItem {
               visible: albumInfo && albumInfo.shared
               //% "Shared"
               label: qsTrId("albumInfoPage.shared")
               value: albumInfo && albumInfo.shared
                      //% "Yes"
                      ? qsTrId("albumInfoPage.sharedYes")
                      //% "No"
                      : qsTrId("albumInfoPage.sharedNo")
           }
       }

       VerticalScrollDecorator {}
   }

   Component.onCompleted: {
       if (albumId) {
           immichApi.fetchAlbumDetails(albumId)
       }
   }

   Connections {
       target: immichApi
       onAlbumDetailsReceived: {
           albumInfo = details
       }
   }
}
