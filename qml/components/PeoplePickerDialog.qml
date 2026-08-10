import QtQuick 2.0
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0
import harbour.immich.models 1.0

Dialog {
    id: peoplePickerDialog

    //% "Select People"
    property string title: qsTrId("peoplePickerDialog.selectPeople")
    property var model: []  // Array of {personId, name, thumbnailId}
    property var selectedPeople: []  // Array of personIds

    // Internal selection state
    property var selectedSet: {
        var set = {}
        for (var i = 0; i < selectedPeople.length; i++) {
            set[selectedPeople[i]] = true
        }
        return set
    }

    canAccept: true

    PeopleModel {
        id: peopleModel
    }

    onModelChanged: peopleModel.loadPeople(model)
    Component.onCompleted: peopleModel.loadPeople(model)

    SilicaGridView {
        id: peopleGrid
        anchors.fill: parent
        clip: true
        currentIndex: -1
        cellWidth: width / 3
        cellHeight: cellWidth + Theme.fontSizeExtraSmall + Theme.paddingMedium
        cacheBuffer: Math.round(cellHeight * 3)

        model: peopleModel

        header: Column {
            id: headerColumn
            width: peopleGrid.width

            DialogHeader {
                title: peoplePickerDialog.title
                //% "Done"
                acceptText: qsTrId("peoplePickerDialog.done")
                //% "Cancel"
                cancelText: qsTrId("peoplePickerDialog.cancel")
            }

            // Filter input field
            SearchField {
                width: parent.width
                //% "Filter by name..."
                placeholderText: qsTrId("peoplePickerDialog.filterName")
                onTextChanged: peopleModel.filterText = text
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
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                }

                Label {
                    text: "·"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    visible: selectedPeople.length > 0
                }

                Label {
                    //% "Clear selection"
                    text: qsTrId("peoplePickerDialog.clear")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.highlightColor
                    visible: selectedPeople.length > 0

                    MouseArea {
                        anchors.fill: parent
                        onClicked: selectedPeople = []
                    }
                }
            }

            Item {
                width: 1
                height: Theme.paddingMedium
            }
        }

        delegate: BackgroundItem {
            id: personDelegate
            width: peopleGrid.cellWidth
            height: peopleGrid.cellHeight

            property bool isSelected: peoplePickerDialog.selectedSet[model.personId] === true
            property real thumbnailSize: peopleGrid.cellWidth - Theme.paddingMedium

            Column {
                anchors.top: parent.top
                anchors.topMargin: Theme.paddingSmall / 2
                width: parent.width
                spacing: Theme.paddingSmall / 2

                Rectangle {
                    width: personDelegate.thumbnailSize
                    height: personDelegate.thumbnailSize
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "transparent"
                    border.width: isSelected ? 3 : 1
                    border.color: isSelected ? Theme.highlightColor : Theme.secondaryColor
                    radius: width / 2

                    Image {
                        id: personImage
                        anchors.fill: parent
                        anchors.margins: 2
                        source: model.thumbnailId ? "image://immich/person/" + model.thumbnailId : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: personDelegate.thumbnailSize
                        sourceSize.height: personDelegate.thumbnailSize
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
                        text: (model.name || "?").charAt(0).toUpperCase()
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.secondaryColor
                        visible: !model.thumbnailId
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
                    width: parent.width
                    //% "Unknown"
                    text: model.name || qsTrId("peoplePickerDialog.unknown")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    horizontalAlignment: Text.AlignHCenter
                    color: isSelected ? Theme.highlightColor : Theme.primaryColor
                }
            }

            onClicked: {
                var personId = model.personId
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

        EmptyState {
            visible: peopleModel.count === 0
            message: peopleModel.totalCount === 0
                //% "No people available"
                ? qsTrId("peoplePickerDialog.noPeople")
                //% "No matches found"
                : qsTrId("peoplePickerDialog.noMatches")
        }

        VerticalScrollDecorator {}
    }
}
