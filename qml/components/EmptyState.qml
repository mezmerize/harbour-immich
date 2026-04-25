import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: root
    property string iconSource: ""
    property string message: ""
    property string hint: ""

    Column {
        width: parent.width
        anchors.centerIn: parent
        spacing: Theme.paddingLarge

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            source: root.iconSource
            color: Theme.highlightColor
            visible: root.iconSource !== ""
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            horizontalAlignment: Text.AlignHCenter
            text: root.message
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeMedium
            wrapMode: Text.WordWrap
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            horizontalAlignment: Text.AlignHCenter
            text: root.hint
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
            visible: root.hint !== ""
        }
    }
}
