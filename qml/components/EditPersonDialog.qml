import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: editPersonDialog

    property string personName
    property string personBirthDate
    property bool personIsFavorite
    property bool personIsHidden
    property string newName: nameField.text
    property string newBirthday: personBirthDate
    property bool newFavorite: favoriteSwitch.checked
    property bool newHidden: hiddenSwitch.checked

    canAccept: newName.length > 0 && (newName !== personName || newBirthday !== personBirthDate || newFavorite !== personIsFavorite || newHidden !== personIsHidden)

    Column {
        width: parent.width

        DialogHeader {
            //% "Edit Person"
            title: qsTrId("editPersonDialog.title")
        }

        TextField {
            id: nameField
            width: parent.width
            text: personName
            //% "Name"
            placeholderText: qsTrId("editPersonDialog.name")
            //% "Name"
            label: qsTrId("editPersonDialog.name")
            EnterKey.iconSource: "image://theme/icon-m-enter-next"
            EnterKey.onClicked: favoriteSwitch.focus = true
            onTextChanged: newName = text
        }

        ValueButton {
            width: parent.width
            //% "Birthday"
            label: qsTrId("editPersonDialog.birthday")
            //% "No birthday"
            value: newBirthday ? Qt.formatDate(new Date(newBirthday), "dd.MM.yyyy") : qsTrId("editPersonDialog.noBirthday")

            onClicked: {
                var currentDate = personBirthDate !== "" ? new Date(personBirthDate) : new Date()
                var dialog = pageStack.push("Sailfish.Silica.DatePickerDialog", {
                    date: currentDate
                })
                dialog.accepted.connect(function() {
                    if (dialog.date <= new Date()) {
                        var y = dialog.year
                        var m = dialog.month
                        var d = dialog.day
                        newBirthday = y + "-" + (m < 10 ? "0" + m : m) + "-" + (d < 10 ? "0" + d : d)
                    } else {
                        //% "Future date is not allowed for birthday"
                        notification.showError(qsTrId("notification.birthdayInFuture"))
                    }
                })
            }
        }

        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !!newBirthday
            //% "Clear birthday"
            text: qsTrId("editPersonDialog.clearBirthday")
            onClicked: newBirthday = ""
        }

        TextSwitch {
            id: favoriteSwitch
            //% "Favorite"
            text: qsTrId("editPersonDialog.favorite")
            checked: editPersonDialog.personIsFavorite
        }

        TextSwitch {
            id: hiddenSwitch
            //% "Hidden"
            text: qsTrId("editPersonDialog.hidden")
            checked: editPersonDialog.personIsHidden
        }
    }

    NotificationBanner {
        id: notification
        anchors.bottom: parent.bottom
    }
}
