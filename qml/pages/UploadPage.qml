import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0
import "../components"

Page {
  id: uploadPage

  // Status: "picking" -> "uploading" -> "complete"
  property string uploadState: "picking"
  property int currentFileIndex: 0
  property int totalFiles: 0
  property int successCount: 0
  property int duplicateCount: 0
  property int failCount: 0
  property real fileProgress: 0
  property string currentFileName: ""

  ListModel {
      id: fileListModel
  }

  function fileNameFromPath(path) {
      var parts = path.split("/")
      return parts[parts.length - 1]
  }

  function startUpload() {
      if (fileListModel.count === 0) return
      var paths = []
      for (var i = 0; i < fileListModel.count; i++) {
          paths.push(fileListModel.get(i).filePath)
      }
      totalFiles = paths.length
      currentFileIndex = 0
      successCount = 0
      duplicateCount = 0
      failCount = 0
      fileProgress = 0
      uploadState = "uploading"
      immichApi.uploadAssets(paths)
  }

  Component.onDestruction: {
      if (uploadState === "uploading") {
          immichApi.cancelUpload()
      }
  }

  Connections {
      target: immichApi
      onUploadFileProgress: {
          currentFileIndex = fileIndex
          if (bytesTotal > 0) {
              fileProgress = bytesSent / bytesTotal
          }
          if (fileIndex < fileListModel.count) {
              currentFileName = fileNameFromPath(fileListModel.get(fileIndex).filePath)
          }
      }
      onAssetUploaded: {
          if (status === "duplicate") {
              uploadPage.duplicateCount++
          } else {
              uploadPage.successCount++
          }
          // Mark file with its upload status in model
          for (var i = 0; i < fileListModel.count; i++) {
              if (fileListModel.get(i).filePath === filePath) {
                  fileListModel.setProperty(i, "status", status === "duplicate" ? "duplicate" : "success")
                  break
              }
          }
      }
      onUploadFailed: {
          uploadPage.failCount++
          // Mark file as failed in model
          for (var i = 0; i < fileListModel.count; i++) {
              if (fileListModel.get(i).filePath === filePath) {
                  fileListModel.setProperty(i, "status", "failed")
                  break
              }
          }
      }
      onUploadAllComplete: {
          uploadState = "complete"
      }
  }

  SilicaFlickable {
      anchors.fill: parent
      contentHeight: column.height

      PullDownMenu {
          visible: uploadState === "uploading"
          MenuItem {
              //% "Cancel upload"
              text: qsTrId("pullDownMenu.cancel")
              onClicked: {
                  immichApi.cancelUpload()
                  uploadState = "complete"
              }
          }
      }

      Column {
          id: column
          width: parent.width
          spacing: Theme.paddingMedium

          PageHeader {
              //% "Upload"
              title: qsTrId("uploadPage.title")
          }

          // Picking state
          Column {
              width: parent.width
              spacing: Theme.paddingMedium
              visible: uploadState === "picking"

              // Add files button
              BackgroundItem {
                  width: parent.width
                  height: Theme.itemSizeMedium

                  Row {
                      anchors.centerIn: parent
                      spacing: Theme.paddingMedium

                      Image {
                          source: "image://theme/icon-m-add"
                          anchors.verticalCenter: parent.verticalCenter
                      }

                      Label {
                          //% "Add images or videos"
                          text: qsTrId("uploadPage.addFiles")
                          anchors.verticalCenter: parent.verticalCenter
                          color: parent.parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                      }
                  }

                  onClicked: {
                      pageStack.push(contentPickerComponent)
                  }
              }

              // Start upload button
              Button {
                  anchors.horizontalCenter: parent.horizontalCenter
                  //% "Start upload (%1)"
                  text: qsTrId("uploadPage.startUpload").arg(fileListModel.count)
                  enabled: fileListModel.count > 0
                  onClicked: startUpload()
              }
          }

          // Upload progress
          Column {
              x: Theme.horizontalPageMargin
              width: parent.width - 2 * Theme.horizontalPageMargin
              spacing: Theme.paddingSmall
              visible: uploadState === "uploading"

              Label {
                  width: parent.width
                  //% "Uploading %1 of %2"
                  text: qsTrId("uploadPage.progress").arg(currentFileIndex + 1).arg(totalFiles)
                  font.pixelSize: Theme.fontSizeMedium
                  color: Theme.highlightColor
              }

              Label {
                  width: parent.width
                  text: currentFileName
                  font.pixelSize: Theme.fontSizeSmall
                  color: Theme.secondaryHighlightColor
                  truncationMode: TruncationMode.Fade
                  visible: currentFileName.length > 0
              }

              // File progress bar
              Item {
                  width: parent.width
                  height: Theme.paddingSmall

                  Rectangle {
                      width: parent.width
                      height: parent.height
                      color: Theme.rgba(Theme.highlightColor, 0.2)
                      radius: height / 2
                  }

                  Rectangle {
                      width: parent.width * fileProgress
                      height: parent.height
                      color: Theme.highlightColor
                      radius: height / 2
                      Behavior on width { NumberAnimation { duration: 200 } }
                  }
              }

              // Overall progress bar
              Item {
                  width: parent.width
                  height: Theme.paddingMedium

                  Rectangle {
                      width: parent.width
                      height: parent.height
                      color: Theme.rgba(Theme.highlightColor, 0.2)
                      radius: height / 2
                  }

                  Rectangle {
                      width: totalFiles > 0 ? parent.width * ((currentFileIndex + fileProgress) / totalFiles) : 0
                      height: parent.height
                      color: Theme.highlightColor
                      radius: height / 2
                      Behavior on width { NumberAnimation { duration: 200 } }
                  }
              }

              LoadingIndicator {
                  anchors.horizontalCenter: parent.horizontalCenter
                  loading: true
                  indicatorSize: Theme.iconSizeMedium
              }
          }

          // Summary of the state
          Column {
              x: Theme.horizontalPageMargin
              width: parent.width - 2 * Theme.horizontalPageMargin
              spacing: Theme.paddingMedium
              visible: uploadState === "complete"

              Image {
                  anchors.horizontalCenter: parent.horizontalCenter
                  source: failCount === 0 ? "image://theme/icon-l-acknowledge" : "image://theme/icon-l-attention"
                  sourceSize.width: Theme.iconSizeLarge
                  sourceSize.height: Theme.iconSizeLarge
              }

              Label {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  //% "Upload complete"
                  text: qsTrId("uploadPage.complete")
                  font.pixelSize: Theme.fontSizeLarge
                  color: Theme.highlightColor
              }

              Label {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  //% "%1 uploaded"
                  text: qsTrId("uploadPage.successCount").arg(successCount)
                  font.pixelSize: Theme.fontSizeMedium
                  color: Theme.primaryColor
                  visible: successCount > 0
              }

              Label {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  //% "%1 duplicates"
                  text: qsTrId("uploadPage.duplicateCount").arg(duplicateCount)
                  font.pixelSize: Theme.fontSizeMedium
                  color: Theme.secondaryHighlightColor
                  visible: duplicateCount > 0
              }

              Label {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  //% "%1 failed"
                  text: qsTrId("uploadPage.failCount").arg(failCount)
                  font.pixelSize: Theme.fontSizeMedium
                  color: "#ff4444"
                  visible: failCount > 0
              }

              Item { width: 1; height: Theme.paddingLarge }

              Button {
                  anchors.horizontalCenter: parent.horizontalCenter
                  //% "Done"
                  text: qsTrId("uploadPage.done")
                  onClicked: pageStack.pop()
              }
          }

          // Filelist
          SectionHeader {
              //% "Files (%1)"
              text: qsTrId("uploadPage.fileCount").arg(fileListModel.count)
              visible: fileListModel.count > 0
          }

          Repeater {
              model: fileListModel

              ListItem {
                  id: fileDelegate
                  width: column.width
                  contentHeight: Theme.itemSizeSmall
                  menu: uploadState === "picking" ? fileContextMenu : null

                  Row {
                      x: Theme.horizontalPageMargin
                      width: parent.width - 2 * Theme.horizontalPageMargin
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Theme.paddingMedium

                      Image {
                          id: statusIcon
                          anchors.verticalCenter: parent.verticalCenter
                          sourceSize.width: Theme.iconSizeSmall
                          sourceSize.height: Theme.iconSizeSmall
                          visible: model.status !== "pending"
                          source: model.status === "success" ? "image://theme/icon-s-installed"
                                : model.status === "duplicate" ? "image://theme/icon-s-certificates"
                                : model.status === "failed" ? "image://theme/icon-s-high-importance" : ""
                      }

                      Label {
                          width: parent.width - (statusIcon.visible ? statusIcon.width + Theme.paddingMedium : 0)
                          anchors.verticalCenter: parent.verticalCenter
                          text: fileNameFromPath(model.filePath)
                          font.pixelSize: Theme.fontSizeSmall
                          truncationMode: TruncationMode.Fade
                          color: fileDelegate.highlighted ? Theme.highlightColor : Theme.primaryColor
                      }
                  }

                  Component {
                      id: fileContextMenu
                      ContextMenu {
                          MenuItem {
                              //% "Remove"
                              text: qsTrId("uploadPage.remove")
                              onClicked: fileListModel.remove(model.index)
                          }
                      }
                  }
              }
          }

          Item {
              width: parent.width
              height: Theme.paddingLarge
          }
      }

      VerticalScrollDecorator {}
  }

  Component {
      id: contentPickerComponent
      ContentPickerPage {
          //% "Select files"
          title: qsTrId("uploadPage.selectFiles")
          onSelectedContentPropertiesChanged: {
              var path = selectedContentProperties.filePath
              if (path && path.length > 0) {
                  // Avoid duplicates
                  for (var i = 0; i < fileListModel.count; i++) {
                      if (fileListModel.get(i).filePath === path) return
                  }
                  fileListModel.append({ "filePath": path, "status": "pending" })
              }
          }
      }
  }
}
