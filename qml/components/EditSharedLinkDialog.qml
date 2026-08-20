import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    property var linkData: ({})
    property string linkId: linkData.id || ""
    property bool hasExistingPassword: linkData.password !== undefined && linkData.password !== null && linkData.password !== ""

    canAccept: slugField.acceptableInput

    onAccepted: {
        var expiresAt
        if (expirationCombo.currentIndex === 0) {
            // "Keep current" - preserve existing expiration
            expiresAt = linkData.expiresAt || ""
        } else if (expirationCombo.currentIndex === 1) {
            // "Never" - clear expiration
            expiresAt = ""
        } else {
            // New relative expiration
            var ms = expirationCombo.durations[expirationCombo.currentIndex]
            expiresAt = new Date(Date.now() + ms).toISOString()
        }

        immichApi.updateSharedLink(linkId, descriptionField.text, passwordField.text, linkData.password !== passwordField.text, expiresAt, allowDownloadSwitch.checked, allowUploadSwitch.checked, showMetadataSwitch.checked, slugField.text)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: dialog.width
            spacing: Theme.paddingLarge

            DialogHeader {
                //% "Edit Share Link"
                acceptText: qsTrId("editSharedLinkDialog.save")
            }

            TextArea {
                id: descriptionField
                width: parent.width
                //% "Description"
                label: qsTrId("editSharedLinkDialog.description")
                placeholderText: label
                text: linkData.description || ""
            }

            PasswordField {
                id: passwordField
                width: parent.width
                //% "Password"
                label: qsTrId("editSharedLinkDialog.password")
                //% "Enter password (leave empty for none)"
                placeholderText: qsTrId("editSharedLinkDialog.passwordPlaceholder")
                text: linkData.password || ""

                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: hasExistingPassword && passwordField.text === linkData.password && passwordField.text !== ""
                //% "This link is currently password protected. Edit the field above to change or remove the password."
                text: qsTrId("editSharedLinkDialog.hasPassword")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.WordWrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: hasExistingPassword && passwordField.text === ""
                //% "Password protection will be removed."
                text: qsTrId("editSharedLinkDialog.passwordWillBeRemoved")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.errorColor
                wrapMode: Text.WordWrap
            }

            TextField {
                id: slugField
                //% "Custom URL"
                label: qsTrId("editSharedLinkDialog.slug")
                //% "Custom share URL (optional)
                placeholderText: qsTrId("editSharedLinkDialog.slugPlaceholder")
                text: linkData.slug || ""
                color: slugField.acceptableInput ? Theme.primaryColor : Theme.errorColor
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

                validator: RegExpValidator {
                    regExp: /^(?:[A-Za-z0-9._~!$&'()*+,;=:@\-\s]|%[0-9A-Fa-f]{2})*$/
                }

                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: slugField.text !== "" && slugField.acceptableInput
                text: immichApi.serverUrl() + "/s/" + slugField.text
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.WrapAnywhere
            }

            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: errorLabel.height + Theme.paddingMedium * 2
                radius: Theme.paddingSmall
                color: Theme.rgba(Theme.errorColor, 0.2)
                visible: !slugField.acceptableInput

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
                        font.pixelSize: Theme.fontSizeExtraSmall
                        //% "Please enter a valid custom share URL"
                        text: qsTrId("editSharedLinkDialog.slugError")
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            ComboBox {
                id: expirationCombo
                //% "Expiration"
                label: qsTrId("editSharedLinkDialog.expiration")
                currentIndex: 0

                property var durations: [-1, 0, 30*60*1000, 60*60*1000, 6*60*60*1000, 24*60*60*1000, 7*24*60*60*1000, 30*24*60*60*1000, 90*24*60*60*1000, 365*24*60*60*1000]

                menu: ContextMenu {
                    MenuItem {
                        text: {
                            if (linkData.expiresAt) {
                                var d = new Date(linkData.expiresAt)
                                //% "Keep current (%1)"
                                return qsTrId("editSharedLinkDialog.keepExpiry").arg(Qt.formatDateTime(d, "dd.MM.yyyy hh:mm"))
                            }
                            //% "Keep current (no expiry)"
                            return qsTrId("editSharedLinkDialog.keepNoExpiry")
                        }
                    }
                    //% "Never"
                    MenuItem { text: qsTrId("editSharedLinkDialog.expirationNever") }
                    //% "30 minutes"
                    MenuItem { text: qsTrId("editSharedLinkDialog.expiration30Min") }
                    //% "1 hour"
                    MenuItem { text: qsTrId("editSharedLinkDialog.expiration1Hour") }
                    //% "6 hours"
                    MenuItem { text: qsTrId("editSharedLinkDialog.expiration6Hours") }
                    //% "1 day"
                    MenuItem { text: qsTrId("editSharedLinkDialog.expiration1Day") }
                    //% "7 days"
                    MenuItem { text: qsTrId("editSharedLinkDialog.expiration7Days") }
                    //% "30 days"
                    MenuItem { text: qsTrId("editSharedLinkDialog.expiration30Days") }
                    //% "3 months"
                    MenuItem { text: qsTrId("editSharedLinkDialog.expiration3Months") }
                    //% "1 year"
                    MenuItem { text: qsTrId("editSharedLinkDialog.expiration1Year") }
                }
            }

            TextSwitch {
                id: showMetadataSwitch
                //% "Show metadata"
                text: qsTrId("editSharedLinkDialog.showMetadata")
                //% "Recipients can view metadata for shared assets"
                description: qsTrId("editSharedLinkDialog.showMetadataDescription")
                checked: linkData.showMetadata !== undefined ? linkData.showMetadata : true

                onCheckedChanged: {
                    if (!checked) {
                        allowDownloadSwitch.checked = false
                    }
                }
            }

            TextSwitch {
                id: allowDownloadSwitch
                //% "Allow download"
                text: qsTrId("editSharedLinkDialog.allowDownload")
                //% "Recipients can download assets/albums from this share"
                description: qsTrId("editSharedLinkDialog.allowDownloadDescription")
                checked: linkData.allowDownload !== undefined ? linkData.allowDownload : true
                enabled: showMetadataSwitch.checked
            }

            TextSwitch {
                id: allowUploadSwitch
                //% "Allow upload"
                text: qsTrId("editSharedLinkDialog.allowUpload")
                //% "Recipients can upload assets/albums to this share"
                description: qsTrId("editSharedLinkDialog.allowUploadDescription")
                checked: linkData.allowUpload !== undefined ? linkData.allowUpload : false
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }
}
