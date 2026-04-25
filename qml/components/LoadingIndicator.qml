import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: root
    property bool loading: false
    property string message: ""
    visible: loading

    Column {
        width: parent.width
        spacing: Theme.paddingMedium
        anchors.centerIn: parent

        BusyIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            running: parent.parent.visible
            size: BusyIndicatorSize.Large
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.message
            color: Theme.secondaryHighlightColor
            visible: root.message !== ""
        }
    }
}
