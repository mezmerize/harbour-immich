import QtQuick 2.0
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0
import harbour.immich.models 1.0
import "../components"

Page {
    id: page

    property bool loading: true
    property bool showHidden: false

    PeopleModel {
        id: peopleModel
    }

    function refresh() {
        loading = true
        immichApi.fetchPeople(showHidden)
    }

    SilicaGridView {
        id: peopleGrid
        anchors.fill: parent
        clip: true
        currentIndex: -1
        cellWidth: width / 3
        cellHeight: cellWidth + Theme.fontSizeExtraSmall + Theme.paddingMedium
        cacheBuffer: Math.round(cellHeight * 3)

        model: peopleModel

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
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

            SearchField {
                width: parent.width
                //% "Filter by name..."
                placeholderText: qsTrId("peoplePage.filter")
                onTextChanged: peopleModel.filterText = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
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

                    Item {
                        anchors.fill: parent
                        opacity: model.isHidden ? 0.6 : 1.0

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: personContextMenu.active ? 3 : 1
                            border.color: personContextMenu.active ? Theme.highlightColor : Theme.secondaryColor
                            radius: width / 2
                        }

                        Image {
                            id: personImage
                            anchors.fill: parent
                            anchors.margins: 2
                            source: model.thumbnailId ? "image://immich/person/" + model.thumbnailId : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: personDelegate.thumbnailSize
                            sourceSize.height: personDelegate.thumbnailSize
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Item {
                                    width: personImage.width
                                    height: personImage.height
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                    }
                                }
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            text: ((model.name || "?").charAt(0)).toUpperCase()
                            font.pixelSize: Theme.fontSizeHuge
                            color: Theme.secondaryColor
                            visible: !model.thumbnailId
                        }
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
                    thumbnailPath: model.thumbnailPath || "",
                    personIsFavorite: model.isFavorite || false,
                    personIsHidden: model.isHidden || false
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
        onPersonUpdated: page.refresh()
        onPeopleReceived: {
            peopleModel.loadPeople(people)
            page.loading = false
        }
    }
}
