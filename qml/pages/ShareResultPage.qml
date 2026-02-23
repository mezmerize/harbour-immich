import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
   id: page

   property string shareUrl: ""

   SilicaFlickable {
       anchors.fill: parent
       contentHeight: column.height

       PullDownMenu {
           MenuItem {
               //% "Copy to clipboard"
               text: qsTrId("shareResultPage.copyToClipboard")
               onClicked: {
                   Clipboard.text = shareUrl
               }
           }

           MenuItem {
               //% "Open in browser"
               text: qsTrId("shareResultPage.openInBrowser")
               onClicked: {
                   Qt.openUrlExternally(shareUrl)
               }
           }
       }

       Column {
           id: column
           width: parent.width
           spacing: Theme.paddingLarge

           PageHeader {
               //% "Share Link Created"
               title: qsTrId("shareResultPage.shareLinkCreated")
           }

           Icon {
               anchors.horizontalCenter: parent.horizontalCenter
               source: "image://theme/icon-m-share"
               color: Theme.highlightColor
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               //% "Your share link has been created successfully"
               text: qsTrId("shareResultPage.shareLinkCreatedInfo")
               font.pixelSize: Theme.fontSizeLarge
               color: Theme.highlightColor
               wrapMode: Text.WordWrap
               horizontalAlignment: Text.AlignHCenter
           }

           Item {
               width: parent.width
               height: Theme.paddingLarge * 2
           }

           BackgroundItem {
               width: parent.width
               height: urlLabel.height + 2 * Theme.paddingLarge

               onClicked: {
                   Clipboard.text = shareUrl
               }

               Rectangle {
                   anchors.fill: parent
                   anchors.margins: Theme.horizontalPageMargin
                   color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                   radius: Theme.paddingSmall

                   Label {
                       id: urlLabel
                       anchors.centerIn: parent
                       width: parent.width - 2 * Theme.paddingLarge
                       text: shareUrl
                       font.pixelSize: Theme.fontSizeSmall
                       color: Theme.primaryColor
                       wrapMode: Text.WrapAnywhere
                       horizontalAlignment: Text.AlignHCenter
                   }
               }
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               //% "Tap the link above to copy it to clipboard"
               text: qsTrId("shareResultPage.copyToClipboardInfo")
               font.pixelSize: Theme.fontSizeExtraSmall
               color: Theme.secondaryColor
               wrapMode: Text.WordWrap
               horizontalAlignment: Text.AlignHCenter
           }

           Item {
               width: parent.width
               height: Theme.paddingLarge * 2
           }

           Rectangle {
               anchors.horizontalCenter: parent.horizontalCenter
               width: qrCode.width + Theme.paddingLarge
               height: qrCode.height + Theme.paddingLarge
               color: "white"
               radius: Theme.paddingSmall

               QRCode {
                   id: qrCode
                   anchors.centerIn: parent
                   width: Math.min(page.width - 4 * Theme.horizontalPageMargin, 300)
                   height: width
                   text: shareUrl
                   foregroundColor: "black"
                   backgroundColor: "white"
               }
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               //% "Scan QR code to open the share link"
               text: qsTrId("shareResultPage.scanQrInfo")
               font.pixelSize: Theme.fontSizeExtraSmall
               color: Theme.secondaryColor
               wrapMode: Text.WordWrap
               horizontalAlignment: Text.AlignHCenter
           }

           Item {
               width: parent.width
               height: Theme.paddingLarge
           }

           Button {
               anchors.horizontalCenter: parent.horizontalCenter
               //% "Done"
               text: qsTrId("shareResultPage.done")
               onClicked: {
                   pageStack.pop()
               }
           }
       }
   }
}
