import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property bool isLoggingIn: false
    property bool hasError: false

    Component.onCompleted: {
        oauthManager.checkOAuthAvailability(authManager.serverUrl)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                //% "Login"
                title: qsTrId("loginPage.loginTitle")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeMedium
                //% "Sign in to your Immich account"
                text: qsTrId("loginPage.loginInfo")
            }

            TextField {
                id: emailField
                width: parent.width
                //% "Email"
                label: qsTrId("loginPage.email")
                placeholderText: "youremail@email.com"
                inputMethodHints: Qt.ImhEmailCharactersOnly
                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: passwordField.focus = true
                color: page.hasError ? Theme.errorColor : Theme.primaryColor
                onTextChanged: page.hasError = false
                text: authManager.email || ""
            }

            TextField {
                id: passwordField
                width: parent.width
                //% "Password"
                label: qsTrId("loginPage.password")
                //% "Enter password"
                placeholderText: qsTrId("loginPage.passwordPlaceholder")
                echoMode: TextInput.Password
                EnterKey.enabled: emailField.text.length > 0 && text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: loginButton.clicked()
                color: page.hasError ? Theme.errorColor : Theme.primaryColor
                onTextChanged: page.hasError = false
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge

                Button {
                    id: loginButton
                    //% "Login"
                    text: qsTrId("loginPage.loginButton")
                    enabled: emailField.text.length > 0 && passwordField.text.length > 0 && !isLoggingIn
                    onClicked: {
                        isLoggingIn = true
                        authManager.login(emailField.text.trim(), passwordField.text)
                    }
                }
            }

            SectionHeader {
                //% "Or"
                text: qsTrId("loginPage.or")
                visible: oauthManager.oauthEnabled
            }

            Button {
                id: oauthButton
                anchors.horizontalCenter: parent.horizontalCenter
                //% "Login with OAuth"
                text: qsTrId("loginPage.oauthLoginButton")
                visible: oauthManager.oauthEnabled
                enabled: !isLoggingIn
                onClicked: {
                    isLoggingIn = true
                    oauthManager.startOAuthLogin(authManager.serverUrl)
                    pageStack.push(Qt.resolvedUrl("OAuthPage.qml"))
                }
            }

            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: errorLabel.height + Theme.paddingMedium * 2
                radius: Theme.paddingSmall
                color: Theme.rgba(Theme.errorColor, 0.2)
                visible: errorLabel.text.length > 0

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
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: isLoggingIn
                size: BusyIndicatorSize.Medium
            }
        }
    }

    Connections {
        target: authManager
        onLoginFailed: {
            isLoggingIn = false
            page.hasError = true
            //% "Login failed"
            errorLabel.text = error || qsTrId("loginPage.failed")
        }
        onLoginSucceeded: {
            isLoggingIn = false
        }
    }

    Connections {
        target: oauthManager
        onOauthLoginFailed: {
            isLoggingIn = false
            page.hasError = true
            errorLabel.text = error || qsTrId("loginPage.failed")
        }
        onOauthLoginSucceeded: {
            isLoggingIn = false
        }
    }
}
