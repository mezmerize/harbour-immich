import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page

    property string filePath: ""
    property bool backedUp: false

    property var info: null
    property var assetInfo: null
    readonly property var exif: (assetInfo && assetInfo.exifInfo) || null

    function formatBytes(bytes) {
        if (!bytes || bytes === 0) return "0 B"
        var k = 1024
        var sizes = ["B", "KB", "MB", "GB", "TB"]
        var i = Math.floor(Math.log(bytes) / Math.log(k))
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i]
    }

    Component.onCompleted: {
        info = backupManager.deviceFileInfo(filePath)
        assetInfo = assetDatabase.localAssetInfo(filePath)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader {
                //% "File Information"
                title: qsTrId("deviceAssetInfoPage.title")
            }

            DetailItem {
                visible: !!(exif && exif.description)
                //% "Description"
                label: qsTrId("assetInfoPage.description")
                value: !!(exif && exif.description) ? exif.description : ""
            }

            DetailItem {
                //% "Name"
                label: qsTrId("deviceAssetInfoPage.name")
                value: info ? info.fileName : ""
            }

            DetailItem {
                //% "Type"
                label: qsTrId("deviceAssetInfoPage.type")
                value: info && info.isVideo
                    //% "Video"
                    ? qsTrId("deviceAssetInfoPage.video")
                    //% "Photo"
                    : qsTrId("deviceAssetInfoPage.photo")
            }

            DetailItem {
                //% "Size"
                label: qsTrId("deviceAssetInfoPage.size")
                value: info ? formatBytes(info.fileSize) : ""
            }

            DetailItem {
                visible: !!(exif && exif.exifImageWidth && exif.exifImageHeight)
                //% "Resolution"
                label: qsTrId("assetInfoPage.resolution")
                value: !!(exif && exif.exifImageWidth && exif.exifImageHeight) ? exif.exifImageWidth + " x " + exif.exifImageHeight : ""
            }

            DetailItem {
                visible: !!(exif && exif.dateTimeOriginal)
                //% "Created"
                label: qsTrId("assetInfoPage.created")
                value: !!(exif && exif.dateTimeOriginal) ? Qt.formatDateTime(new Date(exif.dateTimeOriginal), "dd.MM.yyyy hh:mm:ss") : ""
            }

            DetailItem {
                //% "Last modified"
                label: qsTrId("deviceAssetInfoPage.lastModified")
                value: info && info.lastModified ? Qt.formatDateTime(info.lastModified, "dd.MM.yyyy hh:mm:ss") : ""
            }

            DetailItem {
                //% "Backup status"
                label: qsTrId("deviceAssetInfoPage.backupStatus")
                value: (info && info.backedUp) || page.backedUp
                    //% "Backed up"
                    ? qsTrId("deviceAssetInfoPage.backedUp")
                    //% "Not backed up"
                    : qsTrId("deviceAssetInfoPage.notBackedUp")
            }

            SectionHeader {
                //% "EXIF Information"
                text: qsTrId("assetInfoPage.exifInformation")
                visible: !!(exif && (exif.make || exif.model || exif.fNumber || exif.exposureTime || exif.iso || exif.focalLength))
            }

            DetailItem {
                visible: !!(exif && (exif.make || exif.model))
                //% "Camera"
                label: qsTrId("assetInfoPage.camera")
                value: exif ? (((exif.make || "") + " " + (exif.model || "")).trim()) : ""
            }

            DetailItem {
                visible: !!(exif && exif.fNumber)
                //% "Aperture"
                label: qsTrId("assetInfoPage.aperture")
                value: !!(exif && exif.fNumber) ? "f/" + exif.fNumber : ""
            }

            DetailItem {
                visible: !!(exif && exif.exposureTime)
                //% "Exposure time"
                label: qsTrId("assetInfoPage.exposureTime")
                value: !!(exif && exif.exposureTime) ? exif.exposureTime + "s" : ""
            }

            DetailItem {
                visible: !!(exif && exif.iso)
                //% "ISO"
                label: qsTrId("assetInfoPage.iso")
                value: !!(exif && exif.iso) ? exif.iso : ""
            }

            DetailItem {
                visible: !!(exif && exif.focalLength)
                //% "Focal length"
                label: qsTrId("assetInfoPage.focalLength")
                value: !!(exif && exif.focalLength) ? exif.focalLength + "mm" : ""
            }

            SectionHeader {
                //% "Location"
                text: qsTrId("assetInfoPage.location")
                visible: !!(exif && exif.latitude !== undefined)
            }

            DetailItem {
                visible: !!(exif && exif.latitude !== undefined)
                //% "Coordinates"
                label: qsTrId("assetInfoPage.coordinates")
                value: !!(exif && exif.latitude !== undefined) ? exif.latitude.toFixed(6) + ", " + exif.longitude.toFixed(6) : ""
            }

            Button {
                visible: !!(exif && exif.latitude !== undefined)
                anchors.horizontalCenter: parent.horizontalCenter
                //% "Open in Maps"
                text: qsTrId("assetInfoPage.openInMaps")
                onClicked: Qt.openUrlExternally("geo:" + exif.latitude + "," + exif.longitude)
            }
        }

        VerticalScrollDecorator {}
    }
}
