import QtQuick 2.0
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0

Dialog {
   id: peoplePickerDialog

   //% "Select People"
   property string title: qsTrId("peoplePickerDialog.selectPeople")
   property var model: []  // Array of {personId, name, thumbnailId}
   property var selectedPeople: []  // Array of personIds

   // Filter text
   property string filterText: ""

   // Pagination
   property int initialLimit: 12 // Show first 12 items initially
   property bool expanded: false

   // Filtered model
   property var filteredModel: {
       if (!filterText || filterText.length === 0) {
           return model
       }
       var lowerFilter = filterText.toLowerCase()
       var result = []
       for (var i = 0; i < model.length; i++) {
           var item = model[i]
           var name = item.name || ""
           if (name.toLowerCase().indexOf(lowerFilter) !== -1) {
               result.push(item)
           }
       }
       return result
   }

   // Internal selection state
   property var _selectedSet: {
       var set = {}
       for (var i = 0; i < selectedPeople.length; i++) {
           set[selectedPeople[i]] = true
       }
       return set
   }

   canAccept: true

   onAccepted: {
       // selectedPeople is already updated during interaction
   }

   SilicaFlickable {
       anchors.fill: parent
       contentHeight: column.height

       Column {
           id: column
           width: parent.width

           DialogHeader {
               title: peoplePickerDialog.title
               //% "Done"
               acceptText: qsTrId("peoplePickerDialog.done")
               //% "Cancel"
               cancelText: qsTrId("peoplePickerDialog.cancel")
           }

           // Filter input field
           SearchField {
               id: filterField
               width: parent.width
               //% "Filter by name..."
               placeholderText: qsTrId("peoplePickerDialog.filterName")

               onTextChanged: {
                   peoplePickerDialog.filterText = text
               }

               EnterKey.iconSource: "image://theme/icon-m-enter-close"
               EnterKey.onClicked: focus = false
           }

           // Selection info with clear button
           Row {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               spacing: Theme.paddingMedium

               Label {
                   text: selectedPeople.length > 0
                         //% "%1 selected"
                         ? qsTrId("peoplePickerDialog.selected").arg(selectedPeople.length)
                         //% "Tap to select people"
                         : qsTrId("peoplePickerDialog.tapToSelect")
                   font.pixelSize: Theme.fontSizeExtraSmall
                   color: Theme.secondaryColor
               }

               Label {
                   text: "·"
                   font.pixelSize: Theme.fontSizeExtraSmall
                   color: Theme.secondaryColor
                   visible: selectedPeople.length > 0
               }

               Label {
                   //% "Clear selection."
                   text: qsTrId("peoplePickerDialog.clear")
                   font.pixelSize: Theme.fontSizeExtraSmall
                   color: Theme.highlightColor
                   visible: selectedPeople.length > 0

                   MouseArea {
                       anchors.fill: parent
                       onClicked: selectedPeople = []
                   }
               }
           }

           Item { width: 1; height: Theme.paddingMedium }

           // Grid of people
           Flow {
               id: peopleGrid
               width: parent.width - 2 * Theme.horizontalPageMargin
               x: Theme.horizontalPageMargin
               spacing: Theme.paddingSmall

               property int itemSize: Theme.itemSizeMedium

               Repeater {
                   id: peopleRepeater

                   // Limit to initialLimit unless expanded
                   property int maxVisible: expanded ? filteredModel.length : Math.min(initialLimit, filteredModel.length)

                   model: peoplePickerDialog.filteredModel

                   BackgroundItem {
                       width: peopleGrid.itemSize
                       height: peopleGrid.itemSize + Theme.paddingMedium + Theme.fontSizeTiny

                       property bool isSelected: peoplePickerDialog._selectedSet[modelData.personId] === true

                       Column {
                           anchors.fill: parent
                           spacing: Theme.paddingSmall / 2

                           Rectangle {
                               width: peopleGrid.itemSize
                               height: peopleGrid.itemSize
                               color: "transparent"
                               border.width: isSelected ? 3 : 1
                               border.color: isSelected ? Theme.highlightColor : Theme.secondaryColor
                               radius: width / 2

                               Image {
                                   id: personImage
                                   anchors.fill: parent
                                   anchors.margins: 2
                                   source: modelData.thumbnailId ? "image://immich/person/" + modelData.thumbnailId : ""
                                   fillMode: Image.PreserveAspectCrop
                                   asynchronous: true
                                   layer.enabled: true
                                   layer.effect: OpacityMask {
                                       maskSource: Item {
                                           width: personImage.width
                                           height: personImage.height
                                           Rectangle {
                                               anchors.fill: parent
                                               radius: width / 2
                                           }
                                       }
                                   }
                               }

                               // Fallback when no thumbnail
                               Label {
                                   anchors.centerIn: parent
                                   text: (modelData.name || "?").charAt(0).toUpperCase()
                                   font.pixelSize: Theme.fontSizeLarge
                                   color: Theme.secondaryColor
                                   visible: !modelData.thumbnailId
                               }

                               // Selection checkmark
                               Rectangle {
                                   anchors.right: parent.right
                                   anchors.bottom: parent.bottom
                                   anchors.margins: 2
                                   width: Theme.iconSizeSmall
                                   height: Theme.iconSizeSmall
                                   radius: width / 2
                                   color: Theme.highlightColor
                                   visible: isSelected

                                   Image {
                                       anchors.centerIn: parent
                                       source: "image://theme/icon-s-installed"
                                       width: Theme.iconSizeSmall * 0.7
                                       height: width
                                   }
                               }
                           }

                           Label {
                               width: peopleGrid.itemSize
                               //% "Unknown"
                               text: modelData.name || qsTrId("peoplePickerDialog.unknown")
                               font.pixelSize: Theme.fontSizeTiny
                               truncationMode: TruncationMode.Fade
                               horizontalAlignment: Text.AlignHCenter
                               color: isSelected ? Theme.highlightColor : Theme.primaryColor
                           }
                       }

                       visible: index < peopleRepeater.maxVisible

                       onClicked: {
                           var personId = modelData.personId
                           var idx = selectedPeople.indexOf(personId)
                           var newSelection = selectedPeople.slice() // copy
                           if (idx > -1) {
                               newSelection.splice(idx, 1)
                           } else {
                               newSelection.push(personId)
                           }
                           selectedPeople = newSelection
                       }
                   }
               }
           }

           // Show more / Show less button
           BackgroundItem {
               width: parent.width
               height: Theme.itemSizeExtraSmall
               visible: filteredModel.length > initialLimit

               Label {
                   anchors.centerIn: parent
                   text: expanded
                        //% "Show less"
                        ? qsTrId("peoplePickerDialog.showLess")
                        //% "Show more (%1 more)"
                        : qsTrId("peoplePickerDialog.showMore").arg(filteredModel.length - initialLimit)
                   color: Theme.highlightColor
                   font.pixelSize: Theme.fontSizeSmall
               }

               onClicked: expanded = !expanded
           }

           // Empty state when no people or search results
           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               text: model.length === 0
                    //% "No people available"
                    ? qsTrId("peoplePickerDialog.noPeople")
                    //% "No matches found"
                    : qsTrId("peoplePickerDialog.noMatches")
               color: Theme.secondaryHighlightColor
               font.pixelSize: Theme.fontSizeMedium
               horizontalAlignment: Text.AlignHCenter
               visible: model.length === 0 || (filterText.length > 0 && filteredModel.length === 0)
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
