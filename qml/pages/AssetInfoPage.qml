import QtQuick 2.0
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0

Page {
    id: page

    property string assetId
    property var assetInfo

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader {
                //% "Asset Information"
                title: qsTrId("assetInfoPage.assetInformation")
            }

            DetailItem {
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.description && assetInfo.exifInfo.description !== ""
                //% "Description"
                label: qsTrId("assetInfoPage.description")
                value: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.description ? assetInfo.exifInfo.description : ""
            }

            DetailItem {
                //% "File name"
                label: qsTrId("assetInfoPage.fileNme")
                value: assetInfo ? assetInfo.originalFileName : ""
            }

            DetailItem {
                //% "Created"
                label: qsTrId("assetInfoPage.created")
                value: assetInfo ? Qt.formatDateTime(new Date(assetInfo.fileCreatedAt), "dd.MM.yyyy hh:mm") : ""
            }

            DetailItem {
                //% "Modified"
                label: qsTrId("assetInfoPage.modified")
                value: assetInfo ? Qt.formatDateTime(new Date(assetInfo.fileModifiedAt), "dd.MM.yyyy hh:mm") : ""
            }

            DetailItem {
                //% "Type"
                label: qsTrId("assetInfoPage.type")
                value: assetInfo ? assetInfo.type : ""
            }

            SectionHeader {
                //% "EXIF Information"
                text: qsTrId("assetInfoPage.exifInformation")
                visible: assetInfo && assetInfo.exifInfo
            }

            DetailItem {
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.make
                //% "Camera"
                label: qsTrId("assetInfoPage.camera")
                value: assetInfo && assetInfo.exifInfo ? (assetInfo.exifInfo.make + " " + assetInfo.exifInfo.model) : ""
            }

            DetailItem {
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.fNumber
                //% "Aperture"
                label: qsTrId("assetInfoPage.aperture")
                value: assetInfo && assetInfo.exifInfo ? "f/" + assetInfo.exifInfo.fNumber : ""
            }

            DetailItem {
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.exposureTime
                //% "Exposure time"
                label: qsTrId("assetInfoPage.exposureTime")
                value: assetInfo && assetInfo.exifInfo ? assetInfo.exifInfo.exposureTime + "s" : ""
            }

            DetailItem {
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.iso
                //% "ISO"
                label: qsTrId("assetInfoPage.iso")
                value: assetInfo && assetInfo.exifInfo ? assetInfo.exifInfo.iso : ""
            }

            DetailItem {
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.focalLength
                //% "Focal length"
                label: qsTrId("assetInfoPage.focalLength")
                value: assetInfo && assetInfo.exifInfo ? assetInfo.exifInfo.focalLength + "mm" : ""
            }

            SectionHeader {
                //% "People"
                text: qsTrId("assetInfoPage.people")
                visible: assetInfo && assetInfo.people && assetInfo.people.length > 0
            }

            Item {
                width: parent.width
                height: peopleFlow.height
                visible: assetInfo && assetInfo.people && assetInfo.people.length > 0

                Flow {
                    id: peopleFlow
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: {
                        var itemWidth = Theme.itemSizeMedium
                        var availableWidth = parent.width - 2 * Theme.horizontalPageMargin
                        var count = assetInfo && assetInfo.people ? assetInfo.people.length : 0
                        var maxPerRow = Math.floor((availableWidth + spacing) / (itemWidth + spacing))
                        var perRow = Math.min(count, maxPerRow)
                        return perRow * itemWidth + (perRow - 1) * spacing
                    }
                    spacing: Theme.paddingMedium

                    Repeater {
                        model: assetInfo && assetInfo.people ? assetInfo.people : []

                        BackgroundItem {
                            width: Theme.itemSizeMedium
                            height: Theme.itemSizeMedium + Theme.paddingSmall + Theme.fontSizeTiny

                            Column {
                                anchors.fill: parent
                                spacing: Theme.paddingSmall / 2

                                Rectangle {
                                    width: Theme.itemSizeMedium
                                    height: Theme.itemSizeMedium
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Theme.secondaryColor
                                    radius: width / 2

                                    Image {
                                        id: personThumbnail
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        source: modelData.id ? "image://immich/person/" + modelData.id : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource:  Item {
                                                width: personThumbnail.width
                                                height: personThumbnail.height
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                }
                                            }
                                        }
                                    }

                                    Label {
                                        anchors.centerIn: parent
                                        text: (modelData.name || "?").charAt(0).toUpperCase()
                                        font.pixelSize: Theme.fontSizeLarge
                                        color: Theme.secondaryColor
                                        visible: personThumbnail.status !== Image.Ready
                                    }
                                }

                                Label {
                                    width: Theme.itemSizeMedium
                                    //% "Unknown"
                                    text: modelData.name || qsTrId("assetInfoPage.unknownPerson")
                                    font.pixelSize: Theme.fontSizeTiny
                                    truncationMode: TruncationMode.Fade
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Theme.primaryColor
                                }
                            }

                            onClicked: {
                                if (modelData.id) {
                                    pageStack.push(Qt.resolvedUrl("SearchResultsPage.qml"), {
                                        personIds: [modelData.id],
                                        searchTitle: modelData.name || qsTrId("assetInfoPage.unknownPerson")
                                    })
                                }
                            }
                        }
                    }
                }
            }

            SectionHeader {
                //% "Location"
                text: qsTrId("assetInfoPage.location")
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.latitude
            }

            DetailItem {
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.latitude
                //% "Coordinates"
                label: qsTrId("assetInfoPage.coordinates")
                value: assetInfo && assetInfo.exifInfo ?
                    assetInfo.exifInfo.latitude.toFixed(6) + ", " + assetInfo.exifInfo.longitude.toFixed(6) : ""
            }

            DetailItem {
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.city
                //% "City"
                label: qsTrId("assetInfoPage.city")
                value: assetInfo && assetInfo.exifInfo ? assetInfo.exifInfo.city : ""
            }

            DetailItem {
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.country
                //% "Country"
                label: qsTrId("assetInfoPage.country")
                value: assetInfo && assetInfo.exifInfo ? assetInfo.exifInfo.country : ""
            }

            Button {
                visible: assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.latitude
                anchors.horizontalCenter: parent.horizontalCenter
                //% "Open in Maps"
                text: qsTrId("assetInfoPage.openInMaps")
                onClicked: {
                    if (assetInfo && assetInfo.exifInfo) {
                        Qt.openUrlExternally("geo:" + assetInfo.exifInfo.latitude + "," + assetInfo.exifInfo.longitude)
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
