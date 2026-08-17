import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page

    property var sharedByPartners: [] // Partners I share with
    property var sharedWithPartners: [] // Partners who share with me
    property var allUsers: []
    property bool loading: true

    function refresh() {
        loading = true
        immichApi.fetchPartners("shared-by")
        immichApi.fetchPartners("shared-with")
    }

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }

            MenuItem {
                //% "Add partner"
                text: qsTrId("pullDownMenu.addPartner")
                onClicked: {
                    immichApi.fetchUsers()
                }
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                //% "Partners"
                title: qsTrId("partnersPage.partners")
            }

            // Partners I share with
            SectionHeader {
                //% "Sharing with"
                text: qsTrId("partnersPage.sharingWith")
                visible: !page.loading && sharedByPartners.length > 0
            }

            Repeater {
                model: sharedByPartners

                ListItem {
                    id: sharedByItem
                    contentHeight: Theme.itemSizeMedium

                    property var partner: modelData

                    menu: ContextMenu {
                        MenuItem {
                            //% "Remove partner"
                            text: qsTrId("partnersPage.removePartner")
                            onClicked: {
                                sharedByItem.remorseAction(
                                    //% "Removing partner"
                                    qsTrId("notification.removingPartner"), function() {
                                    immichApi.removePartner(partner.id)
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
                                text: partner.name || partner.email || ""
                                color: sharedByItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                font.pixelSize: Theme.fontSizeMedium
                                truncationMode: TruncationMode.Fade
                            }

                            Label {
                                width: parent.width
                                text: partner.email || ""
                                color: sharedByItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                visible: partner.name && partner.name !== "" && partner.email !== partner.name
                                truncationMode: TruncationMode.Fade
                            }
                        }
                    }
                }
            }

            // Partners who share with me
            SectionHeader {
                //% "Shared with me"
                text: qsTrId("partnersPage.sharedWithMe")
                visible: !page.loading && sharedWithPartners.length > 0
            }

            Repeater {
                model: sharedWithPartners

                ListItem {
                    id: sharedWithItem
                    contentHeight: Theme.itemSizeMedium

                    property var partner: modelData

                    menu: ContextMenu {
                        MenuItem {
                            text: partner.inTimeline
                                //% "Hide from timeline"
                                ? qsTrId("partnersPage.hideFromTimeline")
                                //% "Show on timeline"
                                : qsTrId("partnersPage.showOnTimeline")
                            onClicked: immichApi.updatePartner(partner.id, !partner.inTimeline)
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
                                text: partner.name || partner.email || ""
                                color: sharedWithItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                font.pixelSize: Theme.fontSizeMedium
                                truncationMode: TruncationMode.Fade
                            }

                            Row {
                                spacing: Theme.paddingSmall

                                Label {
                                    text: partner.email || ""
                                    color: sharedWithItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    visible: partner.name && partner.name !== "" && partner.email !== partner.name
                                }

                                Rectangle {
                                    width: timelineLabel.width + Theme.paddingSmall * 2
                                    height: timelineLabel.height + Theme.paddingSmall
                                    radius: Theme.paddingSmall / 2
                                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                                    visible: partner.inTimeline
                                    anchors.verticalCenter: parent.verticalCenter

                                    Label {
                                        id: timelineLabel
                                        anchors.centerIn: parent
                                        //% "On timeline"
                                        text: qsTrId("partnersPage.onTimeline")
                                        font.pixelSize: Theme.fontSizeTiny
                                        color: Theme.highlightColor
                                    }
                                }
                            }
                        }
                    }

                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("PartnerAssetsPage.qml"), {
                            partnerId: partner.id,
                            partnerName: partner.name || partner.email || "",
                            inTimeline: partner.inTimeline || false
                        })
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

    // Loading
    LoadingIndicator {
        anchors.fill: flickable
        loading: page.loading && sharedByPartners.length === 0 && sharedWithPartners.length === 0
        //% "Loading partners..."
        message: qsTrId("partnersPage.loading")
    }

    // Empty state
    EmptyState {
        anchors.fill: flickable
        visible: !page.loading && sharedByPartners.length === 0 && sharedWithPartners.length === 0
        iconSource: "image://theme/icon-m-transfer"
        //% "No partners"
        message: qsTrId("peoplePage.noPartners")
        //% "Add a partner to share your photos with them"
        hint: qsTrId("partnersPage.noPartnersHint")
    }

    NotificationBanner {
        id: notification
        anchors.bottom: parent.bottom
    }

    Component.onCompleted: page.refresh()

    Connections {
        target: immichApi

        onPartnersReceived: {
            if (direction === "shared-by") {
                var byResult = []
                for (var i = 0; i < partners.length; i++) {
                    var pBy = partners[i]
                    byResult.push({
                        id: pBy.id || "",
                        name: pBy.name || "",
                        email: pBy.email || "",
                        inTimeline: pBy.inTimeline || false
                    })
                }
                page.sharedByPartners = byResult
            } else if (direction === "shared-with") {
                var withResult = []
                for (var j = 0; j < partners.length; j++) {
                    var pWith = partners[j]
                    withResult.push({
                        id: pWith.id || "",
                        name: pWith.name || "",
                        email: pWith.email || "",
                        inTimeline: pWith.inTimeline || false
                    })
                }
                page.sharedWithPartners = withResult
            }
            page.loading = false
        }

        onPartnerCreated: {
            //% "Partner added"
            notification.show(qsTrId("notification.partnerAdded"))
            page.refresh()
        }

        onPartnerRemoved: {
            //% "Partner removed"
            notification.show(qsTrId("notification.partnerRemoved"))
            page.refresh()
        }

        onPartnerUpdated: {
            //% "Partner updated"
            notification.show(qsTrId("notification.partnerUpdated"))
            page.refresh()
        }

        onUsersReceived: {
            var existingIds = {}
            for (var i = 0; i < sharedByPartners.length; i++) existingIds[sharedByPartners[i].id] = true
            var availableUsers = []
            for (var j = 0; j < users.length; j++) {
                var u = users[j]
                var uid = u.id || ""
                if (uid !== "" && uid !== authManager.userId && !existingIds[uid]) {
                    availableUsers.push({
                        id: uid,
                        name: u.name || "",
                        email: u.email || ""
                    })
                }
            }
            if (availableUsers.length === 0) {
                //% "No users available to add as partner"
                notification.show(qsTrId("notification.noUsersAvailable"))
                return
            }
            pageStack.push(addPartnerDialog, { availableUsers: availableUsers })
        }
    }

    Component {
        id: addPartnerDialog
        Page {
            property var availableUsers: []

            SilicaListView {
                anchors.fill: parent
                model: availableUsers.length

                header: PageHeader {
                    //% "Add Partner"
                    title: qsTrId("partnersPage.addPartnerTitle")
                }

                delegate: ListItem {
                    contentHeight: Theme.itemSizeMedium

                    property var user: availableUsers[index]

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

                            Label {
                                width: parent.width
                                text: user.name || user.email || ""
                                font.pixelSize: Theme.fontSizeMedium
                                truncationMode: TruncationMode.Fade
                            }

                            Label {
                                width: parent.width
                                text: user.email || ""
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: Theme.secondaryColor
                                visible: user.name && user.name !== "" && user.email !== user.name
                            }
                        }
                    }

                    onClicked: {
                        immichApi.createPartner(user.id)
                        pageStack.pop()
                    }
                }

                VerticalScrollDecorator {}
            }
        }
    }
}
