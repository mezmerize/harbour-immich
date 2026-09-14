import QtQuick 2.0
import Sailfish.Silica 1.0

Rectangle {
    property real dragOpacity: 1.0
    property real dragOffsetY: 0
    property bool draggingVertical: false
    property real dismissThreshold: 0
    property string releaseText: ""
    property string dragText: ""

    color: Theme.rgba("black", dragOpacity * 0.95)

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        y: dragOffsetY > 0 ? Theme.paddingLarge * 2 : parent.height - height - Theme.paddingLarge * 2
        visible: draggingVertical && dragOffsetY > 0
        opacity: Math.min(1.0, Math.abs(dragOffsetY) / (dismissThreshold * 0.5))
        text: Math.abs(dragOffsetY) >= dismissThreshold ? releaseText : dragText
        color: Math.abs(dragOffsetY) >= dismissThreshold ? Theme.highlightColor : Theme.secondaryColor
        font.pixelSize: Theme.fontSizeMedium
    }
}
