import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0
import "../components"

Page {
    id: page

    function fileNameFromPath(path) {
        if (!path) return ""
        var parts = String(path).split("/")
        return parts[parts.length - 1]
    }

    function statusColor() {
        if (!clientCertManager.hasCertificate) return Theme.secondaryColor
        if (clientCertManager.isExpired) return Theme.errorColor
        if (clientCertManager.isExpiringSoon) return Theme.highlightColor
        return Theme.primaryColor
    }

    function statusText() {
        if (clientCertManager.isExpired) {
            //% "Expired"
            return qsTrId("clientCertPage.statusExpired")
        }
        if (clientCertManager.isExpiringSoon) {
            //% "Expires in %n day(s)"
            return qsTrId("clientCertPage.statusExpiringSoon", clientCertManager.daysUntilExpiry)
        }
        //% "Valid"
        return qsTrId("clientCertPage.statusValid")
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader {
                //% "Client Certificate"
                title: qsTrId("clientCertPage.title")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                //% "Import a PKCS#12 (.p12 or .pfx) certificate to authenticate this device to servers that require mutual TLS (mTLS). Changes take effect immediately."
                text: qsTrId("clientCertPage.description")
            }

            // Expiry warning
            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: expiryRow.height + Theme.paddingMedium * 2
                radius: Theme.paddingSmall
                color: Theme.rgba(Theme.errorColor, 0.2)
                visible: clientCertManager.hasCertificate && (clientCertManager.isExpired || clientCertManager.isExpiringSoon)

                Row {
                    id: expiryRow
                    anchors.centerIn: parent
                    spacing: Theme.paddingMedium
                    width: parent.width - Theme.paddingMedium * 2

                    Icon {
                        source: "image://theme/icon-s-warning"
                        color: Theme.errorColor
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Label {
                        width: parent.width - parent.spacing - Theme.iconSizeSmall
                        wrapMode: Text.WordWrap
                        color: Theme.errorColor
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                        text: clientCertManager.isExpired
                            //% "The client certificate has expired. Import a new one to keep connecting."
                            ? qsTrId("clientCertPage.expiredWarning")
                            //% "The client certificate is expiring soon. Consider importing a new one."
                            : qsTrId("clientCertPage.expiringSoonWarning")
                    }
                }
            }

            SectionHeader {
                visible: clientCertManager.hasCertificate
                //% "Certificate details"
                text: qsTrId("clientCertPage.details")
            }

            Column {
                width: parent.width
                visible: clientCertManager.hasCertificate

                DetailItem {
                    //% "Subject"
                    label: qsTrId("clientCertPage.subject")
                    value: clientCertManager.subject
                }
                DetailItem {
                    //% "Issuer"
                    label: qsTrId("clientCertPage.issuer")
                    value: clientCertManager.issuer
                }
                DetailItem {
                    //% "Serial number"
                    label: qsTrId("clientCertPage.serial")
                    value: clientCertManager.serialNumber
                }
                DetailItem {
                    //% "Valid from"
                    label: qsTrId("clientCertPage.validFrom")
                    value: clientCertManager.validFrom
                }
                DetailItem {
                    //% "Valid until"
                    label: qsTrId("clientCertPage.validUntil")
                    value: clientCertManager.validUntil
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }

            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: statusRow.height + Theme.paddingMedium * 2
                radius: Theme.paddingSmall
                color: Theme.rgba(Theme.highlightColor, 0.2)

                Row {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: Theme.paddingMedium

                    Label {
                        visible: clientCertManager.hasCertificate
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.WordWrap
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        //% "Status:"
                        text: qsTrId("clientCertPage.status")
                    }

                    Label {
                        visible: clientCertManager.hasCertificate
                        anchors.verticalCenter: parent.verticalCenter
                        color: page.statusColor()
                        font.pixelSize: Theme.fontSizeSmall
                        text: page.statusText()
                    }

                    Label {
                        visible: !clientCertManager.hasCertificate
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.WordWrap
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        //% "No client certificate configured"
                        text: qsTrId("clientCertPage.none")
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: clientCertManager.hasCertificate
                    //% "Replace certificate"
                    ? qsTrId("clientCertPage.replace")
                    //% "Import certificate"
                    : qsTrId("clientCertPage.import")
                onClicked: pageStack.push(importDialogComponent)
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: clientCertManager.hasCertificate
                //% "Remove certificate"
                text: qsTrId("clientCertPage.remove")
                onClicked: {
                    //% "Removing certificate"
                    remorse.execute(qsTrId("notification.removingCertificate"), function() {
                        clientCertManager.removeCertificate()
                    })
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }

            TextSwitch {
                //% "Allow self-signed server certificates"
                text: qsTrId("clientCertPage.allowSelfSigned")
                //% "Disables server certificate verification for the configured server only. Client certificate (mTLS) still applies."
                description: qsTrId("clientCertPage.allowSelfSignedInfo")
                checked: clientCertManager.allowSelfSigned
                onCheckedChanged: clientCertManager.allowSelfSigned = checked
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }

    RemorsePopup {
        id: remorse
    }

    NotificationBanner {
        id: notification
        anchors.top: parent.top
    }

    Component {
        id: importDialogComponent
        Dialog {
            id: importDialog
            property string certPath: ""
            canAccept: certPath.length > 0

            Column {
                width: parent.width
                spacing: Theme.paddingMedium

                DialogHeader {
                    //% "Import certificate"
                    title: qsTrId("clientCertPage.importCertificate")
                }

                ValueButton {
                    width: parent.width
                    //% "Certificate file"
                    label: qsTrId("clientCertPage.certificateFile")
                    //% "Choose file"
                    value: importDialog.certPath.length > 0 ? page.fileNameFromPath(importDialog.certPath) : qsTrId("clientCertPage.chooseFile")
                    onClicked: pageStack.push(filePickerComponent)
                }

                PasswordField {
                    id: passwordField
                    width: parent.width
                    //% "Password"
                    label: qsTrId("clientCertPage.password")
                    //% "Leave empty if the file has no password"
                    placeholderText: qsTrId("clientCertPage.passwordPlaceholder")
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: importDialog.accept()
                }
            }

            Component {
                id: filePickerComponent
                FilePickerPage {
                    //% "Select certificate"
                    title: qsTrId("clientCertPage.selectFile")
                    nameFilters: [ "*.p12", "*.pfx", "*.P12", "*.PFX" ]
                    onSelectedContentPropertiesChanged: importDialog.certPath = selectedContentProperties.filePath
                }
            }

            onAccepted: clientCertManager.importCertificate(importDialog.certPath, passwordField.text)
        }
    }

    Connections {
        target: clientCertManager
        onImportSucceeded: {
            //% "Certificate imported and applied"
            notification.show(qsTrId("notification.certificateImported"))
        }
        onImportFailed: {
            //% "Could not import certificate - check the file and password"
            notification.showError(qsTrId("notification.certificateImportFailed"))
        }
    }
}
