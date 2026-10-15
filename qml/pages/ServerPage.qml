import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page

    readonly property bool isLoggingIn: authManager.checkingServer
    property bool hasError: false
    property string errorText: ""

    function processServerUrl() {
        hasError = false
        authManager.checkServer(String(serverUrlField.text))
    }

    Component.onCompleted: {
        if (errorText) {
            hasError = true
            errorLabel.text = errorText
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                //% "Client certificate"
                text: qsTrId("pullDownMenu.clientCertificate")
                onClicked: pageStack.push(Qt.resolvedUrl("ClientCertPage.qml"))
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                //% "Server Configuration"
                title: qsTrId("serverPage.serverConfiguration")
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width / 2
                source: Qt.resolvedUrl("../../icons/logo-main.svg")
                fillMode: Image.PreserveAspectFit
                smooth: true
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
                EnterKey.enabled: text.length > 0 && !page.isLoggingIn
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: page.processServerUrl()
                color: page.hasError ? Theme.errorColor : Theme.primaryColor
                onTextChanged: page.hasError = false
            }

            Button {
                id: nextButton
                anchors.horizontalCenter: parent.horizontalCenter
                //% "Next"
                text: qsTrId("serverPage.next")
                enabled: serverUrlField.text.length > 0 && !page.isLoggingIn
                onClicked: page.processServerUrl()
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

            LoadingIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                loading: isLoggingIn
                indicatorSize: Theme.iconSizeMedium
            }
        }
    }

    Connections {
        target: authManager
        onServerCheckSucceeded: {
            if (page.status === PageStatus.Active || pageStack.currentPage === page) {
                pageStack.push(Qt.resolvedUrl("LoginPage.qml"))
            }
        }
        onServerCheckFailed: {
            page.hasError = true
            errorLabel.text = error || qsTrId("serverPage.serverUrlError")
        }
    }
}
