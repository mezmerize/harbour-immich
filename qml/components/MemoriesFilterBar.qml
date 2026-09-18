import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: filterBar
    width: parent.width
    height: Theme.itemSizeExtraSmall + Theme.paddingMedium

    property string sortOrder: "desc" // desc, asc
    property bool showFavorites: false
    property bool showUpcoming: false
    property real filterButtonWidth: (filterRow.width - Theme.paddingSmall - sortButton.width - Theme.paddingMedium) / 2

    signal filterFavorites(bool showFavorites)
    signal filterUpcoming(bool showUpcoming)
    signal sortOrderToggled(string order)

    Row {
        id: filterRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.horizontalPageMargin
        anchors.rightMargin: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.paddingSmall

        // Upcoming toggle
        BackgroundItem {
            id: upcomingButton
            width: filterBar.filterButtonWidth
            height: Theme.itemSizeExtraSmall

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: filterBar.showUpcoming ? Theme.rgba(Theme.highlightBackgroundColor, 0.4) : "transparent"
                border.width: filterBar.showUpcoming ? 1 : 0
                border.color: Theme.highlightColor
            }

            Row {
                anchors.centerIn: parent
                spacing: Theme.paddingSmall

                Icon {
                    source: "image://theme/icon-m-date"
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall
                    color: filterBar.showUpcoming ? Theme.highlightColor : Theme.primaryColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Label {
                    //% "Upcoming"
                    text: qsTrId("filterBar.upcoming")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: filterBar.showUpcoming ? Theme.highlightColor : Theme.primaryColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            onClicked: filterBar.filterUpcoming(!filterBar.showUpcoming)
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
                    color: filterBar.showFavorites ? Theme.highlightColor : Theme.primaryColor
                    anchors.verticalCenter: parent.verticalCenter
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
