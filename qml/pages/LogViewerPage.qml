import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
  id: page

  property string previousLogs: ""

  //% "%1 log entries"
  function updateCount() { entryCountLabel.text = qsTrId("logViewerPage.entryCount").arg(logManager.count) }
  Component.onCompleted: {
      updateCount()
      previousLogs = logManager.previousLogContents()
  }

  Connections {
      target: logManager
      onLogsChanged: updateCount()
  }

  SilicaFlickable {
      anchors.fill: parent
      contentHeight: column.height

      PullDownMenu {
          MenuItem {
              //% "Clear logs"
              text: qsTrId("logViewerPage.clearLogs")
              onClicked: logManager.clear()
          }

          MenuItem {
              //% "Copy to clipboard"
              text: qsTrId("logViewerPage.copyToClipboard")
              onClicked: {
                  Clipboard.text = logManager.logs.join("\n")
              }
          }
      }

      Column {
          id: column
          width: parent.width

          PageHeader {
              //% "Application Logs"
              title: qsTrId("logViewerPage.title")
          }

          SectionHeader {
              //% "Current session"
              text: qsTrId("logViewerPage.currentSession")
          }

          Label {
              id: entryCountLabel
              x: Theme.horizontalPageMargin
              width: parent.width - 2 * Theme.horizontalPageMargin
              font.pixelSize: Theme.fontSizeExtraSmall
              color: Theme.secondaryHighlightColor
          }

          Item {
              width: parent.width
              height: Theme.paddingMedium
          }

          Repeater {
              model: logManager.logs

              Label {
                  x: Theme.horizontalPageMargin
                  width: page.width - 2 * Theme.horizontalPageMargin
                  text: modelData
                  font.pixelSize: Theme.fontSizeTiny
                  font.family: "monospace"
                  wrapMode: Text.WrapAnywhere
                  color: {
                      if (modelData.indexOf("] WRN:") > -1) return Theme.rgba(Theme.highlightColor, 0.9)
                      if (modelData.indexOf("] ERR:") > -1) return "#ff4444"
                      if (modelData.indexOf("] FTL:") > -1) return "#ff0000"
                      return Theme.primaryColor
                  }
              }
          }

          SectionHeader {
              //% "Previous session"
              text: qsTrId("logViewerPage.previousSession")
              visible: previousLogs.length > 0
          }

          Label {
              x: Theme.horizontalPageMargin
              width: page.width - 2 * Theme.horizontalPageMargin
              visible: previousLogs.length > 0
              text: previousLogs
              font.pixelSize: Theme.fontSizeTiny
              font.family: "monospace"
              wrapMode: Text.WrapAnywhere
              color: Theme.secondaryColor
          }

          Label {
              x: Theme.horizontalPageMargin
              width: page.width - 2 * Theme.horizontalPageMargin
              visible: previousLogs.length === 0
              //% "No previous session logs available"
              text: qsTrId("logViewerPage.noPreviousLogs")
              font.pixelSize: Theme.fontSizeExtraSmall
              color: Theme.secondaryColor
          }

          Item {
              width: parent.width
              height: Theme.paddingLarge
          }
      }

      VerticalScrollDecorator {}
  }
}
