import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    property string iconSource: ""
    property string message: ""

    Column {
        anchors.centerIn: parent
        spacing: Theme.paddingLarge

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            source: iconSource
            color: Theme.highlightColor
            visible: iconSource !== ""
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: message
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeMedium
        }
    }
}
