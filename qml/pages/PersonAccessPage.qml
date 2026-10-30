import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    backgroundColor: __silica_applicationwindow_instance.lightSurface(Theme.rgba(palette.overlayBackgroundColor, 0))
    id: page

    property string personId: ""
    property string personName: ""
    property var sharedByMe: []
    property var sharedWithMe: []

    Component.onCompleted: immichApi.fetchPersonShares()

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            backgroundColor: __silica_applicationwindow_instance.lightSurface(Theme.highlightBackgroundColor)
            MenuItem {
                //% "Add users"
                text: qsTrId("personAccessPage.addUsers")
                onClicked: {
                    var ids = []
                    for (var i = 0; i < page.sharedByMe.length; i++) {
                        ids.push(page.sharedByMe[i].id)
                    }
                    var dialog = pageStack.push(Qt.resolvedUrl("../components/UserPickerDialog.qml"), {
                        excludedIds: ids
                    })
                    dialog.accepted.connect(function() {
                        immichApi.sharePeople([page.personId], dialog.selectedUserIds)
                    })
                }
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                //% "Manage access"
                title: qsTrId("personAccessPage.title")
                description: page.personName
            }

            SectionHeader {
                //% "Sharing with"
                text: qsTrId("personAccessPage.sharedByMe")
                visible: sharedByMe.length > 0
            }

            Repeater {
                model: sharedByMe

                ListItem {
                    id: sharedByMeItem
                    contentHeight: Theme.itemSizeMedium

                    property var user: modelData

                    menu: ContextMenu {
                        backgroundColor: __silica_applicationwindow_instance.lightSurface(Theme.highlightBackgroundColor)
                        MenuItem {
                            //% "Stop sharing"
                            text: qsTrId("personAccessPage.stopSharing")
                            onClicked: {
                                sharedByMeItem.remorseAction(
                                    //% "Stop sharing"
                                    qsTrId("personAccessPage.stopSharing"), function() {
                                        immichApi.unsharePerson(page.personId, user.id)
                                })
                            }
                        }
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

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Theme.rgba(Theme.highlightBackgroundColor, 0.3)
                            }

                            Label {
                                anchors.centerIn: parent
                                text: ((user.name || user.email || "?").charAt(0)).toUpperCase()
                                font.pixelSize: Theme.fontSizeLarge
                                color: Theme.highlightColor
                            }
                        }

                        Column {
                            width: parent.width - Theme.itemSizeSmall - 2 * Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.paddingSmall / 2

                            Label {
                                width: parent.width
                                text: user.name || user.email || ""
                                color: sharedByMeItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                font.pixelSize: Theme.fontSizeMedium
                                truncationMode: TruncationMode.Fade
                            }

                            Label {
                                width: parent.width
                                text: user.email || ""
                                color: sharedByMeItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                visible: user.name && user.name !== "" && user.email !== user.name
                                truncationMode: TruncationMode.Fade
                            }
                        }
                    }
                }
            }

            SectionHeader {
                //% "Shared with me"
                text: qsTrId("personAccessPage.sharedWithMe")
                visible: sharedWithMe.length > 0
            }

            Repeater {
                model: sharedWithMe

                ListItem {
                    id: sharedWithMeItem
                    contentHeight: Theme.itemSizeMedium

                    menu: modelData.sharedBack ? null : shareBackMenu

                    property var user: modelData

                    Component {
                        id: shareBackMenu
                        ContextMenu {
                            backgroundColor: __silica_applicationwindow_instance.lightSurface(Theme.highlightBackgroundColor)
                            MenuItem {
                                //% "Share back"
                                text: qsTrId("personAccessPage.shareBack")
                                onClicked: immichApi.sharePeople([page.personId], [user.id])
                            }
                        }
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

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Theme.rgba(Theme.highlightBackgroundColor, 0.3)
                            }

                            Label {
                                anchors.centerIn: parent
                                text: ((partner.name || partner.email || "?").charAt(0)).toUpperCase()
                                font.pixelSize: Theme.fontSizeLarge
                                color: Theme.highlightColor
                            }
                        }

                        Column {
                            width: parent.width - Theme.itemSizeSmall - 2 * Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.paddingSmall / 2

                            Label {
                                width: parent.width
                                text: user.name || user.email || ""
                                color: sharedWithMeItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                font.pixelSize: Theme.fontSizeMedium
                                truncationMode: TruncationMode.Fade
                            }

                            Row {
                                spacing: Theme.paddingSmall

                                Label {
                                    text: user.email || ""
                                    color: sharedWithMeItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    visible: user.name && user.name !== "" && user.email !== user.name
                                }

                                Rectangle {
                                    width: shareBackLabel.width + Theme.paddingSmall * 2
                                    height: shareBackLabel.height + Theme.paddingSmall
                                    radius: Theme.paddingSmall / 2
                                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                                    visible: user.shareBack
                                    anchors.verticalCenter: parent.verticalCenter

                                    Label {
                                        id: shareBackLabel
                                        anchors.centerIn: parent
                                        //% "Shared back"
                                        text: qsTrId("personAccessPage.sharedBack")
                                        font.pixelSize: Theme.fontSizeTiny
                                        color: Theme.highlightColor
                                    }
                                }
                            }
                        }
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

    // Empty state
    EmptyState {
        anchors.fill: flickable
        visible: sharedByMe.length === 0 && sharedWithMe.length === 0
        iconSource: "image://theme/icon-m-people"
        //% "Not shared with anyone"
        message: qsTrId("personAccessPage.notShared")
        //% "Add a user from your cluster group to share the person with them"
        hint: qsTrId("personAccessPage.notSharedHint")
    }

    NotificationBanner {
        id: notification
        anchors.bottom: parent.bottom
    }

    Connections {
        target: immichApi
        onPersonSharesReceived: {
            var byMe = []
            var withMe = []
            for (var i = 0; i < shares.length; i++) {
                var s = shares[i]
                if (s.personId !== page.personId) continue
                if (s.sharedById === authManager.userId) {
                    byMe.push(s.sharedWith)
                } else if (s.sharedWithId === authManager.userId) {
                    withMe.push(s.sharedBy)
                }
            }
            var byMeIds = {}
            for (var j = 0; j < byMe.length; j++) {
                byMeIds[byMe[j].id] = true
            }
            for (var k = 0; k < withMe.length; k++) {
                withMe[k].sharedBack = byMeIds[withMe[k].id] === true
            }
            page.sharedByMe = byMe
            page.sharedWithMe = withMe
        }
        onPeopleShared: immichApi.fetchPersonShares()
        onPersonUnshared: immichApi.fetchPersonShares()
        onErrorOccurred: notification.showError(error)
    }
}
