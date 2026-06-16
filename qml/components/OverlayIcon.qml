import QtQuick 2.0
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0

Item {
    id: root

    property alias source: icon.source
    property color color: Theme.lightPrimaryColor
    property color shadowColor: Theme.rgba("black", 0.8)

    Icon {
        id: icon
        anchors.fill: parent
        color: root.color

        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 1
            radius: 6
            samples: 13
            spread: 0.2
            color: root.shadowColor
        }
    }
}
