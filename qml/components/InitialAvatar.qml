import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    property string name: ""
    property string iconSource: ""
    property bool selected: false

    width: Theme.itemSizeSmall
    height: Theme.itemSizeSmall

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 3
        border.color: Theme.highlightColor
        radius: width / 2
        visible: selected
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.3)
    }

    Label {
        anchors.centerIn: parent
        visible: iconSource === ""
        text: ((name || "?").charAt(0)).toUpperCase()
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.highlightColor
    }

    Icon {
        anchors.centerIn: parent
        visible: iconSource !== ""
        source: iconSource
        color: Theme.highlightColor
    }
}
