import QtQuick 2.0
import Sailfish.Silica 1.0
import QtFeedback 5.0

Item {
    id: actionBar
    width: parent.width
    height: contentHeight + menuContainer.height
    visible: shown || slideTransform.y < contentHeight
    transform: Translate {
        id: slideTransform
        y: shown ? 0 : contentHeight
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
    }

    property real contentHeight: Theme.itemSizeLarge
    property int selectedCount: 0
    property bool shown: selectedCount > 0
    property bool hasAnyFavorites: false
    property bool allAreFavorites: false
    property bool canStack: false
    property string activeMenuType: ""

    // Page context flags
    property bool showArchive: false
    property bool isArchivePage: false
    property bool isTrashPage: false
    property bool isLockedFolderPage: false

    signal addToFavorites()
    signal removeFromFavorites()
    signal share()
    signal addToAlbum()
    signal stackSelected()
    signal clearSelection()
    signal download()
    signal deleteSelected()
    signal moveToArchive()
    signal removeFromArchive()
    signal moveToLockedFolder()
    signal removeFromLockedFolder()
    signal restoreFromTrash()

    function showContextMenu(menuType) {
        if (activeMenuType === menuType) {
            activeMenuType = ""
        } else {
            activeMenuType = menuType
        }
    }

    onShownChanged: {
        if (!shown) activeMenuType = ""
    }

    ThemeEffect {
        id: actionFeedback
        effect: ThemeEffect.Press
    }

    // Dim background
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.top
        height: Screen.height
        color: Theme.rgba("black", 0.4)

        opacity: activeMenuType !== "" ? 1.0 : 0.0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 150 } }

        MouseArea {
            anchors.fill: parent
            onClicked: activeMenuType = ""
        }
    }

    // Bar background
    Rectangle {
        id: barBackground
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: contentHeight
        color: Theme.rgba(Theme.highlightDimmerColor, 0.95)
        z: 2

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.rgba(Theme.highlightColor, 0.3)
        }
    }

    // Selection label
    Label {
        anchors.top: parent.top
        anchors.topMargin: Theme.paddingSmall
        anchors.horizontalCenter: parent.horizontalCenter
        //% "%1 selected"
        text: qsTrId("selectionActionBar.selected").arg(selectedCount)
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.highlightColor
        visible: selectedCount > 0
        z: 3
    }

    // Buttons - trash folder mode
    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: contentHeight
        anchors.leftMargin: Theme.horizontalPageMargin
        anchors.rightMargin: Theme.horizontalPageMargin
        z: 3
        visible: isTrashPage

        IconButton {
            width: parent.width / 3
            height: parent.height
            icon.source: "image://theme/icon-m-backup"

            onClicked: {
                actionFeedback.play()
                restoreFromTrash()
            }
        }

        IconButton {
            width: parent.width / 3
            height: parent.height
            icon.source: "image://theme/icon-m-delete"

            onClicked: {
                actionFeedback.play()
                deleteSelected()
            }
        }

        IconButton {
            width: parent.width / 3
            height: parent.height
            icon.source: "image://theme/icon-m-dismiss"

            onClicked: {
                actionFeedback.play()
                clearSelection()
            }
        }
    }

    // Buttons - locked folder mode
    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: contentHeight
        anchors.leftMargin: Theme.horizontalPageMargin
        anchors.rightMargin: Theme.horizontalPageMargin
        z: 3
        visible: isLockedFolderPage

        IconButton {
            width: parent.width / 4
            height: parent.height
            icon.source: "image://theme/icon-m-cloud-download"

            onClicked: {
                actionFeedback.play()
                download()
            }
        }

        IconButton {
            width: parent.width / 4
            height: parent.height
            icon.source: "image://theme/icon-m-delete"

            onClicked: {
                actionFeedback.play()
                deleteSelected()
            }
        }

        IconButton {
            width: parent.width / 4
            height: parent.height
            icon.source: "image://theme/icon-m-device-lock"

            onClicked: {
                actionFeedback.play()
                removeFromLockedFolder()
            }
        }

        IconButton {
            width: parent.width / 4
            height: parent.height
            icon.source: "image://theme/icon-m-dismiss"

            onClicked: {
                actionFeedback.play()
                clearSelection()
            }
        }
    }

    // Buttons - normal mode
    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: contentHeight
        anchors.leftMargin: Theme.horizontalPageMargin
        anchors.rightMargin: Theme.horizontalPageMargin
        z: 3
        visible: !isTrashPage && !isLockedFolderPage

        IconButton {
            width: parent.width / 4
            height: parent.height
            icon.source: allAreFavorites ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"

            onClicked: {
                actionFeedback.play()
                if (allAreFavorites) {
                    removeFromFavorites()
                } else {
                    addToFavorites()
                }
            }
        }

        IconButton {
            width: parent.width / 4
            height: parent.height
            icon.source: "image://theme/icon-m-share"

            onClicked: {
                actionFeedback.play()
                share()
            }
        }

        IconButton {
            width: parent.width / 4
            height: parent.height
            icon.source: "image://theme/icon-m-add?" + (activeMenuType === "add" ? Theme.highlightColor : Theme.primaryColor)

            onClicked: {
                actionFeedback.play()
                showContextMenu("add")
            }
        }

        IconButton {
            width: parent.width / 4
            height: parent.height
            icon.source: "image://theme/icon-m-other?" + (activeMenuType === "more" ? Theme.highlightColor : Theme.primaryColor)

            onClicked: {
                actionFeedback.play()
                showContextMenu("more")
            }
        }
    }

    Item {
        id: menuContainer
        anchors.top: barBackground.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: visibleMenu ? menuColumn.implicitHeight : 0
        clip: true
        z: 2

        property bool visibleMenu: activeMenuType !== ""

        Behavior on height {
            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
        }

        Column {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: activeMenuType === "add" && showArchive && !isArchivePage
                highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

                Label {
                    anchors.centerIn: parent
                    //% "Move to archive"
                    text: qsTrId("selectionActionBar.moveToArchive")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                onClicked: {
                    activeMenuType = ""
                    moveToArchive()
                }
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: activeMenuType === "add" && !isLockedFolderPage && showArchive
                highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

                Label {
                    anchors.centerIn: parent
                    //% "Move to locked folder"
                    text: qsTrId("selectionActionBar.moveToLockedFolder")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                onClicked: {
                    activeMenuType = ""
                    moveToLockedFolder()
                }
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: activeMenuType === "add"
                highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

                Label {
                    anchors.centerIn: parent
                    //% "Add to album"
                    text: qsTrId("selectionActionBar.addToAlbum")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                onClicked: {
                    activeMenuType = ""
                    addToAlbum()
                }
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: activeMenuType === "add" && canStack
                highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

                Label {
                    anchors.centerIn: parent
                    //% "Stack"
                    text: qsTrId("selectionActionBar.stack")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                onClicked: {
                    activeMenuType = ""
                    stackSelected()
                }
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: activeMenuType === "more" && isArchivePage
                highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

                Label {
                    anchors.centerIn: parent
                    //% "Remove from archive"
                    text: qsTrId("selectionActionBar.removeFromArchive")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                onClicked: {
                    activeMenuType = ""
                    removeFromArchive()
                }
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: activeMenuType === "more" && isLockedFolderPage
                highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

                Label {
                    anchors.centerIn: parent
                    //% "Remove from locked folder"
                    text: qsTrId("selectionActionBar.removeFromLockedFolder")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                onClicked: {
                    activeMenuType = ""
                    removeFromLockedFolder()
                }
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: activeMenuType === "more"
                highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

                Label {
                    anchors.centerIn: parent
                    //% "Clear selection"
                    text: qsTrId("selectionActionBar.clear")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                onClicked: {
                    activeMenuType = ""
                    clearSelection()
                }
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: activeMenuType === "more"
                highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

                Label {
                    anchors.centerIn: parent
                    //% "Download"
                    text: qsTrId("selectionActionBar.download")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                onClicked: {
                    activeMenuType = ""
                    download()
                }
            }

            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: activeMenuType === "more"
                highlightedColor: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

                Label {
                    anchors.centerIn: parent
                    //% "Delete"
                    text: qsTrId("selectionActionBar.delete")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                onClicked: {
                    activeMenuType = ""
                    deleteSelected()
                }
            }
        }
    }
}
