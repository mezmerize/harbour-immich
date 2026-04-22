import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    property bool loading: false
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
    }
}
