import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page

    property string homePath: settingsManager.homePath()
    property var allMediaRoots: [
        { name: "Pictures", path: StandardPaths.pictures, icon: "image://theme/icon-m-image" },
        { name: "Videos", path: StandardPaths.videos, icon: "image://theme/icon-m-video" },
        { name: "Screenshots", path: StandardPaths.pictures + "/Screenshots", icon: "image://theme/icon-m-screenshot" },
        { name: "Downloads", path: StandardPaths.download, icon: "image://theme/icon-m-cloud-download" },
        { name: "DCIM", path: homePath + "/android_storage/DCIM", icon: "image://theme/icon-m-camera" },
        { name: "Android Pictures", path: homePath + "/android_storage/Pictures", icon: "image://theme/icon-m-image" },
        { name: "Android Download", path: homePath + "/android_storage/Download", icon: "image://theme/icon-m-cloud-download" },
        { name: "Android Screenshots", path: homePath + "/android_storage/Pictures/Screenshots", icon: "image://theme/icon-m-screenshot" }
    ]
    property var customFolderPaths: settingsManager.validCustomBrowseFolders()
    property var mediaRoots: {
        var result = []
        for (var i = 0; i < allMediaRoots.length; i++) {
            var r = allMediaRoots[i]
            if (r.path && r.path !== "" && r.path !== undefined && settingsManager.folderExists(r.path)) result.push(r)
        }
        for (var j = 0; j < customFolderPaths.length; j++) {
            var cp = customFolderPaths[j]
            result.push({ name: cp.split("/").pop(), path: cp, icon: "image://theme/icon-m-folder", isCustom: true })
        }

        return result
    }

    function isFolderAlreadyListed(path) {
        for (var i = 0; i < allMediaRoots.length; i++) {
            if (allMediaRoots[i].path === path) return true
        }
        for (var j = 0; j < customFolderPaths.length; j++) {
            if (customFolderPaths[j] === path) return true
        }
        return false
    }

    signal refreshCounts()

    Component.onCompleted: backupManager.ensureMediaTypesFetched()

    onStatusChanged: {
        if (status === PageStatus.Active) refreshCounts()
    }

    Connections {
        target: settingsManager
        onCustomBrowseFoldersChanged: {
            customFolderPaths = settingsManager.validCustomBrowseFolders()
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: mediaRoots.length

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refreshCounts()
            }

            MenuItem {
                //% "Add custom folder"
                text: qsTrId("pullDownMenu.addCustomFolder")
                onClicked: {
                    var dialog = pageStack.push(addFolderDialogComponent)
                    dialog.accepted.connect(function() {
                        var path = dialog.folderPath.trim()
                        if (path.length > 0 && settingsManager.folderExists(path) && !isFolderAlreadyListed(path)) {
                            settingsManager.addCustomBrowseFolder(path)
                        }
                    })
                }
            }
        }

        header: PageHeader {
            //% "On This Device"
            title: qsTrId("onThisDevicePage.title")
        }

        delegate: ListItem {
            id: listItem
            contentHeight: Math.max(Theme.itemSizeMedium, contentColumn.implicitHeight + Theme.paddingMedium)

            property var folder: mediaRoots[index]
            property bool isCustomFolder: folder && folder.isCustom === true
            property string folderPath: folder ? folder.path : ""
            property int mediaCount: 0

            function updateCount() {
                if (folderPath) backupManager.requestMediaCount(folderPath)
            }

            Component.onCompleted: updateCount()

            Connections {
                target: page
                onRefreshCounts: listItem.updateCount()
            }

            Connections {
                target: backupManager
                onMediaTypesReadyChanged: listItem.updateCount()
                onMediaCountReady: if (path === listItem.folderPath) listItem.mediaCount = count
            }

            function removeFolder() {
                var path = folderPath
                //% "Removing folder"
                remorseAction(qsTrId("notification.removeCustomFolder"), function() {
                    settingsManager.removeCustomBrowseFolder(path)
                })
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    source: listItem.folder ? listItem.folder.icon : "image://theme/icon-m-folder"
                }

                Column {
                    id: contentColumn
                    width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall / 2

                    Label {
                        width: parent.width
                        text: listItem.folder ? listItem.folder.name : ""
                        color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        width: parent.width
                        text: listItem.folderPath
                        color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        width: parent.width
                        text: listItem.mediaCount === 1
                            //% "1 asset"
                            ? qsTrId("onThisDevicePage.asset")
                            //% "%1 assets"
                            : qsTrId("onThisDevicePage.assets").arg(listItem.mediaCount)
                        color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }

            menu: isCustomFolder ? contextMenuComponent : null

            Component {
                id: contextMenuComponent

                ContextMenu {
                    MenuItem {
                        //% "Remove folder"
                        text: qsTrId("onThisDevicePage.removeCustomFolder")
                        onClicked: listItem.removeFolder()
                    }
                }
            }

            onClicked: {
                var deviceFolderPage = pageStack.push(Qt.resolvedUrl("DeviceFolderPage.qml"), {
                    folderPath: listItem.folderPath,
                    displayName: listItem.folder ? listItem.folder.name : ""
                })
            }
        }

        VerticalScrollDecorator {}
    }

    // Empty state
    EmptyState {
        anchors.fill: listView
        visible: mediaRoots.length === 0
        iconSource: "image://theme/icon-m-phone"
        //% "No folders"
        message: qsTrId("onThisDevicePage.noFolders")
        //% "Pull down to add a custom folder"
        hint: qsTrId("onThisDevicePage.noFoldersHint")
    }

    Component {
        id: addFolderDialogComponent

        Dialog {
            property string folderPath: ""
            canAccept: folderPath.trim().length > 0

            Column {
                width: parent.width

                DialogHeader {
                    //% "Add Folder"
                    acceptText: qsTrId("onThisDevicePage.addFolderAccept")
                }

                TextField {
                    width: parent.width
                    //% "Enter folder path"
                    placeholderText: qsTrId("onThisDevicePage.folderPathPlaceholder")
                    //% "Folder path"
                    label: qsTrId("onThisDevicePage.folderPath")
                    onTextChanged: folderPath = text
                    EnterKey.iconSource: "image://theme-m-enter-accept"
                    EnterKey.onClicked: accept()
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryHighlightColor
                    //% "Enter the full path to a folder on your device. The folder must exist."
                    text: qsTrId("onThisDevicePage.addFolderDescription")
                }
            }
        }
    }
}
