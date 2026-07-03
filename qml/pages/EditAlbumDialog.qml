import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0

Dialog {
  id: dialog

  property string albumId
  property string albumName
  property string albumDescription
  property bool isActivityEnabled: true
  property string albumThumbnailAssetId: ""
  property string selectedThumbnailAssetId: albumThumbnailAssetId
  // 3 and half images on the line so that it points to allowed horizontal scrolling
  property real thumbnailSize: Math.max(Theme.itemSizeLarge, Math.floor((width - 2 * Theme.horizontalPageMargin) / 3.5))
  property var albumAssets: []
  property string albumContext: "edit-album-" + albumId
  property var albumQuery: ({"albumId": albumId, "order": "desc"})
  property int nextBucketToLoad: 0

  canAccept: nameField.text.length > 0

  onAccepted: {
      immichApi.updateAlbum(albumId, nameField.text, descriptionField.text, isActivityEnabled, selectedThumbnailAssetId)
  }

  function loadNextBucket() {
      var bucketCount = pickerModel.getBucketCount()
      while (nextBucketToLoad < bucketCount && pickerModel.isBucketLoaded(nextBucketToLoad)) {
          nextBucketToLoad++
      }
      if (nextBucketToLoad < bucketCount)
          pickerModel.requestBucketLoad(nextBucketToLoad)
  }

  TimelineModel {
      id: pickerModel
  }

  Component.onCompleted: {
      pickerModel.setServerUrl(authManager.serverUrl)
      immichApi.fetchTimelineBuckets(albumContext, albumQuery)
  }

  Connections {
      target: immichApi
      onTimelineBucketsReceived: {
          if (context !== dialog.albumContext) return
          pickerModel.loadBuckets(buckets)
          dialog.nextBucketToLoad = 0
          if (pickerModel.getBucketCount() > 0)
              dialog.loadNextBucket()
      }
      onTimelineBucketReceived: {
          if (context !== dialog.albumContext) return
          pickerModel.loadBucketAssets(timeBucket, bucketData)
          dialog.albumAssets = pickerModel.getLoadedAssetIds()
          var visibleCapacity = Math.ceil(dialog.width / dialog.thumbnailSize) + 4
          if (dialog.albumAssets.length < visibleCapacity)
              dialog.loadNextBucket()
      }
  }

  Connections {
      target: pickerModel
      onBucketLoadRequested: {
          immichApi.fetchTimelineBucket(dialog.albumContext, timeBucket, dialog.albumQuery)
      }
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

          SectionHeader {
              //% "Album thumbnail"
              text: qsTrId("editAlbumDialog.albumThumbnail")
              visible: dialog.albumAssets.length > 0
          }

          ListView {
              id: thumbnailList
              x: Theme.horizontalPageMargin
              width: parent.width - 2 * Theme.horizontalPageMargin
              height: dialog.albumAssets.length > 0 ? dialog.thumbnailSize : 0
              orientation: ListView.Horizontal
              spacing: Theme.paddingSmall
              clip: true
              model: dialog.albumAssets
              visible: dialog.albumAssets.length > 0
              cacheBuffer: Math.round(dialog.thumbnailSize * 4)

              onContentXChanged: {
                  if (contentWidth > 0 && contentX + width > contentWidth - dialog.thumbnailSize * 3)
                      dialog.loadNextBucket()
              }

              delegate: BackgroundItem {
                  width: dialog.thumbnailSize
                  height: dialog.thumbnailSize
                  highlighted: dialog.selectedThumbnailAssetId === modelData

                  onClicked: {
                      if (modelData) {
                          dialog.selectedThumbnailAssetId = modelData
                      }
                  }

                  Image {
                      id: thumbnailImage
                      anchors.fill: parent
                      fillMode: Image.PreserveAspectCrop
                      source: modelData ? "image://immich/thumbnail/" + modelData : ""
                      asynchronous: true

                      Rectangle {
                          anchors.fill: parent
                          color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                          visible: thumbnailImage.status !== Image.Ready
                      }

                      Image {
                          anchors.centerIn: parent
                          source: "image://theme/icon-m-image"
                          visible: thumbnailImage.status !== Image.Ready
                      }
                  }

                  Rectangle {
                      anchors.fill: parent
                      color: "transparent"
                      border.width: dialog.selectedThumbnailAssetId === modelData ? 2 : 0
                      border.color: Theme.highlightColor
                  }
              }
          }
      }

      VerticalScrollDecorator {}
  }
}
