import QtQuick 2.0
import Sailfish.Silica 1.0
import QtFeedback 5.0

Rectangle {
    id: root

    anchors.left: parent.left
    anchors.right: parent.right
    height: opacity > 0 ? notificationLabel.height + Theme.paddingLarge * 2 : 0
    color: isError ? Theme.rgba(Theme.errorColor, 0.9) : Theme.rgba(Theme.highlightBackgroundColor, 0.9)
    visible: opacity > 0
    opacity: 0

    property bool isError: false

    ThemeEffect {
        id: notificationFeedback
        effect: ThemeEffect.PressWeak
    }

    ThemeEffect {
        id: errorFeedback
        effect: ThemeEffect.Press
    }

    Behavior on opacity {
        NumberAnimation { duration: 300 }
    }

    Label {
        id: notificationLabel
        anchors.centerIn: parent
        width: parent.width - Theme.paddingLarge * 2
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: Theme.primaryColor
    }

    function show(message) {
        isError = false
        notificationLabel.text = message
        opacity = 1
        notificationFeedback.play()
        notificationTimer.restart()
    }

    function showError(message) {
        isError = true
        notificationLabel.text = message
        opacity = 1
        errorFeedback.play()
        notificationTimer.restart()
    }

    Timer {
        id: notificationTimer
        interval: 3000
        onTriggered: root.opacity = 0
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.opacity = 0
    }
}
