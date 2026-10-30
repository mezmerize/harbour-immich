import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    backgroundColor: __silica_applicationwindow_instance.lightSurface(Theme.rgba(palette.overlayBackgroundColor, 0))
    id: picker

    property string homePath: settingsManager.homePath()
    property var allMediaRoots: [
        { name: "Pictures", path: StandardPaths.pictures, icon: "image://theme/icon-m-image" },
        { name: "Videos", path: StandardPaths.videos, icon: "image://theme/icon-m-video" },
        { name: "Camera", path: StandardPaths.pictures + "/Camera", icon: "image://theme/icon-m-camera" },
        { name: "Downloads", path: StandardPaths.download, icon: "image://theme/icon-m-cloud-download" },
        { name: "DCIM", path: homePath + "/android_storage/DCIM", icon: "image://theme/icon-m-camera" },
        { name: "Android Pictures", path: homePath + "/android_storage/Pictures", icon: "image://theme/icon-m-image" },
        { name: "Android Download", path: homePath + "/android_storage/Download", icon: "image://theme/icon-m-cloud-download" },
        { name: "Screenshots", path: homePath + "/android_storage/Pictures/Screenshots", icon: "image://theme/icon-m-screenshot" }
    ]
    property var uploadPage: null
    property var customFolderPaths: settingsManager.validCustomBrowseFolders()
    property var mediaRoots: {
        var result = []
        for (var i = 0; i < allMediaRoots.length; i++) {
            var r = allMediaRoots[i]
            if (r.path && r.path !== "" && r.path !== undefined && settingsManager.folderExists(r.path)) result.push(r)
        }
        for (var j = 0; j < customFolderPaths.length; j++) {
            var cp = customFolderPaths[j]
            result.push({ name: cp.split("/").pop(), path: cp, icon: "image://theme/icon-m-folder" })
        }
        return result
    }

    Component.onCompleted: backupManager.ensureMediaTypesFetched()

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: mediaRoots.length

        header: PageHeader {
            //% "Select folder"
            title: qsTrId("uploadPickerPage.title")
        }

        delegate: ListItem {
            property var folder: mediaRoots[index]
            property int mediaCount: 0
            property int queuedCount: 0

            function updateCount() {
                if (folder && folder.path) backupManager.requestMediaCount(folder.path)
            }

            function updateQueued() {
                queuedCount = uploadPage && folder && folder.path ? uploadPage.queuedPathsInFolder(folder.path).length : 0
            }

            Component.onCompleted: {
                updateCount()
                updateQueued()
            }

            Connections {
                target: backupManager
                onMediaTypesReadyChanged: updateCount()
                onMediaCountReady: if (folder && path === folder.path) mediaCount = count
            }

            Connections {
                target: uploadPage
                onQueueSizeChanged: updateQueued()
            }

            Icon {
                id: folderIcon
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                source: folder ? folder.icon : ""
                sourceSize.width: Theme.iconSizeMedium
                sourceSize.height: Theme.iconSizeMedium
            }

            Label {
                anchors {
                    left: folderIcon.right
                    leftMargin: Theme.paddingMedium
                    right: countLabel.left
                    rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }
                text: folder ? folder.name : ""
                truncationMode: TruncationMode.Fade
                color: highlighted ? Theme.highlightColor : Theme.primaryColor
            }

            Label {
                id: countLabel
                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: queuedCount > 0 ? queuedCount + " / " + mediaCount : mediaCount
                color: queuedCount > 0 ? Theme.highlightColor : Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
            }

            onClicked: {
                var fp = pageStack.push(Qt.resolvedUrl("DeviceFolderPage.qml"), {
                    folderPath: folder.path,
                    displayName: folder.name,
                    pickMode: true,
                    initialSelectedPaths: uploadPage ? uploadPage.queuedPathsInFolder(folder.path) : []
                })
                fp.selectionEdited.connect(function(selected, deselected) {
                    if (!uploadPage) return
                    uploadPage.addPaths(selected)
                    uploadPage.removePaths(deselected)
                })
            }
        }

        VerticalScrollDecorator {}
    }
}
