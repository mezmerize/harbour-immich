import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
   id: dialog

   property var assetIds: []
   property var albumId: null
   property string shareType: "INDIVIDUAL" // INDIVIDUAL or ALBUM

   canAccept: false  // Prevent normal dialog acceptance

   SilicaFlickable {
       anchors.fill: parent
       contentHeight: column.height

       Column {
           id: column
           width: parent.width
           spacing: Theme.paddingLarge

           PageHeader {
               //% "Create Share link"
               title: qsTrId("sharePage.createShareLink")
           }

           SectionHeader {
               //% "Share Settings"
               text: qsTrId("sharePage.shareSettings")
           }

           TextField {
               id: passwordField
               width: parent.width
               //% "Password (optional)"
               label: qsTrId("sharePage.password")
               //% "Enter password to protect share"
               placeholderText: qsTrId("sharePage.passwordPlaceholder")
               echoMode: TextInput.Password

               EnterKey.iconSource: "image://theme/icon-m-enter-next"
               EnterKey.onClicked: focus = false
           }

           ComboBox {
               id: expirationCombo
               //% "Expiration"
               label: qsTrId("sharePage.expiration")
               currentIndex: 0

               // Duration values in milliseconds (0 = never)
               property var durations: [0, 30*60*1000, 60*60*1000, 6*60*60*1000, 24*60*60*1000, 7*24*60*60*1000, 30*24*60*60*1000, 90*24*60*60*1000, 365*24*60*60*1000]

               function getExpiresAt() {
                   var ms = durations[currentIndex]
                   if (ms === 0) return ""
                   return new Date(Date.now() + ms).toISOString()
               }

               menu: ContextMenu {
                   //% "Never"
                   MenuItem { text: qsTrId("sharePage.expirationNever") }
                   //% "30 minutes"
                   MenuItem { text: qsTrId("sharePage.expiration30Min") }
                   //% "1 hour"
                   MenuItem { text: qsTrId("sharePage.expiration1Hour") }
                   //% "6 hours"
                   MenuItem { text: qsTrId("sharePage.expiration6Hours") }
                   //% "1 day"
                   MenuItem { text: qsTrId("sharePage.expiration1Day") }
                   //% "7 days"
                   MenuItem { text: qsTrId("sharePage.expiration7Days") }
                   //% "30 days"
                   MenuItem { text: qsTrId("sharePage.expiration30Days") }
                   //% "3 months"
                   MenuItem { text: qsTrId("sharePage.expiration3Months") }
                   //% "1 year"
                   MenuItem { text: qsTrId("sharePage.expiration1Year") }
               }
           }

           TextSwitch {
               id: allowDownloadSwitch
               //% "Allow download"
               text: qsTrId("sharePage.allowDownload")
               //% "Recipients can download assets/albums from this share"
               description: qsTrId("sharePage.allowDownloadDescription")
               checked: true
           }

           TextSwitch {
               id: allowUploadSwitch
               //% "Allow upload"
               text: qsTrId("sharePage.allowUpload")
               //% "Recipients can upload assets/albums to this share"
               description: qsTrId("sharePage.allowUploadDescription")
               checked: false
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               text: shareType === "INDIVIDUAL" ? (assetIds.length === 1
                     //% "Sharing asset"
                     ? qsTrId("sharePage.sharingAsset")
                     //% "Sharing %1 assets"
                     : qsTrId("sharePage.sharingAssets").arg(assetIds.length))
                     //% "Sharing album"
                     : qsTrId("sharePage.sharingAlbum")
               font.pixelSize: Theme.fontSizeSmall
               color: Theme.secondaryColor
               wrapMode: Text.WordWrap
           }

           Item {
               width: parent.width
               height: Theme.paddingLarge
           }

           Button {
               anchors.horizontalCenter: parent.horizontalCenter
               //% "Create Share link"
               text: qsTrId("sharePage.createShareLinkButton")
               enabled: assetIds.length > 0 || albumId
               onClicked: {
                   var expiresAt = expirationCombo.getExpiresAt()
                   var password = passwordField.text
                   var ids = shareType === "INDIVIDUAL" ? assetIds : albumId
                   immichApi.createSharedLink(shareType, ids, password, expiresAt,
                                              allowDownloadSwitch.checked, allowUploadSwitch.checked)
               }
           }

           Item {
               width: parent.width
               height: Theme.paddingLarge
           }
       }
   }

   Connections {
       target: immichApi
       onSharedLinkCreated: {
           var shareUrl = immichApi.serverUrl() + "/share/" + shareKey
           // Clear selection after successful share creation
           if (shareType === "INDIVIDUAL") {
               timelineModel.clearSelection()
           }

           pageStack.replace(Qt.resolvedUrl("ShareResultPage.qml"), {
               shareUrl: shareUrl
           })
       }
       onErrorOccurred: {
           errorNotification.show(message)
       }
   }
}
