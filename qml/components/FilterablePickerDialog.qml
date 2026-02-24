import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
   id: pickerDialog

   property string title: ""
   property var model: []  // Array of {displayValue: string, actualValue: string}
   property int selectedIndex: -1
   property string selectedValue: ""
   property string selectedDisplayValue: ""

   // Filter text
   property string filterText: ""

   // Filtered model
   property var filteredModel: {
       if (!filterText || filterText.length === 0) {
           return model
       }
       var lowerFilter = filterText.toLowerCase()
       var result = []
       for (var i = 0; i < model.length; i++) {
           var item = model[i]
           if (item.displayValue.toLowerCase().indexOf(lowerFilter) !== -1) {
               result.push({
                   displayValue: item.displayValue,
                   actualValue: item.actualValue,
                   originalIndex: i
               })
           }
       }
       return result
   }

   canAccept: false

   SilicaFlickable {
       anchors.fill: parent
       contentHeight: column.height

       Column {
           id: column
           width: parent.width

           DialogHeader {
               title: pickerDialog.title
               acceptText: ""
               //% "Cancel"
               cancelText: qsTrId("filterablePickerDialog.cancel")
           }

           // Filter input field
           SearchField {
               id: filterField
               width: parent.width
               //% "Filter options..."
               placeholderText: qsTrId("filterablePickerDialog.filterOptions")

               onTextChanged: {
                   pickerDialog.filterText = text
               }

               EnterKey.iconSource: "image://theme/icon-m-enter-close"
               EnterKey.onClicked: focus = false
           }

           // "Any" option at the top
           BackgroundItem {
               width: parent.width
               height: Theme.itemSizeSmall

               Label {
                   anchors {
                       left: parent.left
                       right: parent.right
                       leftMargin: Theme.horizontalPageMargin
                       rightMargin: Theme.horizontalPageMargin
                       verticalCenter: parent.verticalCenter
                   }
                   //% "Any"
                   text: qsTrId("filterablePickerDialog.any")
                   color: selectedIndex === 0 ? Theme.highlightColor : Theme.primaryColor
                   font.bold: selectedIndex === 0
               }

               onClicked: {
                   pickerDialog.selectedIndex = 0
                   pickerDialog.selectedValue = ""
                   // % "Any"
                   pickerDialog.selectedDisplayValue = qsTrId("filterablePickerDialog.any")
                   pickerDialog.canAccept = true
                   pickerDialog.accept()
               }
           }

           // Separator
           Separator {
               width: parent.width
               color: Theme.primaryColor
               horizontalAlignment: Qt.AlignHCenter
           }

           // Results count when filtering
           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               text: filterText.length > 0 ? (filteredModel.length === 1
                     //% "1 result"
                     ? qsTrId("filterablePickerDialog.result")
                     //% "%1 results"
                     : qsTrId("filterablePickerDialog.results").arg(filteredModel.length))
                     : (model.length === 1
                     //% "1 option"
                     ? qsTrId("filterablePickerDialog.option")
                     //% "%1 options"
                     : qsTrId("filterablePickerDialog.options").arg(model.length))
               font.pixelSize: Theme.fontSizeExtraSmall
               color: Theme.secondaryColor
               visible: model.length > 10
           }

           // Filtered list of options
           Repeater {
               model: pickerDialog.filteredModel

               BackgroundItem {
                   width: column.width
                   height: Theme.itemSizeSmall

                   property int actualIndex: modelData.originalIndex !== undefined ? modelData.originalIndex + 1 : index + 1

                   Label {
                       anchors {
                           left: parent.left
                           right: parent.right
                           leftMargin: Theme.horizontalPageMargin
                           rightMargin: Theme.horizontalPageMargin
                           verticalCenter: parent.verticalCenter
                       }
                       text: modelData.displayValue
                       color: selectedIndex === actualIndex ? Theme.highlightColor : Theme.primaryColor
                       font.bold: selectedIndex === actualIndex
                       truncationMode: TruncationMode.Fade
                   }

                   onClicked: {
                       pickerDialog.selectedIndex = actualIndex
                       pickerDialog.selectedValue = modelData.actualValue
                       pickerDialog.selectedDisplayValue = modelData.displayValue
                       pickerDialog.canAccept = true
                       pickerDialog.accept()
                   }
               }
           }

           // Empty state when no results
           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               //% "No matches found"
               text: qsTrId("filterablePickerDialog.noMatchesFound")
               color: Theme.secondaryHighlightColor
               font.pixelSize: Theme.fontSizeMedium
               horizontalAlignment: Text.AlignHCenter
               visible: filterText.length > 0 && filteredModel.length === 0
               height: visible ? implicitHeight + Theme.paddingLarge * 2 : 0
               verticalAlignment: Text.AlignVCenter
           }

           Item {
               width: parent.width
               height: Theme.paddingLarge
           }
       }

       VerticalScrollDecorator {}
   }
}
