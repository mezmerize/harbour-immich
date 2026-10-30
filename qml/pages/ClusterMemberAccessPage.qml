import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page

    property string userId: ""
    property string userName: ""
    property var ownPeople: []
    property var sharedIds: []
    property bool allShared: page.ownPeople.length > 0 && page.ownPeople.every(function(p) {
        return page.sharedIds.indexOf(p.id) >= 0
    })

    function personName(personId) {
        for (var i = 0; i < page.ownPeople.length; i++) {
            if (page.ownPeople[i].id === personId) {
                //% "Unnamed person"
                return page.ownPeople[i].name || qsTrId("clusterMemberAccessPage.unnamedPerson")
            }
        }
        //% "Unnamed person"
        return qsTrId("clusterMemberAccessPage.unnamedPerson")
    }

    function unsharedPeople() {
        var result = []
        for (var i = 0; i < page.ownPeople.length; i++) {
            if (page.sharedIds.indexOf(page.ownPeople[i].id) < 0) {
                result.push(page.ownPeople[i])
            }
        }
        return result
    }

    Component.onCompleted: {
        page.ownPeople = immichApi.ownPeople()
        immichApi.fetchPersonShares()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                //% "Add people"
                text: qsTrId("pullDownMenu.addPeople")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("../components/PeoplePickerDialog.qml"), {
                        model: page.unsharedPeople()
                    })
                    dialog.accepted.connect(function() {
                        if (dialog.selectedPeople.length > 0) {
                            immichApi.sharePeople(dialog.selectedPeople, [page.userId])
                        }
                    })
                }
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                //% "Person access"
                title: qsTrId("clusterMemberAccessPage.title")
                description: page.userName
            }

            TextSwitch {
                id: shareAllSwitch
                //% "Share all my people"
                text: qsTrId("clusterMemberAccessPage.shareAll")
                //% "Share every person you own with this user"
                description: qsTrId("clusterMemberAccessPage.shareAllInfo")
                checked: page.allShared
                onClicked: {
                    if (checked) {
                        immichApi.sharePeopleWithEveryone([page.userId])
                    } else {
                        immichApi.unsharePeople(page.sharedIds, page.userId)
                    }
                }
            }

            SectionHeader {
                //% "Shared people"
                text: qsTrId("clusterMemberAccessPage.sharedPeople")
            }

            Repeater {
                model: page.sharedIds

                ListItem {
                    id: sharedItem
                    contentHeight: Theme.itemSizeSmall
                    width: column.width

                    menu: ContextMenu {
                        MenuItem {
                            //% "Stop sharing"
                            text: qsTrId("clusterMemberAccessPage.stopSharing")
                            //% "Stop sharing"
                            onClicked: sharedItem.remorseAction(qsTrId("clusterMemberAccessPage.stopSharing"), function() {
                                immichApi.unsharePerson(modelData, page.userId)
                            })
                        }
                    }

                    Label {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.horizontalPageMargin
                            rightMargin: Theme.horizontalPageMargin
                        }
                        text: page.personName(modelData)
                        color: sharedItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                visible: page.sharedIds.length === 0
                //% "No people shared with this user"
                text: qsTrId("clusterMemberAccessPage.noSharedPeople")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        VerticalScrollDecorator {}
    }

    NotificationBanner {
        id: notification
        anchors.bottom: parent.bottom
    }

    Connections {
        target: immichApi
        onPersonSharesReceived: {
            var ids = []
            for (var i = 0; i < shares.length; i++) {
                var s = shares[i]
                if (s.sharedById === authManager.userId && s.sharedWithId === page.userId) {
                    ids.push(s.personId)
                }
            }
            page.sharedIds = ids
            shareAllSwitch.checked = page.allShared
        }
        onPeopleShared: immichApi.fetchPersonShares()
        onPersonUnshared: immichApi.fetchPersonShares()
        onPeopleUnshared: immichApi.fetchPersonShares()
        onErrorOccurred: {
            shareAllSwitch.checked = page.allShared
            notification.showError(error)
        }
    }
}
