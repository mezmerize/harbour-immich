import QtQuick 2.6
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    property string assetId
    property string description
    property double latitude: 0
    property double longitude: 0
    property bool hasLocation: false

    canAccept: true

    onAccepted: {
        var lat = parseFloat(latitudeField.text) || 0
        var lng = parseFloat(longitudeField.text) || 0
        var locationChanged = latitudeField.text !== "" && longitudeField.text !== "" && (lat !== dialog.latitude || lng !== dialog.longitude || !dialog.hasLocation)
        immichApi.updateAsset(assetId, descriptionField.text, lat, lng, locationChanged)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            DialogHeader {
                //% "Edit Asset"
                title: qsTrId("editAssetDialog.title")
                //% "Save"
                acceptText: qsTrId("editAssetDialog.save")
            }

            TextArea {
                id: descriptionField
                width: parent.width
                //% "Description"
                label: qsTrId("editAssetDialog.description")
                placeholderText: label
                text: dialog.description
                focus: true
            }

            SectionHeader {
                //% "Location"
                text: qsTrId("editAssetDialog.location")
            }

            TextField {
                id: latitudeField
                width: parent.width
                //% "Latitude"
                label: qsTrId("editAssetDialog.latitude")
                placeholderText: label
                text: dialog.hasLocation ? dialog.latitude.toFixed(6) : ""
                inputMethodHints: Qt.ImhFormattedNumbersOnly

                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: longitudeField.focus = true
            }

            TextField {
                id: longitudeField
                width: parent.width
                //% "Longitude"
                label: qsTrId("editAssetDialog.longitude")
                placeholderText: label
                text: dialog.hasLocation ? dialog.longitude.toFixed(6) : ""
                inputMethodHints: Qt.ImhFormattedNumbersOnly

                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }

        VerticalScrollDecorator {}
    }
}
