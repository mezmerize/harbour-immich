import QtQuick 2.0
import Sailfish.Silica 1.0

MouseArea {
    id: selectedCountButton

    property int selectedCount: 0
    property real actionBarHeight: 0
    property bool forceHidden: false

    signal clearSelection()

    readonly property string position: settingsManager.selectedCountPosition
    readonly property bool atTop: position.indexOf("top") === 0
    readonly property bool atLeft: position.indexOf("left") !== -1
    readonly property bool atRight: position.indexOf("right") !== -1
    readonly property bool atCenter: position.indexOf("center") !== -1

    width: contentRow.width + 2 * Theme.paddingLarge
    height: Theme.itemSizeMedium
    z: 10

    visible: !forceHidden && selectedCount > 0
    opacity: pressed ? 0.6 : 0.85

    Behavior on opacity {
        NumberAnimation { duration: 100 }
    }

    anchors {
        top: atTop ? parent.top : undefined
        bottom: atTop ? undefined : parent.bottom
        left: atLeft ? parent.left : undefined
        right: atRight ? parent.right : undefined
        horizontalCenter: atCenter ? parent.horizontalCenter : undefined
        topMargin: Theme.paddingLarge
        bottomMargin: Theme.paddingLarge + actionBarHeight
        leftMargin: Theme.horizontalPageMargin
        rightMargin: Theme.horizontalPageMargin
    }

    onClicked: clearSelection()

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.rgba(Theme.highlightDimmerColor, 0.9)
        border.width: 1
        border.color: Theme.rgba(Theme.highlightColor, 0.4)

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: Theme.paddingMedium

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: selectedCountButton.selectedCount
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                source: "image://theme/icon-m-dismiss"
                width: Theme.iconSizeSmall
                height: Theme.iconSizeSmall
                color: Theme.highlightColor
            }
        }
    }
}
