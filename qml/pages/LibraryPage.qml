import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                //% "Settings"
                text: qsTrId("libraryPage.settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }

            MenuItem {
                //% "Search"
                text: qsTrId("libraryPage.search")
                onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
            }

            MenuItem {
                //% "Albums"
                text: qsTrId("libraryPage.albums")
                onClicked: pageStack.push(Qt.resolvedUrl("AlbumsPage.qml"))
            }

            MenuItem {
                //% "Timeline"
                text: qsTrId("libraryPage.timeline")
                onClicked: pageStack.replaceAbove(null, Qt.resolvedUrl("TimelinePage.qml"))
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                //% "Library"
                title: qsTrId("libraryPage.library")
            }

            // Library items grid
            Grid {
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                columns: 2
                spacing: Theme.paddingMedium

                Repeater {
                    model: [
                        //% "Archived"
                        { title: qsTrId("libraryPage.archived"), icon: "image://theme/icon-m-file-archive-folder", page: "ArchivedPage.qml" },
                        //% "Shared Links"
                        { title: qsTrId("libraryPage.sharedLinks"), icon: "image://theme/icon-m-link", page: "SharedLinksPage.qml" },
                        //% "Trash"
                        { title: qsTrId("libraryPage.trash"), icon: "image://theme/icon-m-delete", page: "TrashPage.qml" },
                        //% "People"
                        { title: qsTrId("libraryPage.people"), icon: "image://theme/icon-m-people", page: "PeoplePage.qml" },
                        //% "Places"
                        { title: qsTrId("libraryPage.places"), icon: "image://theme/icon-m-location", page: "PlacesPage.qml" },
                        //% "On This Device"
                        { title: qsTrId("libraryPage.onThisDevice"), icon: "image://theme/icon-m-phone", page: "OnThisDevicePage.qml" },
                        //% "Folders"
                        { title: qsTrId("libraryPage.folders"), icon: "image://theme/icon-m-folder", page: "FoldersPage.qml" },
                        //% "Locked Folder"
                        { title: qsTrId("libraryPage.lockedFolder"), icon: "image://theme/icon-m-device-lock", page: "LockedFolderPage.qml" },
                        //% "Partners"
                        { title: qsTrId("libraryPage.partners"), icon: "image://theme/icon-m-transfer", page: "PartnersPage.qml" }
                    ]

                    BackgroundItem {
                        width: (column.width - 2 * Theme.horizontalPageMargin - Theme.paddingMedium) / 2
                        height: Theme.itemSizeLarge * 1.2

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.paddingMedium
                            color: parent.highlighted ? Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity) : Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.paddingSmall

                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                source: modelData.icon
                                color: parent.parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                            }

                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.title
                                font.pixelSize: Theme.fontSizeSmall
                                color: parent.parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                                horizontalAlignment: Text.AlignHCenter
                                width: parent.parent.width - 2 * Theme.paddingMedium
                                truncationMode: TruncationMode.Fade
                            }
                        }

                        onClicked: pageStack.push(Qt.resolvedUrl(modelData.page))
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
