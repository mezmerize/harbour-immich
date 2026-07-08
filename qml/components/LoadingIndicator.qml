import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: root
    property bool loading: false
    property string message: ""
    property bool useMonochrome: false
    property real indicatorSize: useMonochrome ? Theme.iconSizeMedium : Theme.iconSizeExtraLarge
    property color iconColor: Theme.lightPrimaryColor

    visible: loading
    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: Theme.paddingMedium
        anchors.centerIn: parent

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.indicatorSize
            height: width
            color: root.useMonochrome ? root.iconColor : undefined
            source: root.useMonochrome ? Qt.resolvedUrl("../../icons/loading-mono-icon.svg") : Qt.resolvedUrl("../../icons/loading-icon.svg")

            NumberAnimation on rotation {
                from: 0
                to: 360
                duration: 1000
                loops: Animation.Infinite
                running: root.loading
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.message
            color: Theme.secondaryHighlightColor
            visible: root.message !== ""
        }
    }
}
