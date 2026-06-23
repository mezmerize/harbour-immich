import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page

    property string currentPath: ""
    property string displayName: ""
    property var allPaths: []
    property var folderItems: []
    property bool loading: true
    property bool waitingForPaths: false

    function refresh() {
        loading = true
        if (currentPath === "") {
            currentPath = "/"
        }
        if (allPaths.length > 0) {
            buildFolderItems()
            immichApi.fetchServerFolders(currentPath)
        } else {
            waitingForPaths = true
            immichApi.fetchUniqueFolderPaths()
        }
    }

    function countImmediateSubfolders(folderPath) {
        var prefix = folderPath
        if (prefix.charAt(prefix.length - 1) !== "/") prefix = prefix + "/"
        var children = {}
        for (var i = 0; i < allPaths.length; i++) {
            var p = String(allPaths[i])
            if (p.indexOf(prefix) === 0) {
                var remainder = p.substring(prefix.length)
                if (remainder === "") continue
                var slashIdx = remainder.indexOf("/")
                var childName = slashIdx === -1 ? remainder : remainder.substring(0, slashIdx)
                if (childName !== "") children[childName] = true
            }
        }
        return Object.keys(children).length
    }

    function buildFolderItems() {
        var subfolders = {}
        var prefix = currentPath
        if (prefix.charAt(prefix.length - 1) !== "/") {
            prefix = prefix + "/"
        }
        for (var i = 0; i < allPaths.length; i++) {
            var p = String(allPaths[i])
            if (p.indexOf(prefix) === 0) {
                var remainder = p.substring(prefix.length)
                if (remainder === "") continue
                var slashIdx = remainder.indexOf("/")
                var childName = slashIdx === -1 ? remainder : remainder.substring(0, slashIdx)
                if (childName !== "" && !subfolders[childName]) {
                    var childPath = prefix + childName
                    subfolders[childName] = { isAsset: false, name: childName, path: childPath, subfolderCount: countImmediateSubfolders(childPath) }
                }
            }
        }
        var result = []
        var names = Object.keys(subfolders).sort()
        for (var j = 0; j < names.length; j++) {
            result.push(subfolders[names[j]])
        }
        folderItems = result
    }

    function navigateToFolder(path, name) {
        pageStack.push(Qt.resolvedUrl("FoldersPage.qml"), {
            currentPath: path,
            displayName: name,
            allPaths: page.allPaths
        })
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: folderItems.length

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }
        }

        header: PageHeader {
            //% "Folders"
            title: displayName !== "" ? displayName : qsTrId("foldersPage.folders")
        }

        delegate: ListItem {
            id: listItem
            contentHeight: Theme.itemSizeMedium

            property var item: page.folderItems[index]

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
                        id: folderThumbnail
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: item.isAsset && item.id
                        source: visible ? "image://immich/thumbnail/" + item.id : ""

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                            visible: folderThumbnail.visible && folderThumbnail.status !== Image.Ready
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: !item.isAsset || !item.id
                        source: "image://theme/icon-m-folder"
                    }
                }

                Column {
                    width: parent.width - Theme.itemSizeSmall - 2 * Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall / 2

                    Label {
                        width: parent.width
                        text: item.name || ""
                        color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        width: parent.width
                        visible: text !== ""
                        text: {
                            if (!item.isAsset) {
                                var n = item.subfolderCount || 0
                                if (n === 0) return ""
                                return n === 1
                                    //% "1 folder"
                                    ? qsTrId("foldersPage.folderNumber")
                                    //% "%1 folders"
                                    : qsTrId("foldersPage.foldersNumber").arg(n)
                            }
                            var parts = []
                            if (item.fileSize) {
                                var size = item.fileSize
                                if (size > 1048576) parts.push((size / 1048576).toFixed(1) + " MB")
                                else if (size > 1024) parts.push((size / 1024).toFixed(0) + " KB")
                                else parts.push(size + " B")
                            }
                            if (item.fileCreatedAt) parts.push(item.fileCreatedAt)
                            return parts.join(" · ")
                        }
                        color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }

            onClicked: {
                if (item.isAsset) {
                    pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                        assetId: item.id,
                        isFavorite: item.isFavorite || false,
                        isVideo: item.isVideo || false,
                        thumbhash: item.thumbhash || ""
                    })
                } else {
                    page.navigateToFolder(item.path, item.name)
                }
            }
        }

        VerticalScrollDecorator {}
    }

    LoadingIndicator {
        anchors.fill: listView
        loading: page.loading && folderItems.length === 0
        //% "Loading folders..."
        message: qsTrId("foldersPage.loading")
    }

    EmptyState {
        anchors.fill: listView
        visible: !page.loading && folderItems.length === 0
        iconSource: "image://theme/icon-m-folder"
        //% "No items in this folder"
        message: qsTrId("foldersPage.empty")
    }

    Component.onCompleted: page.refresh()

    Connections {
        target: immichApi
        onUniqueFolderPathsReceived: {
            if (!page.waitingForPaths) return
            page.waitingForPaths = false
            page.allPaths = []
            for (var i = 0; i < paths.length; i++) {
                page.allPaths.push(String(paths[i]))
            }
            page.buildFolderItems()
            immichApi.fetchServerFolders(page.currentPath)
        }
        onServerFoldersReceived: {
            if (path !== page.currentPath) return
            var result = []
            // Keep existing subfolders
            for (var i = 0; i < page.folderItems.length; i++) {
                if (!page.folderItems[i].isAsset) {
                    result.push(page.folderItems[i])
                }
            }
            // Add assets from API response
            for (var j = 0; j < items.length; j++) {
                var item = items[j]
                if (item.id) {
                    var fileDate = ""
                    if (item.fileCreatedAt) {
                        var d = new Date(item.fileCreatedAt)
                        fileDate = d.toLocaleDateString()
                    }
                    result.push({
                        isAsset: true,
                        id: item.id || "",
                        name: item.originalFileName || item.originalPath || "",
                        isFavorite: item.isFavorite || false,
                        isVideo: item.type === "VIDEO",
                        thumbhash: item.thumbhash || "",
                        duration: item.duration || "",
                        fileSize: item.exifInfo ? (item.exifInfo.fileSizeInByte || 0) : 0,
                        fileCreatedAt: fileDate
                    })
                }
            }
            page.folderItems = result
            page.loading = false
        }
    }
}
