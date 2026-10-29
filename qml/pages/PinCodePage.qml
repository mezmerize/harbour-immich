import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page

    property bool pinExists: false
    property bool hasPassword: false
    property bool loading: true
    property string mode: ""
    property string step: ""
    property bool checkingPin: false
    property string firstPin: ""
    property string currentPin: ""

    function pinEntryLabel() {
        if (page.mode === "create") {
            if (page.step === "confirm") {
                //% "Re-enter your 6-digit PIN to confirm"
                return qsTrId("pinCodePage.confirmPin")
            }
            //% "Create a 6-digit PIN for your locked folder"
            return qsTrId("pinCodePage.createNewPin")
        }
        if (page.mode === "change") {
            if (page.step === "current") {
                //% "Enter your current PIN"
                return qsTrId("pinCodePage.enterCurrentPin")
            }
            if (page.step === "confirm") {
                //% "Re-enter your 6-digit PIN to confirm"
                return qsTrId("pinCodePage.confirmPin")
            }
            //% "Enter a new 6-digit PIN"
            return qsTrId("pinCodePage.enterNewPin")
        }
        if (page.mode === "resetPin") {
            //% "Enter your current PIN"
            return qsTrId("pinCodePage.enterCurrentPin")
        }
        return ""
    }

    function restartFlow() {
        page.firstPin = ""
        page.currentPin = ""
        pinPad.clear()
        passwordField.text = ""
        if (page.mode === "create") {
            page.step = "new"
        } else if (page.mode === "change" || page.mode === "resetPin") {
            page.step = "current"
        }
    }

    function finishAction(message) {
        page.checkingPin = false
        notification.show(message)
        page.mode = ""
        page.step = ""
        page.restartFlow()
        page.loading = true
        immichApi.fetchAuthStatus()
    }

    function pinCompleted(pin) {
        if (page.mode === "create") {
            if (page.step === "new") {
                page.firstPin = pin
                pinPad.clear()
                page.step = "confirm"
            } else if (pin === page.firstPin) {
                page.checkingPin = true
                immichApi.createPinCode(pin)
            } else {
                page.firstPin = ""
                pinPad.clear()
                page.step = "new"
                //% "PINs to do not match, try again"
                notification.show(qsTrId("notification.pinMismatch"))
            }
        } else if (page.mode === "change") {
            if (page.step === "current") {
                page.currentPin = pin
                pinPad.clear()
                page.step = "new"
            } else if (page.step === "new") {
                page.firstPin = pin
                pinPad.clear()
                page.step = "confirm"
            } else if (pin === page.firstPin) {
                page.checkingPin = true
                immichApi.changePinCode(pin, page.currentPin, "")
            } else {
                page.firstPin = ""
                pinPad.clear()
                page.step = "new"
                //% "PINs to do not match, try again"
                notification.show(qsTrId("notification.pinMismatch"))
            }
        } else if (page.mode === "resetPin") {
            var enteredPin = pin
            //% "Resetting PIN"
            remorse.execute(qsTrId("notification.resettingPin"), function() {
                page.checkingPin = true
                immichApi.resetPinCode(enteredPin, "")
            })
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                //% "Locked folder PIN"
                title: qsTrId("pinCodePage.title")
            }

            Item {
                width: 1
                height: Theme.paddingLarge
            }

            LoadingIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                loading: page.loading
                indicatorSize: Theme.iconSizeMedium
            }

            Column {
                width: parent.width
                spacing: Theme.paddingLarge
                visible: !page.loading && page.pinExists && page.mode === ""

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    horizontalAlignment: Text.AlignHCenter
                    //% "A PIN protects your locked folder"
                    text: qsTrId("pinCodePage.pinInfo")
                    color: Theme.secondaryColor
                    wrapMode: Text.WordWrap
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    //% "Change PIN"
                    text: qsTrId("pinCodePage.changePin")
                    onClicked: {
                        page.mode = "change"
                        page.step = "current"
                    }
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    //% "Reset PIN with current PIN"
                    text: qsTrId("pinCodePage.resetWithPin")
                    onClicked: {
                        page.mode = "resetPin"
                        page.step = "current"
                    }
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: page.hasPassword
                    //% "Reset PIN with password"
                    text: qsTrId("pinCodePage.resetWithPassword")
                    onClicked: {
                        page.mode = "resetPassword"
                        page.step = ""
                    }
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    horizontalAlignment: Text.AlignHCenter
                    //% "Resetting the PIN locks the locked folder on all devices"
                    text: qsTrId("pinCodePage.resetPinInfo")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                text: page.pinEntryLabel()
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeMedium
                wrapMode: Text.WordWrap
                visible: !page.loading && page.mode !== "" && page.mode !== "resetPassword"
            }

            PinPad {
                id: pinPad
                width: parent.width
                visible: !page.loading && page.mode !== "" && page.mode !== "resetPassword"
                enabled: !page.checkingPin
                onCompleted: page.pinCompleted(pin)
            }

            Column {
                width: parent.width
                spacing: Theme.paddingLarge
                visible: !page.loading && page.mode === "resetPassword"

                PasswordField {
                    id: passwordField
                    width: parent.width
                    //% "Password"
                    label: qsTrId("pinCodePage.password")
                    //% "Enter your account password"
                    placeholderText: qsTrId("pinCodePage.passwordPlaceholder")
                    enabled: !page.checkingPin
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    enabled: !page.checkingPin && passwordField.text.length > 0
                    //% "Reset PIN"
                    text: qsTrId("pinCodePage.resetPin")
                    onClicked: {
                        //% "Resetting PIN"
                        remorse.execute(qsTrId("notification.resettingPin"), function() {
                            page.checkingPin = true
                            immichApi.resetPinCode("", passwordField.text)
                        })
                    }
                }
            }

            LoadingIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                loading: page.checkingPin
                indicatorSize: Theme.iconSizeMedium
            }
        }

        VerticalScrollDecorator {}
    }

    RemorsePopup {
        id: remorse
        onCanceled: page.restartFlow()
    }

    NotificationBanner {
        id: notification
        anchors.bottom: parent.bottom
    }

    Component.onCompleted: immichApi.fetchAuthStatus()

    Connections {
        target: immichApi
        onAuthStatusReceived: {
            page.loading = false
            page.pinExists = pinCodeExists
            page.hasPassword = hasPassword
            if (!pinCodeExists && page.mode === "") {
                page.mode = "create"
                page.step = "new"
            }
        }
        onPinCodeCreated: {
            //% "PIN created successfully"
            page.finishAction(qsTrId("notification.pinCreated"))
        }
        onPinCodeChanged: {
            //% "PIN changed"
            page.finishAction(qsTrId("notification.pinChanged"))
        }
        onPinCodeReset: {
            //% "PIN reset"
            page.finishAction(qsTrId("notification.pinReset"))
        }
        onErrorOccurred: {
            if (page.checkingPin) {
                page.checkingPin = false
                notification.showError(error)
                page.restartFlow()
            }
        }
    }
}
