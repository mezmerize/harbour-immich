import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
  id: dialog

  property string albumId
  property string albumName
  property string albumDescription

  canAccept: nameField.text.length > 0

  onAccepted: {
      immichApi.updateAlbum(albumId, nameField.text, descriptionField.text)
  }

  SilicaFlickable {
      anchors.fill: parent
      contentHeight: column.height

      Column {
          id: column
          width: parent.width

          DialogHeader {
              //% "Edit Album"
              title: qsTrId("editAlbumDialog.editAlbum")
              //% "Save"
              acceptText: qsTrId("editAlbumDialog.save")
          }

          TextField {
              id: nameField
              width: parent.width
              //% "Album name"
              label: qsTrId("editAlbumDialog.albumName")
              placeholderText: label
              text: dialog.albumName

              EnterKey.iconSource: "image://theme/icon-m-enter-next"
              EnterKey.onClicked: descriptionField.focus = true
          }

          TextArea {
              id: descriptionField
              width: parent.width
              //% "Description"
              label: qsTrId("editAlbumDialog.description")
              placeholderText: label
              text: dialog.albumDescription
          }
      }

      VerticalScrollDecorator {}
  }
}
