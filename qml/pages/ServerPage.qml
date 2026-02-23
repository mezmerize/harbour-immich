import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property bool hasError: false

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                //% "Server Configuration"
                title: qsTrId("serverPage.serverConfiguration")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeMedium
                //% "Enter your Immich server URL to get started"
                text: qsTrId("serverPage.serverConfigurationInfo")
            }

            TextField {
                id: serverUrlField
                width: parent.width
                //% "Server URL"
                label: qsTrId("serverPage.serverUrl")
                placeholderText: "http://your-server-ip:port"
                text: authManager.serverUrl || ""
                inputMethodHints: Qt.ImhUrlCharactersOnly
                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: nextButton.clicked()
                color: page.hasError ? Theme.errorColor : Theme.primaryColor
                onTextChanged: page.hasError = false
            }

            Button {
                id: nextButton
                anchors.horizontalCenter: parent.horizontalCenter
                //% "Next"
                text: qsTrId("serverPage.next")
                enabled: serverUrlField.text.length > 0
                onClicked: {
                    var url = String(serverUrlField.text).trim()
                    if (url.charAt(url.length - 1) === "/") {
                        url = url.substring(0, url.length - 1)
                    }

                    // Validate URL format
                    var urlPattern = /^https?:\/\/(([a-zA-Z0-9\-]+\.)*[a-zA-Z0-9\-]+|localhost|\d{1,3}\.\d{1,3}\.\d{1,3})(:\d+)?(\/.*)?$/
                    if (!urlPattern.test(url)) {
                        page.hasError = true
                        return
                    }

                    authManager.serverUrl = url
                    pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                //% "Make sure your Immich server is accessible from this device"
                text: qsTrId("serverPage.serverUrlInfo")
            }

            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: errorLabel.height + Theme.paddingMedium * 2
                radius: Theme.paddingSmall
                color: Theme.rgba(Theme.errorColor, 0.2)
                visible: page.hasError

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.paddingMedium
                    width: parent.width - Theme.paddingMedium * 2

                    Icon {
                        source: "image://theme/icon-s-warning"
                        color: Theme.errorColor
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Label {
                        id: errorLabel
                        width: parent.width - parent.spacing - Theme.iconSizeSmall
                        wrapMode: Text.WordWrap
                        color: Theme.errorColor
                        font.pixelSize: Theme.fontSizeSmall
                        //% "Please enter a valid URL (e.g., http://192.168.1.100:2283)"
                        text: qsTrId("serverPage.serverUrlError")
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
