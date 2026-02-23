import QtQuick 2.0
import Sailfish.Silica 1.0

MouseArea {
    id: scrollButton

    property Flickable targetFlickable
    property real actionBarHeight: 0
    property bool forceHidden: false

    width: Theme.itemSizeMedium
    height: Theme.itemSizeMedium
    z: 10

    visible: !forceHidden && targetFlickable && targetFlickable.contentY > Theme.itemSizeLarge
    opacity: pressed ? 0.6 : 0.85

    Behavior on opacity {
        NumberAnimation { duration: 100 }
    }

    anchors {
        bottom: parent.bottom
        bottomMargin: Theme.paddingLarge + actionBarHeight
    }

    // Horizontal position from setting
    states: [
        State {
            name: "left"
            when: settingsManager.scrollToTopPosition === "left"
            AnchorChanges {
                target: scrollButton
                anchors.left: parent.left
                anchors.right: undefined
                anchors.horizontalCenter: undefined
            }
            PropertyChanges {
                target: scrollButton
                anchors.leftMargin: Theme.horizontalPageMargin
            }
        },
        State {
            name: "center"
            when: settingsManager.scrollToTopPosition === "center"
            AnchorChanges {
                target: scrollButton
                anchors.left: undefined
                anchors.right: undefined
                anchors.horizontalCenter: parent.horizontalCenter
            }
        },
        State {
            name: "right"
            when: settingsManager.scrollToTopPosition === "right"
            AnchorChanges {
                target: scrollButton
                anchors.left: undefined
                anchors.right: parent.right
                anchors.horizontalCenter: undefined
            }
            PropertyChanges {
                target: scrollButton
                anchors.rightMargin: Theme.horizontalPageMargin
            }
        }
    ]

    onClicked: {
        if (targetFlickable) {
            targetFlickable.scrollToTop()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.rgba(Theme.highlightDimmerColor, 0.9)
        border.width: 1
        border.color: Theme.rgba(Theme.highlightColor, 0.4)

        Icon {
            anchors.centerIn: parent
            source: "image://theme/icon-m-up"
            color: Theme.highlightColor
        }
    }
}
