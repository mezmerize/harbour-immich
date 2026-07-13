import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: filterBar
    width: parent.width
    height: Theme.itemSizeExtraSmall + Theme.paddingMedium

    property string activeFilter: "taken"  // taken, created
    property string sortOrder: "desc"    // desc, asc
    property bool showFavorites: false
    property bool showActiveFilter: true
    property real filterButtonWidth: (filterRow.width - Theme.paddingSmall - sortButton.width - Theme.paddingMedium) / (showActiveFilter ? 3 : 1)

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

        // Switch between date taken and date added
        Repeater {
            model: showActiveFilter ? [
                //% "Taken"
                { id: "taken", label: qsTrId("timelineFilterBar.taken"), icon: "image://theme/icon-m-image" },
                //% "Created"
                { id: "created", label: qsTrId("timelineFilterBar.created"), icon: "image://theme/icon-m-clock" }
            ] : null

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
                    text: qsTrId("timelineFilterBar.favorites")
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
