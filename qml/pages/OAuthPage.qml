import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
   id: oauthPage

   backNavigation: false

   SilicaFlickable {
       anchors.fill: parent
       contentHeight: column.height

       Column {
           id: column
           width: parent.width
           spacing: Theme.paddingLarge

           PageHeader {
               //% "OAuth Login"
               title: qsTrId("oauthPage.oauthLogin")
           }

           BusyIndicator {
               anchors.horizontalCenter: parent.horizontalCenter
               running: oauthManager.busy
               size: BusyIndicatorSize.Large
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               wrapMode: Text.WordWrap
               horizontalAlignment: Text.AlignHCenter
               color: Theme.highlightColor
               font.pixelSize: Theme.fontSizeMedium
               //% "Please complete authentication in the browser"
               text: qsTrId("oauthPage.completeInBrowser")
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               wrapMode: Text.WordWrap
               horizontalAlignment: Text.AlignHCenter
               color: Theme.secondaryHighlightColor
               font.pixelSize: Theme.fontSizeSmall
               //% "You will be returned to the app automatically"
               text: qsTrId("oauthPage.completeInBrowserReturn")
           }
       }
   }

   Connections {
       target: oauthManager
       onOauthLoginSucceeded: {
           authManager.checkStoredCredentials()
           pageStack.clear()
       }
       onOauthLoginFailed: {
           pageStack.pop()
       }
   }
}
