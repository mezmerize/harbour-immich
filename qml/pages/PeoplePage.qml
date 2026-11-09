import QtQuick 2.6
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"

Page {
    id: page

    property bool loading: true
    property bool showHidden: false

    PeopleModel {
        id: peopleModel
    }

    Connections {
        target: syncEngine
        onSyncFinished: if (ok) page.refresh()
    }

    function refresh() {
        loading = true
        immichApi.fetchPeople(showHidden)
        immichApi.fetchPersonShares()
    }

    SilicaGridView {
        id: peopleGrid
        anchors.fill: parent
        clip: true
        currentIndex: -1
        cellWidth: width / (page.isPortrait ? 3 : 6)
        cellHeight: cellWidth + Theme.fontSizeExtraSmall + Theme.paddingMedium
        cacheBuffer: Math.round(cellHeight * 3)

        model: peopleModel

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: syncEngine.sync()
            }

            MenuItem {
                text: page.showHidden
                    //% "Hide hidden people"
                    ? qsTrId("pullDownMenu.hideHidden")
                    //% "Show hidden people"
                    : qsTrId("pullDownMenu.showHidden")
                onClicked: {
                    page.showHidden = !page.showHidden
                    page.refresh()
                }
            }
        }

        header: Column {
            id: headerColumn
            width: peopleGrid.width

            PageHeader {
                //% "People"
                title: qsTrId("peoplePage.people")
            }

            FilterBar {
                width: parent.width
                activeFilter: peopleModel.activeFilter
                sortOrder: peopleModel.sortAscending ? "asc" : "desc"
                showFavorites: peopleModel.showFavorites
                filterModel: [
                    //% "Name"
                    { id: "name", label: qsTrId("filterBar.name"), icon: "image://theme/icon-m-people" },
                    //% "Updated"
                    { id: "updatedAt", label: qsTrId("filterBar.updated"), icon: "image://theme/icon-m-time" }
                ]
                onFilterActivated: peopleModel.activeFilter = filter
                onFilterFavorites: peopleModel.showFavorites = showFavorites
                onSortOrderToggled: peopleModel.sortAscending = (order === "asc")
            }

            SearchField {
                width: parent.width
                //% "Filter by name..."
                placeholderText: qsTrId("peoplePage.filter")
                onTextChanged: peopleModel.filterText = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            Item {
                width: parent.width
                height: Theme.paddingSmall
            }
        }

        delegate: BackgroundItem {
            id: personDelegate
            width: peopleGrid.cellWidth
            height: peopleGrid.cellHeight
            z: personContextMenu.active ? 10 : 0

            property real thumbnailSize: peopleGrid.cellWidth - Theme.paddingMedium

            Column {
                anchors.top: parent.top
                anchors.topMargin: Theme.paddingSmall / 2
                width: parent.width
                spacing: Theme.paddingSmall

                Item {
                    width: personDelegate.thumbnailSize
                    height: personDelegate.thumbnailSize
                    anchors.horizontalCenter: parent.horizontalCenter

                    PersonAvatar {
                        anchors.fill: parent
                        opacity: model.isHidden ? 0.6 : 1.0
                        personId: model.personId
                        name: model.name || ""
                        hasThumbnail: model.hasThumbnail
                        selected: personContextMenu.active
                        backgroundColor: "transparent"
                        letterColor: Theme.secondaryColor
                        letterPixelSize: Theme.fontSizeHuge
                    }

                    Icon {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: Theme.iconSizeSmall
                        height: Theme.iconSizeSmall
                        source: "image://theme/icon-m-favorite-selected"
                        visible: model.isFavorite
                    }

                    Icon {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        width: Theme.iconSizeSmall
                        height: Theme.iconSizeSmall
                        source: "image://theme/icon-m-incognito"
                        visible: model.isHidden
                    }

                    Icon {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        width: Theme.iconSizeSmall
                        height: Theme.iconSizeSmall
                        source: "image://theme/icon-m-share"
                        visible: model.isSharedByMe || model.isSharedWithMe
                    }
                }

                Label {
                    width: parent.width
                    //% "Unknown"
                    text: model.name || qsTrId("peoplePage.unknown")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    horizontalAlignment: Text.AlignHCenter
                    color: parent.parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
            }

            onClicked: {
                pageStack.push(Qt.resolvedUrl("PersonDetailPage.qml"), {
                    personId: model.personId,
                    personName: model.name || "",
                    personBirthDate: model.birthDate || "",
                    personIsFavorite: model.isFavorite || false,
                    personIsHidden: model.isHidden || false,
                    isShared: model.isSharedByMe || model.isSharedWithMe
                })
            }

            onPressAndHold: personContextMenu.open(personDelegate)

            ContextMenu {
                id: personContextMenu

                MenuItem {
                    text: model.isFavorite
                        //% "Remove from favorites"
                        ? qsTrId("peoplePage.removeFromFavorites")
                        //% "Add to favorites"
                        : qsTrId("peoplePage.addToFavorites")
                    onClicked: immichApi.updatePerson(model.personId, { "isFavorite": !model.isFavorite })
                }

                MenuItem {
                    text: model.isHidden
                        //% "Show person"
                        ? qsTrId("peoplePage.unhidePerson")
                        //% "Hide person"
                        : qsTrId("peoplePage.hidePerson")
                    onClicked: immichApi.updatePerson(model.personId, { "isHidden": !model.isHidden })
                }

                MenuItem {
                    //% "Manage access"
                    text: qsTrId("peoplePage.manageAccess")
                    visible: authManager.clusterGroupId !== ""
                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("PersonAccessPage.qml"), {
                            personId: model.personId,
                            personName: model.name || ""
                        })
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    // Loading
    LoadingIndicator {
        anchors.fill: parent
        loading: page.loading && peopleModel.totalCount === 0
        //% "Loading people..."
        message: qsTrId("peoplePage.loading")
    }

    EmptyState {
        anchors.fill: parent
        visible: !page.loading && peopleModel.count === 0
        iconSource: "image://theme/icon-m-people"
        //% "No people found"
        message: qsTrId("peoplePage.noPeople")
    }

    Component.onCompleted: page.refresh()

    Connections {
        target: immichApi
        onPeopleReceived: {
            peopleModel.loadPeople(people)
            page.loading = false
        }
        onPersonSharesReceived: peopleModel.setShares(shares, authManager.userId)
        onPersonUnshared: immichApi.fetchPersonShares()
    }
}
