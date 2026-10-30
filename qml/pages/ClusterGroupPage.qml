import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page

    property var members: []
    property var sentRequests: []
    property var receivedRequests: []
    property var usersById: ({})
    property bool loading: true

    function refresh() {
        page.loading = true
        var map = {}
        var users = immichApi.catalogUsers()
        for (var i = 0; i < users.length; i++) {
            map[users[i].id] = users[i]
        }
        page.usersById = map
        immichApi.fetchClusterGroupUsers()
        immichApi.fetchClusterGroupSentRequests()
        immichApi.fetchClusterGroupRequests()
    }

    Component.onCompleted: page.refresh()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }

            MenuItem {
                //% "Leave group"
                text: qsTrId("pullDownMenu.leaveClusterGroup")
                visible: page.members.length > 0
                onClicked: pageStack.push(leaveDialogComponent)
            }

            MenuItem {
                //% "Reset facial recognition"
                text: qsTrId("pullDownMenu.resetFacialRecognition")
                onClicked: pageStack.push(resetDialogComponent)
            }

            MenuItem {
                //% "Invite users"
                text: qsTrId("pullDownMenu.inviteClusterUsers")
                onClicked: {
                    var excluded = []
                    for (var i = 0; i < page.members.length; i++) {
                        excluded.push(page.members[i].id)
                    }
                    for (var j = 0; j < page.sentRequests.length; j++) {
                        excluded.push(page.sentRequests[j].userId)
                    }
                    var dialog = pageStack.push(Qt.resolvedUrl("../components/UserPickerDialog.qml"), {
                        sourceUsers: immichApi.catalogUsers(),
                        excludedIds: excluded,
                        //% "Invite"
                        acceptText: qsTrId("clusterGroupPage.invite"),
                        //% "No users to invite"
                        emptyText: qsTrId("clusterGroupPage.noUsersToInvite"),
                        //% "All users are already members or invited"
                        emptyHint: qsTrId("clusterGroupPage.allMembersOrInvited")
                    })
                    dialog.accepted.connect(function() {
                        immichApi.inviteToClusterGroup(dialog.selectedUserIds)
                    })
                }
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                //% "Cluster group"
                title: qsTrId("clusterGroupPage.title")
            }

            SectionHeader {
                //% "Members"
                text: qsTrId("clusterGroupPage.members")
            }

            Item {
                height: Theme.itemSizeMedium
                width: column.width

                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Theme.horizontalPageMargin
                        rightMargin: Theme.horizontalPageMargin
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.paddingSmall

                        Label {
                            text: immichApi.currentUserName() || authManager.email
                            truncationMode: TruncationMode.Fade
                        }

                        Label {
                            //% "(you)"
                            text: qsTrId("clusterGroupPage.you")
                            color: Theme.highlightColor
                        }
                    }

                    Label {
                        width: parent.width
                        text: authManager.email
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        truncationMode: TruncationMode.Fade
                    }
                }
            }

            Repeater {
                model: page.members

                ListItem {
                    id: memberItem
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
                            color: memberItem.highlighted ? Theme.highlightColor : Theme.primaryColor
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

                    onClicked: pageStack.push(Qt.resolvedUrl("ClusterMemberAccessPage.qml"), {
                        userId: modelData.id,
                        userName: modelData.name || modelData.email || modelData.id
                    })
                }
            }

            SectionHeader {
                //% "Invitations"
                text: qsTrId("clusterGroupPage.invitations")
                visible: page.receivedRequests.length > 0
            }

            Repeater {
                model: page.receivedRequests

                ListItem {
                    id: inviteItem
                    contentHeight: Theme.itemSizeMedium
                    width: column.width

                    menu: ContextMenu {
                        MenuItem {
                            //% "Accept"
                            text: qsTrId("clusterGroupPage.accept")
                            onClicked: immichApi.acceptClusterGroupRequest(modelData.id)
                        }

                        MenuItem {
                            //% "Decline"
                            text: qsTrId("clusterGroupPage.decline")
                            //% "Declining invitation"
                            onClicked: inviteItem.remorseAction(qsTrId("notification.decliningInvitation"), function() {
                                immichApi.declineClusterGroupRequest(modelData.id)
                            })
                        }
                    }

                    onClicked: pageStack.push(Qt.resolvedUrl("ClusterGroupInviteDialog.qml"), {
                        requestId: modelData.id,
                        clusterGroupId: modelData.clusterGroupId
                    })

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
                            //% "You have been invited to join a cluster group"
                            text: qsTrId("clusterGroupPage.invitedInfo")
                            color: inviteItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                            truncationMode: TruncationMode.Fade
                        }

                        Label {
                            width: parent.width
                            text: Qt.formatDate(new Date(modelData.createdAt), "dd MMM yyyy")
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryColor
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }
            }

            SectionHeader {
                //% "Pending invitations"
                text: qsTrId("clusterGroupPage.pendingInvitations")
                visible: page.sentRequests.length > 0
            }

            Repeater {
                model: page.sentRequests

                ListItem {
                    id: sentItem
                    contentHeight: Theme.itemSizeMedium
                    width: column.width

                    property var invitedUser: page.usersById[modelData.userId]

                    menu: ContextMenu {
                        MenuItem {
                            //% "Cancel invitation"
                            text: qsTrId("clusterGroupPage.cancelInvitation")
                            //% "Cancelling invitation"
                            onClicked: sentItem.remorseAction(qsTrId("notification.cancellingInvitation"), function() {
                                immichApi.declineClusterGroupRequest(modelData.id)
                            })
                        }
                    }

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
                            text: sentItem.invitedUser ? (sentItem.invitedUser.name || "") : modelData.userId
                            color: sentItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                            truncationMode: TruncationMode.Fade
                        }

                        Label {
                            width: parent.width
                            text: sentItem.invitedUser ? (sentItem.invitedUser.email || "") : ""
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
        loading: page.loading
        //% "Loading cluster group..."
        message: qsTrId("clusterGroupPage.loading")
    }

    NotificationBanner {
        id: notification
        anchors.bottom: parent.bottom
    }

    RemorsePopup {
        id: remorse
    }

    Component {
        id: resetDialogComponent

        Dialog {
            canAccept: true

            Column {
                width: parent.width

                DialogHeader {
                    //% "Reset"
                    acceptText: qsTrId("clusterGroupPage.reset")
                    //% "Reset facial recognition"
                    title: qsTrId("clusterGroupPage.resetFacialRecognition")
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    //% "Resetting facial recognition will delete all people for all users in this group. Already set names and birth dates will be lost. Are you sure you want to continue?"
                    text: qsTrId("clusterGroupPage.resetFacialRecognitionWarning")
                    color: Theme.highlightColor
                    wrapMode: Text.WordWrap
                }
            }

            //% "Queuing facial recognition reset"
            onAccepted: remorse.execute(qsTrId("notification.queuingFacialRecognitionReset"), function() {
                immichApi.regenerateClusterGroupPeople()
            })
        }
    }

    Component {
        id: leaveDialogComponent

        Dialog {
            canAccept: true

            Column {
                width: parent.width

                DialogHeader {
                    //% "Leave group"
                    acceptText: qsTrId("clusterGroupPage.leaveGroup")
                    //% "Leave group"
                    title: qsTrId("clusterGroupPage.leaveGroup")
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    //% "Your people will no longer be recognized together with the other members. You will be moved to a new group of your own."
                    text: qsTrId("clusterGroupPage.leaveGroupWarning")
                    color: Theme.highlightColor
                    wrapMode: Text.WordWrap
                }
            }

            //% "Leaving cluster group"
            onAccepted: remorse.execute(qsTrId("notification.leavingClusterGroup"), function() {
                immichApi.leaveClusterGroup()
            })
        }
    }

    Connections {
        target: authManager
        onClusterGroupIdChanged: page.refresh()
    }

    Connections {
        target: immichApi
        onClusterGroupUsersReceived: {
            if (groupId !== authManager.clusterGroupId) return
            page.members = users
            page.loading = false
        }
        onClusterGroupSentRequestsReceived: {
            page.sentRequests = requests
        }
        onClusterGroupRequestsReceived: {
            page.receivedRequests = requests
        }
        onClusterGroupInvitesSent: page.refresh()
        onClusterGroupRequestDeleted: page.refresh()
        onClusterGroupJoined: {
            //% "Joined cluster group"
            notification.show(qsTrId("notification.clusterGroupJoined"))
            page.refresh()
        }
        onClusterGroupLeft: {
            //% "Left cluster group"
            notification.show(qsTrId("notification.clusterGroupLeft"))
            page.refresh()
        }
        onClusterGroupPeopleRegenerated: {
            //% "Facial recognition reset queued"
            notification.show(qsTrId("notification.clusterGroupPeopleRegenerated"))
            page.refresh()
        }
        onErrorOccurred: {
            page.loading = false
            notification.showError(error)
        }
    }
}
