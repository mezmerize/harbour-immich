import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0

Item {
    id: memoriesBar
    width: parent.width
    height: (hasMemories || loading) ? memoriesList.height + Theme.paddingMedium * 2 : 0
    visible: hasMemories || loading

    property bool hasMemories: memoriesModel.count > 0 && memoriesLoaded
    property bool loading: false
    property bool memoriesLoaded: false

    property int thumbnailSize: settingsManager.memoriesThumbnailSize
    property int baseSize: Math.min(Screen.width, Screen.height)
    property int itemSize: thumbnailSize == 0 ? Math.floor(baseSize / 4) : thumbnailSize == 1 ? Math.floor(baseSize / 3) : Math.floor(baseSize / 2)

    MemoriesModel {
        id: memoriesModel
    }

    function loadMemories() {
        loading = true
        immichApi.fetchMemories()
    }

    function titleFor(year, memoryDate) {
        if (year <= 0 && memoryDate) {
            year = new Date(memoryDate).getFullYear()
        }
        if (year <= 0) return ""
        var yearsAgo = new Date().getFullYear() - year
        if (yearsAgo <= 0) yearsAgo = 1
        return yearsAgo === 1
            //% "A year ago"
            ? qsTrId("memoriesBar.yearAgo")
            //% "%1 years ago"
            : qsTrId("memoriesBar.yearsAgo").arg(yearsAgo)
    }

    Component.onCompleted: loadMemories()

    Connections {
        target: immichApi
        onMemoriesReceived: {
            memoriesModel.clear()
            memoriesModel.appendMemories(memories)
            memoriesBar.memoriesLoaded = true
            memoriesBar.loading = false
        }
        onMemoryUpdated: memoriesModel.setSaved(memoryId, isSaved)
        onErrorOccurred: memoriesBar.loading = false
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
    }

    SilicaListView {
        id: memoriesList
        width: parent.width
        height: memoriesBar.itemSize + Theme.paddingMedium
        anchors.verticalCenter: parent.verticalCenter
        orientation: ListView.Horizontal
        clip: true
        spacing: Theme.paddingMedium
        leftMargin: Theme.horizontalPageMargin
        rightMargin: Theme.horizontalPageMargin
        cacheBuffer: 256

        model: memoriesModel

        delegate: BackgroundItem {
            id: memoryDelegate
            width: memoriesBar.itemSize
            height: memoriesBar.itemSize

            Rectangle {
                anchors.fill: parent
                color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                radius: Theme.paddingSmall

                Image {
                    anchors.fill: parent
                    anchors.margins: 2
                    source: model.thumbhash ? "image://thumbhash/" + model.thumbhash : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                    smooth: true
                    visible: memoryImage.status !== Image.Ready
                }

                Image {
                    id: memoryImage
                    anchors.fill: parent
                    anchors.margins: 2
                    source: model.thumbnailId ? "image://immich/thumbnail/" + model.thumbnailId : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: memoriesBar.itemSize * 2
                    sourceSize.height: memoriesBar.itemSize * 2

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        radius: Theme.paddingSmall - 2
                        border.width: 2
                        border.color: Theme.highlightColor
                    }
                }

                // "N years ago" overlay at bottom
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: yearsAgoLabel.height + Theme.paddingSmall
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightDimmerColor, 0.8)

                    // Square off top corners by overlaying a rect
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: parent.radius
                        color: parent.color
                    }

                    Label {
                        id: yearsAgoLabel
                        anchors.centerIn: parent
                        text: memoriesBar.titleFor(model.memoryYear, model.memoryDate)
                        font.pixelSize: Theme.fontSizeTiny
                        font.bold: true
                        color: Theme.primaryColor
                    }
                }

                // Asset count badge
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Theme.paddingSmall / 2
                    width: countLabel.width + Theme.paddingSmall
                    height: countLabel.height + Theme.paddingSmall / 2
                    radius: height / 2
                    color: Theme.rgba(Theme.highlightDimmerColor, 0.8)
                    visible: model.assetCount > 1

                    Label {
                        id: countLabel
                        anchors.centerIn: parent
                        text: model.assetCount
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.primaryColor
                    }
                }
            }

            onClicked: {
                var assetsArray = JSON.parse(model.assetsJson)
                pageStack.push(Qt.resolvedUrl("../pages/MemoryDetailPage.qml"), {
                    memoryTitle: memoriesBar.titleFor(model.memoryYear, model.memoryDate),
                    memoryId: model.memoryId,
                    memoryIsSaved: model.isSaved,
                    assets: assetsArray
                })
            }
        }

        HorizontalScrollDecorator {}
    }

    LoadingIndicator {
        anchors.centerIn: parent
        loading: memoriesBar.loading && memoriesModel.count === 0
        useMonochrome: true
    }
}
