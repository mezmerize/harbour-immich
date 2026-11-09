import QtQuick 2.6
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0

Item {
    property string personId: ""
    property string name: ""
    property bool hasThumbnail: true
    property bool selected: false
    property real letterPixelSize: Theme.fontSizeLarge
    property color letterColor: Theme.highlightColor
    property color backgroundColor: Theme.rgba(Theme.highlightBackgroundColor, 0.3)

    width: Theme.itemSizeSmall
    height: Theme.itemSizeSmall

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: selected ? 3 : 1
        border.color: selected ? Theme.highlightColor : Theme.secondaryColor
        radius: width / 2
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: width / 2
        color: backgroundColor
    }

    Image {
        id: img
        anchors.fill: parent
        anchors.margins: 2
        source: hasThumbnail && personId !== "" ? "image://immich/person/" + personId : ""
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: width
        sourceSize.height: height
        visible: status === Image.Ready
        layer.enabled: status === Image.Ready
        layer.effect: OpacityMask {
            maskSource: Item {
                width: img.width
                height: img.height

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        anchors.margins: 2
        visible: img.status !== Image.Ready
        text: ((name || "?").charAt(0)).toUpperCase()
        font.pixelSize: letterPixelSize
        color: letterColor
    }
}
