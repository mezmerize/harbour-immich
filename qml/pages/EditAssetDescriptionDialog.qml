import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    property string assetId
    property string description

    onAccepted: {
        immichApi.updateAssetDescription(assetId, descriptionField.text)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            DialogHeader {
                //% "Edit Description"
                title: qsTrId("editAssetDescriptionDialog.title")
                //% "Save"
                acceptText: qsTrId("editAssetDescriptionDialog.save")
            }

            TextArea {
                id: descriptionField
                width: parent.width
                //% "Description"
                label: qsTrId("editAssetDescriptionDialog.description")
                placeholderText: label
                text: dialog.description
                focus: true
            }
        }

        VerticalScrollDecorator {}
    }
}
