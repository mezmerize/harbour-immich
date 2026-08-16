import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: filterBar
    width: parent.width
    height: Theme.itemSizeExtraSmall + Theme.paddingMedium

    property var filterModel: [
        //% "All"
        { id: "all", label: qsTrId("albumsPage.filterAll"), icon: "image://theme/icon-m-folder" },
        //% "Shared"
        { id: "shared", label: qsTrId("albumsPage.filterShared"), icon: "image://theme/icon-m-share" },
        //% "My albums"
        { id: "mine", label: qsTrId("albumsPage.filterMyAlbums"), icon: "image://theme/icon-m-person" }
    ]
    property string activeFilter: filterModel[0].id
    property real filterButtonWidth: (filterRow.width - Theme.paddingSmall - Theme.paddingMedium) / filterModel.length

    signal filterActivated(string filter)

    function isActive(filterId) {
        if (filterId === "shared") return filterBar.activeFilter === "shared" || filterBar.activeFilter === "sharedWithMe"
        return filterBar.activeFilter === filterId
    }

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
                    color: filterBar.isActive(modelData.id) ? Theme.rgba(Theme.highlightBackgroundColor, 0.4) : "transparent"
                    border.width: filterBar.isActive(modelData.id) ? 1 : 0
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
                        color: filterBar.isActive(modelData.id) ? Theme.highlightColor : Theme.primaryColor
                    }

                    Label {
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: filterBar.isActive(modelData.id) ? Theme.highlightColor : Theme.primaryColor
                        anchors.verticalCenter: parent.verticalCenter
                        truncationMode: TruncationMode.Fade
                    }
                }

                onClicked: filterBar.filterActivated(modelData.id)
            }
        }
    }
}
