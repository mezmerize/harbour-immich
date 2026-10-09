import QtQuick 2.6
import Sailfish.Silica 1.0

Dialog {
    id: downloadFolderDialog

    property string selectedFolder: settingsManager.downloadFolder

    property var suggestedFolders: {
        var home = settingsManager.homePath()
        var suggestions = []
        suggestions.push(home + "/Downloads")
        suggestions.push(home + "/Pictures")
        suggestions.push(home + "/Videos")
        suggestions.push(home + "/android_storage/Download")
        suggestions.push(home + "/android_storage/DCIM")
        return suggestions
    }

    canAccept: selectedFolder.length > 0

    onAccepted: {
        settingsManager.downloadFolder = selectedFolder
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            DialogHeader {
                //% "Accept"
                acceptText: qsTrId("downloadFolderDialog.accept")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                //% "Select or enter a folder where downloaded photos and videos will be saved."
                text: qsTrId("downloadFolderDialog.description")
            }

            Item { width: 1; height: Theme.paddingMedium }

            SectionHeader {
                //% "Suggested Folders"
                text: qsTrId("downloadFolderDialog.suggestedFolders")
            }

            Repeater {
                model: suggestedFolders

                ListItem {
                    id: folderDelegate
                    contentHeight: Theme.itemSizeSmall
                    width: parent.width
                    highlighted: down || downloadFolderDialog.selectedFolder === modelData

                    onClicked: {
                        downloadFolderDialog.selectedFolder = modelData
                        customFolderField.text = ""
                    }

                    Row {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingMedium

                        Icon {
                            source: downloadFolderDialog.selectedFolder === modelData ? "image://theme/icon-m-acknowledge" : "image://theme/icon-m-folder"
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium

                            Label {
                                width: parent.width
                                text: modelData.split("/").pop()
                                font.pixelSize: Theme.fontSizeSmall
                                color: folderDelegate.highlighted ? Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                            }

                            Label {
                                width: parent.width
                                text: modelData
                                font.pixelSize: Theme.fontSizeTiny
                                color: Theme.secondaryColor
                                truncationMode: TruncationMode.Fade
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }

            SectionHeader {
                //% "Custom Folder"
                text: qsTrId("downloadFolderDialog.customFolder")
            }

            TextField {
                id: customFolderField
                width: parent.width
                //% "Enter folder path"
                placeholderText: qsTrId("downloadFolderDialog.enterPath")
                //% "Folder path"
                label: qsTrId("downloadFolderDialog.folderPath")
                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: {
                    var path = text.trim()
                    if (path.length > 0) {
                        downloadFolderDialog.selectedFolder = path
                        focus = false
                    }
                }
                onTextChanged: {
                    var path = text.trim()
                    if (path.length > 0) {
                        downloadFolderDialog.selectedFolder = path
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                //% "Current selection:"
                text: qsTrId("downloadFolderDialog.currentSelection")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: downloadFolderDialog.selectedFolder
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
                truncationMode: TruncationMode.Fade
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }
}
