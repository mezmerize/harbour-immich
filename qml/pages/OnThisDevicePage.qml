import QtQuick 2.0
import Sailfish.Silica 1.0
import Qt.labs.folderlistmodel 2.1
import "../components"

Page {
    id: page

    property string browsingFolder: ""
    property string displayName: ""

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

    property bool showingRoots: browsingFolder === ""
    property bool folderValid: showingRoots || (folderModel.folder.toString() === "file://" + browsingFolder)

    property var videoExtensions: []
    property var mediaFilters: []

    // Fallback filters used when server media types not available
    property var fallbackFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.heic", "*.heif", "*.webp", "*.mp4", "*.mov", "*.avi", "*.mkv", "*.webm", "*.JPG", "*.JPEG", "*.PNG", "*.GIF", "*.HEIC", "*.HEIF", "*.WEBP", "*.MP4", "*.MOV", "*.AVI", "*.MKV", "*.WEBM"]

    function isFolderAlreadyListed(path) {
        for (var i = 0; i < allMediaRoots.length; i++) {
            if (allMediaRoots[i].path === path) return true
        }
        for (var j = 0; j < customFolderPaths.length; j++) {
            if (customFolderPaths[j] === path) return true
        }
        return false
    }

    function buildNameFilters() {
        var photoExts = backupManager.supportedPhotoExtensions()
        var videoExts = backupManager.supportedVideoExtensions()
        videoExtensions = []
        var filters = []
        for (var p = 0; p < photoExts.length; p++) {
            var pext = String(photoExts[p])
            filters.push("*." + pext)
            filters.push("*." + pext.toUpperCase())
        }
        for (var v = 0; v < videoExts.length; v++) {
            var vext = String(videoExts[v])
            filters.push("*." + vext)
            filters.push("*." + vext.toUpperCase())
        }
        if (filters.length === 0) {
            filters = fallbackFilters
        }
        mediaFilters = filters
        folderModel.nameFilters = filters
    }

    function isVideoFile(fileName) {
        var ext = fileName.substring(fileName.lastIndexOf(".") + 1).toLowerCase()
        return videoExtensions.indexOf(ext) !== -1
    }

    Connections {
        target: backupManager
        onMediaTypesReadyChanged: page.buildNameFilters()
    }

    Connections {
        target: settingsManager
        onCustomBrowseFoldersChanged: {
            customFolderPaths = settingsManager.validCustomBrowseFolders()
        }
    }

    Component.onCompleted: buildNameFilters()

    FolderListModel {
        id: folderModel
        folder: showingRoots ? "" : "file://" + browsingFolder
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        nameFilters: page.mediaFilters.length > 0 ? page.mediaFilters : page.fallbackFilters
        sortField: FolderListModel.Name
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: showingRoots ? mediaRoots.length : (folderValid ? folderModel.count : 0)

        PullDownMenu {
            visible: showingRoots
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
            title: showingRoots ? qsTrId("onThisDevicePage.title") : displayName
        }

        delegate: ListItem {
            id: listItem
            contentHeight: Theme.itemSizeMedium

            property bool isDir: !showingRoots && folderModel.isFolder(index)
            property bool isCustomFolder: showingRoots && mediaRoots[index] && mediaRoots[index].isCustom === true
            property string customFolderPath: isCustomFolder ? mediaRoots[index].path : ""

            function removeFolder() {
                var path = customFolderPath
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

                Item {
                    width: Theme.itemSizeSmall
                    height: Theme.itemSizeSmall
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: itemThumbnail
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: width
                        sourceSize.height: height
                        visible: !showingRoots && !listItem.isDir
                        source: visible ? "file://" + folderModel.get(index, "filePath") : ""

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                            visible: itemThumbnail.status !== Image.Ready && itemThumbnail.visible
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: showingRoots || listItem.isDir || itemThumbnail.status !== Image.Ready
                        source: {
                            if (showingRoots) return mediaRoots[index].icon
                            if (listItem.isDir) return "image://theme/icon-m-folder"
                            return "image://theme/icon-m-image"
                        }
                    }
                }

                Column {
                    width: parent.width - Theme.itemSizeSmall - 2 * Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall / 2

                    Label {
                        width: parent.width
                        text: showingRoots ? mediaRoots[index].name : folderModel.get(index, "fileName")
                        color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        width: parent.width
                        visible: showingRoots
                        text: mediaRoots[index] ? mediaRoots[index].path : ""
                        color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                    }

                    Row {
                        width: parent.width
                        visible: !showingRoots && !listItem.isDir

                        Label {
                            width: parent.width / 2
                            text: {
                                var size = folderModel.get(index, "fileSize")
                                if (size > 1048576) return (size / 1048576).toFixed(1) + " MB"
                                if (size > 1024) return (size / 1024).toFixed(0) + " KB"
                                return size + " B"
                            }
                            color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                        }

                        Label {
                            width: parent.width / 2
                            horizontalAlignment: Text.AlignRight
                            text: {
                                var modified = folderModel.get(index, "fileModified")
                                return modified ? Qt.formatDateTime(modified, "yyyy-MM-dd hh:mm") : ""
                            }
                            color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                        }
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
                if (showingRoots) {
                    var mediaRoot = mediaRoots[index]
                    if (!mediaRoot) return
                    pageStack.push(Qt.resolvedUrl("OnThisDevicePage.qml"), {
                        browsingFolder: mediaRoot.path,
                        displayName: mediaRoot.name
                    })
                } else if (listItem.isDir) {
                    var folderName = folderModel.get(index, "fileName")
                    pageStack.push(Qt.resolvedUrl("OnThisDevicePage.qml"), {
                        browsingFolder: browsingFolder + "/" + folderName,
                        displayName: folderName
                    })
                } else {
                    var filePath = folderModel.get(index, "filePath")
                    Qt.openUrlExternally("file://" + filePath)
                }
            }
        }

        // Empty state
        EmptyState {
            anchors.centerIn: parent
            visible: !showingRoots && (folderModel.count === 0 || !folderValid) && folderModel.status === FolderListModel.Ready
            iconSource: "image://theme/icon-m-phone"
            //% "No media files in this folder"
            message: qsTrId("onThisDevicePage.empty")
        }

        VerticalScrollDecorator {}
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
