import QtQuick 2.0
import Sailfish.Silica 1.0

Column {
    id: pinPad

    property string pin: ""
    signal completed(string pin)

    function clear() {
        pin = ""
    }

    spacing: Theme.paddingLarge

    // PIN dots display
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.paddingLarge

        Repeater {
            model: 6
            Rectangle {
                width: Theme.iconSizeSmall
                height: width
                radius: width / 2
                color: index < pinPad.pin.length ? Theme.highlightColor : "transparent"
                border.width: 2
                border.color: Theme.highlightColor
            }
        }
    }

    // Number pad
    Grid {
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 3
        spacing: Theme.paddingMedium

        Repeater {
            model: [1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 0, -2]

            BackgroundItem {
                width: Theme.itemSizeLarge
                height: Theme.itemSizeLarge
                enabled: pinPad.enabled && modelData !== -1

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: parent.highlighted ? Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity) : Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                    visible: modelData !== -1
                }

                Label {
                    anchors.centerIn: parent
                    text: modelData >= 0 ? modelData.toString() : ""
                    font.pixelSize: Theme.fontSizeExtraLarge
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                    visible: modelData >= 0
                }

                // Backspace icon
                Icon {
                    anchors.centerIn: parent
                    source: "image://theme/icon-m-backspace"
                    visible: modelData === -2
                }

                onClicked: {
                    if (modelData >= 0) {
                        if (pinPad.pin.length < 6) {
                            pinPad.pin = pinPad.pin + modelData.toString()
                            if (pinPad.pin.length === 6) {
                                pinPad.completed(pinPad.pin)
                            }
                        }
                    } else if (modelData === -2) {
                        if (pinPad.pin.length > 0) {
                            pinPad.pin = pinPad.pin.substring(0, pinPad.pin.length - 1)
                        }
                    }
                }
            }
        }
    }
}
