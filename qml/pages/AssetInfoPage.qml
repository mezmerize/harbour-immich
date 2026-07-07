import QtQuick 2.0
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0

Page {
    id: page

    property string assetId
    property var assetInfo
    property var assetAlbums: []
    property bool isOwnedByOther: assetInfo ? (assetInfo.ownerId !== undefined && assetInfo.ownerId !== authManager.userId) : false

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            enabled: !isOwnedByOther

            MenuItem {
                //% "Edit Asset"
                text: qsTrId("pullDownMenu.editAsset")
                onClicked: {
                    var currentDesc = assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.description ? assetInfo.exifInfo.description : ""
                    var hasLoc = assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.latitude ? true : false
                    var lat = hasLoc ? assetInfo.exifInfo.latitude : 0
                    var lng = hasLoc ? assetInfo.exifInfo.longitude : 0
                    pageStack.push(Qt.resolvedUrl("EditAssetDialog.qml"), {
                        assetId: page.assetId,
                        description: currentDesc,
                        latitude: lat,
                        longitude: lng,
                        hasLocation: hasLoc
                    })
                }
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader {
                //% "Asset Information"
                title: qsTrId("assetInfoPage.assetInformation")
            }

            DetailItem {
                //% "Description"
                label: qsTrId("assetInfoPage.description")
                value: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.description) ? assetInfo.exifInfo.description : ""
            }

            DetailItem {
                //% "File name"
                label: qsTrId("assetInfoPage.fileNme")
                value: !!(assetInfo && assetInfo.originalFileName) ? assetInfo.originalFileName : ""
            }

            DetailItem {
                //% "Created"
                label: qsTrId("assetInfoPage.created")
                value: !!(assetInfo && assetInfo.fileCreatedAt) ? Qt.formatDateTime(new Date(assetInfo.fileCreatedAt), "dd.MM.yyyy hh:mm") : ""
            }

            DetailItem {
                //% "Modified"
                label: qsTrId("assetInfoPage.modified")
                value: !!(assetInfo && assetInfo.fileModifiedAt) ? Qt.formatDateTime(new Date(assetInfo.fileModifiedAt), "dd.MM.yyyy hh:mm") : ""
            }

            DetailItem {
                //% "Type"
                label: qsTrId("assetInfoPage.type")
                value: !!(assetInfo && assetInfo.type) ? assetInfo.type : ""
            }

            SectionHeader {
                //% "EXIF Information"
                text: qsTrId("assetInfoPage.exifInformation")
                visible: !!(assetInfo && assetInfo.exifInfo && (assetInfo.exifInfo.make || assetInfo.exifInfo.fNumber || assetInfo.exifInfo.exposureTime || assetInfo.exifInfo.iso || assetInfo.exifInfo.focalLength))
            }

            DetailItem {
                visible: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.make)
                //% "Camera"
                label: qsTrId("assetInfoPage.camera")
                value: !!(assetInfo && assetInfo.exifInfo) ? (assetInfo.exifInfo.make + " " + assetInfo.exifInfo.model) : ""
            }

            DetailItem {
                visible: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.fNumber)
                //% "Aperture"
                label: qsTrId("assetInfoPage.aperture")
                value: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.fNumber) ? "f/" + assetInfo.exifInfo.fNumber : ""
            }

            DetailItem {
                visible: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.exposureTime)
                //% "Exposure time"
                label: qsTrId("assetInfoPage.exposureTime")
                value: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.exposureTime) ? assetInfo.exifInfo.exposureTime + "s" : ""
            }

            DetailItem {
                visible: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.iso)
                //% "ISO"
                label: qsTrId("assetInfoPage.iso")
                value: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.iso) ? assetInfo.exifInfo.iso : ""
            }

            DetailItem {
                visible: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.focalLength)
                //% "Focal length"
                label: qsTrId("assetInfoPage.focalLength")
                value: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.focalLength) ? assetInfo.exifInfo.focalLength + "mm" : ""
            }

            SectionHeader {
                //% "People"
                text: qsTrId("assetInfoPage.people")
                visible: !!(assetInfo && assetInfo.people && assetInfo.people.length > 0)
            }

            Item {
                width: parent.width
                height: peopleFlow.height
                visible: !!(assetInfo && assetInfo.people && assetInfo.people.length > 0)

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
                visible: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.latitude)
            }

            DetailItem {
                visible: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.latitude)
                //% "Coordinates"
                label: qsTrId("assetInfoPage.coordinates")
                value: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.latitude) ? assetInfo.exifInfo.latitude.toFixed(6) + ", " + assetInfo.exifInfo.longitude.toFixed(6) : ""
            }

            DetailItem {
                visible: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.city)
                //% "City"
                label: qsTrId("assetInfoPage.city")
                value: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.city) ? assetInfo.exifInfo.city : ""
            }

            DetailItem {
                visible: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.country)
                //% "Country"
                label: qsTrId("assetInfoPage.country")
                value: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.country) ? assetInfo.exifInfo.country : ""
            }

            Button {
                visible: !!(assetInfo && assetInfo.exifInfo && assetInfo.exifInfo.latitude)
                anchors.horizontalCenter: parent.horizontalCenter
                //% "Open in Maps"
                text: qsTrId("assetInfoPage.openInMaps")
                onClicked: {
                    if (assetInfo && assetInfo.exifInfo) {
                        Qt.openUrlExternally("geo:" + assetInfo.exifInfo.latitude + "," + assetInfo.exifInfo.longitude)
                    }
                }
            }

            SectionHeader {
                //% "Owner"
                text: qsTrId("assetInfoPage.owner")
                visible: !!(assetInfo && assetInfo.owner)
            }

            DetailItem {
                visible: !!(assetInfo && assetInfo.owner && assetInfo.owner.name)
                //% "Name"
                label: qsTrId("assetInfoPage.ownerName")
                value: !!(assetInfo && assetInfo.owner) ? assetInfo.owner.name : ""
            }

            DetailItem {
                visible: !!(assetInfo && assetInfo.owner && assetInfo.owner.email)
                //% "Email"
                label: qsTrId("assetInfoPage.ownerEmail")
                value: !!(assetInfo && assetInfo.owner) ? assetInfo.owner.email : ""
            }

            SectionHeader {
                //% "Albums"
                text: qsTrId("assetInfoPage.albums")
                visible: assetAlbums.length > 0
            }

            Repeater {
                model: assetAlbums

                BackgroundItem {
                    id: albumItem
                    width: parent.width
                    height: Theme.itemSizeMedium

                    Row {
                        anchors {
                            fill: parent
                            leftMargin: Theme.horizontalPageMargin
                            rightMargin: Theme.horizontalPageMargin
                        }
                        spacing: Theme.paddingMedium

                        Image {
                            id: albumThumbnail
                            width: Theme.itemSizeMedium
                            height: Theme.itemSizeMedium
                            source: modelData.albumThumbnailAssetId ? "image://immich/thumbnail/" + modelData.albumThumbnailAssetId : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true

                            Rectangle {
                                anchors.fill: parent
                                color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                                visible: albumThumbnail.status !== Image.Ready
                            }

                            Image {
                                anchors.centerIn: parent
                                source: "image://theme/icon-m-image"
                                visible: albumThumbnail.status !== Image.Ready
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - albumThumbnail.width - Theme.paddingMedium

                            Label {
                                width: parent.width
                                text: modelData.albumName || ""
                                color: albumItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                            }

                            Row {
                                spacing: Theme.paddingSmall

                                Label {
                                    text: modelData.assetCount === 1
                                        //% "1 asset"
                                        ? qsTrId("assetInfoPage.asset")
                                        //% "%1 assets"
                                        : qsTrId("assetInfoPage.assets").arg(modelData.assetCount || 0)
                                    color: albumItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                                    font.pixelSize: Theme.fontSizeSmall
                                }

                                Rectangle {
                                    width: sharedLabel.width + Theme.paddingSmall * 2
                                    height: sharedLabel.height + Theme.paddingSmall
                                    radius: Theme.paddingSmall / 2
                                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                                    visible: modelData.shared
                                    anchors.verticalCenter: parent.verticalCenter

                                    Label {
                                        id: sharedLabel
                                        anchors.centerIn: parent
                                        //% "Shared"
                                        text: qsTrId("assetInfoPage.shared")
                                        font.pixelSize: Theme.fontSizeExtraSmall
                                        color: Theme.highlightColor
                                    }
                                }
                            }
                        }
                    }

                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("AlbumDetailPage.qml"), {
                            albumId: modelData.id,
                            albumName: modelData.albumName || "",
                            albumDescription: modelData.description || "",
                            albumStartDate: modelData.startDate || "",
                            albumEndDate: modelData.endDate || ""
                        })
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

    Component.onCompleted: {
        if (assetId) {
            immichApi.fetchAlbumsForAsset(assetId)
        }
    }

    Connections {
        target: immichApi
        onAlbumUpdated: {
            if (assetId) {
                immichApi.fetchAlbumsForAsset(assetId)
            }
        }
        onAssetAlbumsReceived: {
            if (assetId === page.assetId) {
                page.assetAlbums = albums
            }
        }
        onAssetUpdated: {
            if (assetId === page.assetId && page.assetInfo) {
                var info = page.assetInfo
                if (!info.exifInfo) info.exifInfo = {}
                info.exifInfo.description = description
                if (latitude !== 0 || longitude !== 0) {
                    info.exifInfo.latitude = latitude
                    info.exifInfo.longitude = longitude
                }
                page.assetInfo = null
                page.assetInfo = info
            }
        }
    }
}
