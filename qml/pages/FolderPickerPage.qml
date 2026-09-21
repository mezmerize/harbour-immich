import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: folderPickerPage

    property string currentPath: settingsManager.homePath()
    property var selectedFolders: []

    // Common photo/video folder suggestions
    property var suggestedFolders: {
        var home = settingsManager.homePath()
        var suggestions = []
        suggestions.push(home + "/Pictures")
        suggestions.push(home + "/Videos")
        suggestions.push(home + "/android_storage/DCIM")
        suggestions.push(home + "/android_storage/Pictures")
        suggestions.push(home + "/android_storage/Download")
        return suggestions
    }

    onAccepted: {
        settingsManager.backupFolders = selectedFolders
    }

    Component.onCompleted: {
        selectedFolders = settingsManager.backupFolders
        folderModel.populate()
    }

    function isFolderSelected(path) {
        for (var i = 0; i < selectedFolders.length; i++) {
            if (selectedFolders[i] === path) return true
        }
        return false
    }

    function toggleFolder(path) {
        var folders = selectedFolders.slice()
        var idx = folders.indexOf(path)
        if (idx >= 0) {
            folders.splice(idx, 1)
        } else {
            folders.push(path)
        }
        selectedFolders = folders
    }

    ListModel {
        id: folderModel

        function populate() {
            clear()
            // Add suggested folders
            for (var i = 0; i < suggestedFolders.length; i++) {
                append({
                    "folderPath": suggestedFolders[i],
                    "folderName": suggestedFolders[i].split("/").pop(),
                    "isSuggested": true
                })
            }
            // Add currently selected folders that are not in suggestions
            for (var j = 0; j < selectedFolders.length; j++) {
                var found = false
                for (var k = 0; k < suggestedFolders.length; k++) {
                    if (selectedFolders[j] === suggestedFolders[k]) {
                        found = true
                        break
                    }
                }
                if (!found) {
                    append({
                        "folderPath": selectedFolders[j],
                        "folderName": selectedFolders[j].split("/").pop(),
                        "isSuggested": false
                    })
                }
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            DialogHeader {
                //% "Backup Folders"
                acceptText: qsTrId("folderPickerPage.accept")
            }

            SectionHeader {
                //% "Suggested Folders"
                text: qsTrId("folderPickerPage.suggestedFolders")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                //% "Select folders to watch for automatic backup. Only photos and videos will be backed up."
                text: qsTrId("folderPickerPage.description")
            }

            Item {
                width: 1
                height: Theme.paddingMedium
            }

            Repeater {
                model: folderModel

                ListItem {
                    id: folderDelegate
                    contentHeight: Theme.itemSizeSmall
                    width: parent.width

                    property bool isSelected: isFolderSelected(model.folderPath)

                    onClicked: toggleFolder(model.folderPath)

                    Row {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingMedium

                        Icon {
                            source: folderDelegate.isSelected ? "image://theme/icon-m-acknowledge" : "image://theme/icon-m-folder"
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium

                            Label {
                                width: parent.width
                                text: model.folderName
                                font.pixelSize: Theme.fontSizeSmall
                                color: folderDelegate.highlighted ? Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                            }

                            Label {
                                width: parent.width
                                text: model.folderPath
                                font.pixelSize: Theme.fontSizeTiny
                                color: Theme.secondaryColor
                                truncationMode: TruncationMode.Fade
                            }
                        }
                    }
                }
            }

            Item {
                width: 1
                height: Theme.paddingLarge
            }

            SectionHeader {
                //% "Custom Folder"
                text: qsTrId("folderPickerPage.customFolder")
            }

            TextField {
                id: customFolderField
                width: parent.width
                //% "Enter folder path"
                placeholderText: qsTrId("folderPickerPage.enterPath")
                //% "Folder path"
                label: qsTrId("folderPickerPage.folderPath")
                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: {
                    var path = text.trim()
                    if (path.length > 0) {
                        if (!isFolderSelected(path)) {
                            toggleFolder(path)
                            folderModel.append({
                                "folderPath": path,
                                "folderName": path.split("/").pop(),
                                "isSuggested": false
                            })
                        }
                        text = ""
                        focus = false
                    }
                }
            }

            Item {
                width: 1
                height: Theme.paddingLarge
            }

            SectionHeader {
                //% "Selected Folders"
                text: qsTrId("folderPickerPage.selectedFolders")
                visible: selectedFolders.length > 0
            }

            Repeater {
                model: selectedFolders

                ListItem {
                    contentHeight: Theme.itemSizeExtraSmall
                    width: parent.width

                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.highlightColor
                        truncationMode: TruncationMode.Fade
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }
}
