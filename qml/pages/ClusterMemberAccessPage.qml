import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page

    property string userId: ""
    property string userName: ""
    property var ownPeople: []
    property var sharedIds: []
    property var peopleById: ({})
    property bool loading: false
    property bool allShared: page.ownPeople.length > 0 && page.ownPeople.every(function(p) {
        return page.sharedIds.indexOf(p.id) >= 0
    })

    function rebuildPeopleById() {
        var map = {}
        for (var i = 0; i < page.ownPeople.length; i++) {
            map[page.ownPeople[i].id] = page.ownPeople[i]
        }
        page.peopleById = map
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
        page.rebuildPeopleById()
        immichApi.fetchPersonShares()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent

        model: page.sharedIds

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

        header: Column {
            width: listView.width

            PageHeader {
                //% "Person access"
                title: qsTrId("clusterMemberAccessPage.title")
                description: page.userName
            }

            TextSwitch {
                //% "Share all my people"
                text: qsTrId("clusterMemberAccessPage.shareAll")
                //% "Share every person you own with this user"
                description: qsTrId("clusterMemberAccessPage.shareAllInfo")
                automaticCheck: false
                checked: page.allShared
                busy: page.loading
                onClicked: {
                    page.loading = true
                    if (!checked) {
                        var ids = page.unsharedPeople().map(function(p) {
                            return p.id
                        })
                        if (ids.length === 0) return
                        page.loading = true
                        immichApi.sharePeople(ids, [page.userId])
                    } else {
                        immichApi.unsharePeople(page.sharedIds, page.userId)
                    }
                }
            }

            SectionHeader {
                //% "Shared people"
                text: qsTrId("clusterMemberAccessPage.sharedPeople")
            }
        }

        delegate: ListItem {
            id: sharedItem
            contentHeight: Theme.itemSizeMedium
            width: listView.width

            property var person: page.peopleById[modelData]

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

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                PersonAvatar {
                    anchors.verticalCenter: parent.verticalCenter
                    personId: modelData
                    name: sharedItem.person ? (sharedItem.person.name || "") : ""
                    hasThumbnail: sharedItem.person ? sharedItem.person.hasThumbnail : true
                    selected: sharedItem.menuOpen
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.itemSizeSmall - Theme.paddingMedium
                    //% "Unnamed person"
                    text: person && person.name ? person.name : qsTrId("clusterMemberAccessPage.unnamedPerson")
                    color: sharedItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                }
            }
        }

        footer: Item {
            width: listView.width
            height: page.sharedIds.length === 0 ? noSharedLabel.height : 0
            visible: page.sharedIds.length === 0

            Label {
                id: noSharedLabel
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin
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
            ids.sort(function(a, b) {
                var pa = page.peopleById[a]
                var pb = page.peopleById[b]
                var na = pa && pa.name ? pa.name : ""
                var nb = pb && pb.name ? pb.name : ""
                if (na === "" || nb === "") return (na === "") - (nb === "")
                return na.localeCompare(nb)
            })
            page.sharedIds = ids
            page.loading = false
        }
        onPeopleShared: immichApi.fetchPersonShares()
        onPersonUnshared: immichApi.fetchPersonShares()
        onPeopleUnshared: immichApi.fetchPersonShares()
        onErrorOccurred: {
            page.loading = false
            notification.showError(error)
        }
    }
}
