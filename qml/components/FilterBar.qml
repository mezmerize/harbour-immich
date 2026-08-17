import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: filterBar
    width: parent.width
    height: Theme.itemSizeExtraSmall + Theme.paddingMedium

    property var filterModel: [
        //% "Taken"
        { id: "taken", label: qsTrId("filterBar.taken"), icon: "image://theme/icon-m-image" },
        //% "Created"
        { id: "created", label: qsTrId("filterBar.created"), icon: "image://theme/icon-m-clock" }
    ]
    property string activeFilter: filterModel[0].id
    property string sortOrder: "desc" // desc, asc
    property bool favoritesButtonVisible: true
    property bool showFavorites: false
    property real buttonsNumber: favoritesButtonVisible ? filterModel.length + 1 : filterModel.length
    property real filterButtonWidth: (filterRow.width - Theme.paddingSmall - sortButton.width - Theme.paddingMedium) / buttonsNumber

    signal filterActivated(string filter)
    signal filterFavorites(bool showFavorites)
    signal sortOrderToggled(string order)

    Row {
        id: filterRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.horizontalPageMargin
        anchors.rightMargin: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.paddingSmall

        // Switch between filterable values
        Repeater {
            model: filterBar.filterModel

            BackgroundItem {
                width: filterBar.filterButtonWidth
                height: Theme.itemSizeExtraSmall

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: filterBar.activeFilter === modelData.id ? Theme.rgba(Theme.highlightBackgroundColor, 0.4) : "transparent"
                    border.width: filterBar.activeFilter === modelData.id ? 1 : 0
                    border.color: Theme.highlightColor
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.paddingSmall

                    Icon {
                        source: modelData.icon
                        width: Theme.iconSizeSmall
                        height: Theme.iconSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                        color: filterBar.activeFilter === modelData.id ? Theme.highlightColor : Theme.primaryColor
                    }

                    Label {
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: filterBar.activeFilter === modelData.id ? Theme.highlightColor : Theme.primaryColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                onClicked: {
                    if (filterBar.activeFilter !== modelData.id) {
                        filterBar.filterActivated(modelData.id)
                    }
                }
            }
        }

        // Favorites toggle
        BackgroundItem {
            id: favoritesButton
            visible: favoritesButtonVisible
            width: filterBar.filterButtonWidth
            height: Theme.itemSizeExtraSmall

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: filterBar.showFavorites ? Theme.rgba(Theme.highlightBackgroundColor, 0.4) : "transparent"
                border.width: filterBar.showFavorites ? 1 : 0
                border.color: Theme.highlightColor
            }

            Row {
                anchors.centerIn: parent
                spacing: Theme.paddingSmall

                Icon {
                    source: "image://theme/icon-m-favorite"
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                }

                Label {
                    //% "Favorites"
                    text: qsTrId("filterBar.favorites")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: filterBar.showFavorites ? Theme.highlightColor : Theme.primaryColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            onClicked: filterBar.filterFavorites(!filterBar.showFavorites)
        }

        // Sort order button
        BackgroundItem {
            id: sortButton
            width: Theme.itemSizeSmall
            height: Theme.itemSizeExtraSmall

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: sortButton.down ? Theme.rgba(Theme.highlightBackgroundColor, 0.4) : "transparent"

                Behavior on color {
                    ColorAnimation { duration: 100 }
                }
            }

            Icon {
                anchors.centerIn: parent
                source: filterBar.sortOrder === "desc" ? "image://theme/icon-m-down" : "image://theme/icon-m-up"
                width: Theme.iconSizeSmall
                height: Theme.iconSizeSmall
            }

            onClicked: {
                filterBar.sortOrderToggled(filterBar.sortOrder === "desc" ? "asc" : "desc")
            }
        }
    }
}
