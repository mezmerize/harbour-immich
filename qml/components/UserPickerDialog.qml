import QtQuick 2.6
import Sailfish.Silica 1.0

Dialog {
    id: userPickerDialog

    property var excludedIds: []
    property var selectedUserIds: []
    property bool loading: true
    property var users: []

    canAccept: selectedUserIds.length > 0

    Component.onCompleted: immichApi.fetchClusterGroupUsers()

    Connections {
        target: immichApi
        onClusterGroupUsersReceived: {
            var result = []
            for (var i = 0; i < users.length; i++) {
                if (userPickerDialog.excludedIds.indexOf(users[i].id) < 0) {
                    result.push(users[i])
                }
            }
            userPickerDialog.users = result
            userPickerDialog.loading = false
        }
    }

    function toggleUser(userId) {
        var ids = selectedUserIds.slice()
        var idx = ids.indexOf(userId)
        if (idx >= 0) {
            ids.splice(idx, 1)
        } else {
            ids.push(userId)
        }
        selectedUserIds = ids
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: userPickerDialog.users

        header: DialogHeader {
            //% "Share"
            acceptText: qsTrId("userPickerDialog.share")
        }

        delegate: ListItem {
            id: userItem
            contentHeight: Theme.itemSizeMedium
            width: listView.width

            property var user: modelData
            property bool isSelected: userPickerDialog.selectedUserIds.indexOf(user.id) >= 0

            onClicked: userPickerDialog.toggleUser(user.id)

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingMedium

                Item {
                    width: Theme.itemSizeSmall
                    height: Theme.itemSizeSmall
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.3)
                        border.width: userItem.isSelected ? 2 : 0
                        border.color: Theme.highlightColor
                    }

                    Icon {
                        visible: userItem.isSelected
                        source: "image://theme/icon-m-acknowledge"
                        anchors.centerIn: parent
                    }

                    Label {
                        visible: !userItem.isSelected
                        anchors.centerIn: parent
                        text: ((user.name || user.email || "?").charAt(0)).toUpperCase()
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.highlightColor
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium

                    Row {
                        width: parent.width
                        spacing: Theme.paddingSmall

                        Label {
                            text: user.name || user.email || ""
                            font.pixelSize: Theme.fontSizeMedium
                            color: userItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                            truncationMode: TruncationMode.Fade
                        }

                        Label {
                            //% "Partner"
                            text: qsTrId("userPickerDialog.partner")
                            visible: user.isPartner === true
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.highlightColor
                        }
                    }

                    Label {
                        width: parent.width
                        text: user.email || ""
                        font.pixelSize: Theme.fontSizeExtraSmall
                        visible: user.name && user.name !== "" && user.email !== user.name
                        color: Theme.secondaryColor
                        truncationMode: TruncationMode.Fade
                    }
                }
            }
        }

        footer: Item {
            width: listView.width
            property bool shown: !userPickerDialog.loading && userPickerDialog.users.length === 0
            height: shown ? Math.max(Theme.itemSizeHuge, (userPickerDialog.isPortrait ? Screen.height : Screen.width) - (listView.headerItem ? listView.headerItem.height : 0)) : 0

            EmptyState {
                anchors.fill: parent
                visible: parent.shown
                iconSource: "image://theme/icon-m-people"
                //% "No users to share with"
                message: qsTrId("userPickerDialog.empty")
                //% "People can only be shared with users in your cluster group. Set it up in the Immich web interface."
                hint: qsTrId("userPickerDialog.emptyHint")
            }
        }

        VerticalScrollDecorator {}
    }

    LoadingIndicator {
        anchors.fill: listView
        loading: page.loading
        //% "Loading users..."
        message: qsTrId("userPickerDialog.loading")
    }
}
