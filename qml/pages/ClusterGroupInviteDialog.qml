import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Dialog {
    id: dialog

    property string requestId: ""
    property string clusterGroupId: ""
    property var members: []
    property bool loading: true

    Component.onCompleted: immichApi.fetchClusterGroupUsers(dialog.clusterGroupId)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                //% "Decline"
                text: qsTrId("pullDownMenu.declineClusterInvitation")
                //% "Declining invitation"
                onClicked: remorse.execute(qsTrId("notification.decliningInvitation"), function() {
                    immichApi.declineClusterGroupRequest(dialog.requestId)
                    pageStack.pop()
                })
            }
        }

        Column {
            id: column
            width: parent.width

            DialogHeader {
                //% "Join"
                acceptText: qsTrId("clusterGroupInviteDialog.join")
                //% "Cluster group"
                title: qsTrId("clusterGroupInviteDialog.title")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                //% "Joining moves your people into this group so faces are recognized across all members' photos."
                text: qsTrId("clusterGroupInviteDialog.joinInfo")
                color: Theme.secondaryColor
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                //% "Members"
                text: qsTrId("clusterGroupInviteDialog.members")
            }

            Repeater {
                model: dialog.members

                ListItem {
                    contentHeight: Theme.itemSizeMedium
                    width: column.width

                    Column {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.horizontalPageMargin
                            rightMargin: Theme.horizontalPageMargin
                        }

                        Label {
                            width: parent.width
                            text: modelData.name || ""
                            truncationMode: TruncationMode.Fade
                        }

                        Label {
                            width: parent.width
                            text: modelData.email || ""
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryColor
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    LoadingIndicator {
        anchors.centerIn: parent
        visible: dialog.loading
    }

    RemorsePopup {
        id: remorse
    }

    onAccepted: immichApi.acceptClusterGroupRequest(dialog.requestId)

    Connections {
        target: immichApi
        onClusterGroupUsersReceived: {
            if (groupId !== dialog.clusterGroupId) return
            dialog.members = users
            dialog.loading = false
        }
        onErrorOccurred: dialog.loading = false
    }
}
