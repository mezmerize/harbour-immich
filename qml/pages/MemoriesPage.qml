import QtQuick 2.6
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0
import harbour.immich.models 1.0
import "../components"

Page {
    id: page

    property bool loading: true
    property bool showFavorites: false
    property bool showUpcoming: false
    property string sortOrder: "desc"

    MemoriesModel {
        id: memoriesModel
    }

    function queryParams() {
        var params = {"order": sortOrder, "requestTag": "memoriesPage"}
        if (showFavorites) params["isSaved"] = "true"
        if (showUpcoming) params["isUpcoming"] = "true"
        return params
    }

    function refresh() {
        loading = true
        immichApi.fetchMemories(queryParams())
    }

    function memoryDetailTitle(year, type, personName) {
        if (type === "birthday") {
            //% "%1's birthday"
            return qsTrId("memoriesPage.birthdayTitle").arg(personName ||
                //% "Unknown"
                qsTrId("memoriesPage.unknownPerson"))
        }
        //% "Memory"
        if (year <= 0) return qsTrId("memoriesPage.memory")
        var yearsAgo = new Date().getFullYear() - year
        //% "This year"
        if (yearsAgo <= 0) return qsTrId("memoriesPage.thisYear")
        //% "A year ago"
        if (yearsAgo === 1) return qsTrId("memoriesPage.yearAgo")
        //% "%1 years ago"
        return qsTrId("memoriesPage.yearsAgo").arg(yearsAgo)
    }

    SilicaGridView {
        id: memoriesGrid
        anchors.fill: parent
        clip: true
        currentIndex: -1
        cellWidth: width / (page.isPortrait ? 2 : 4)
        cellHeight: cellWidth + Theme.fontSizeSmall + Theme.fontSizeExtraSmall + 2 * Theme.paddingMedium + Theme.paddingSmall
        cacheBuffer: Math.round(cellHeight * 3)

        model: memoriesModel

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: syncEngine.sync()
            }
        }

        header: Column {
            width: memoriesGrid.width

            PageHeader {
                //% "Memories"
                title: qsTrId("memoriesPage.memories")
            }

            MemoriesFilterBar {
                width: parent.width
                sortOrder: page.sortOrder
                showFavorites: page.showFavorites
                showUpcoming: page.showUpcoming
                onFilterFavorites: {
                    page.showFavorites = showFavorites
                    page.refresh()
                }
                onFilterUpcoming: {
                    page.showUpcoming = showUpcoming
                    page.refresh()
                }
                onSortOrderToggled: {
                    page.sortOrder = order
                    page.refresh()
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingSmall
            }
        }

        delegate: BackgroundItem {
            id: memoryDelegate
            width: memoriesGrid.cellWidth
            height: memoriesGrid.cellHeight

            Item {
                anchors.fill: parent
                anchors.leftMargin: Theme.paddingMedium / 2
                anchors.rightMargin: Theme.paddingMedium / 2

                Item {
                    id: memoryImageArea
                    width: parent.width
                    height: width

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                        radius: Theme.paddingMedium
                        visible: memoryImage.status !== Image.Ready
                    }

                    Image {
                        id: thumbhashImage
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: model.thumbhash ? "image://thumbhash/" + model.thumbhash : ""
                        asynchronous: false
                        smooth: true
                        visible: memoryImage.status !== Image.Ready
                        layer.enabled: memoryImage.status !== Image.Ready
                        layer.effect: OpacityMask {
                            maskSource: Item {
                                width: thumbhashImage.width
                                height: thumbhashImage.height

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.paddingMedium
                                }
                            }
                        }
                    }

                    Image {
                        id: memoryImage
                        anchors.fill: parent
                        source: model.thumbnailId ? "image://immich/thumbnail/" + model.thumbnailId : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: memoriesGrid.cellWidth
                        sourceSize.height: memoriesGrid.cellHeight
                        visible: status === Image.Ready
                        layer.enabled: status === Image.Ready
                        layer.effect: OpacityMask {
                            maskSource: Item {
                                width: memoryImage.width
                                height: memoryImage.height

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.paddingMedium
                                }
                            }
                        }
                    }

                    // Favorite indicator
                    Icon {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Theme.paddingSmall
                        width: Theme.iconSizeSmall
                        height: Theme.iconSizeSmall
                        source: "image://theme/icon-s-favorite"
                        visible: model.isSaved
                    }
                }

                // Memory date overlay at bottom
                Label {
                    id: dateLabel
                    anchors.top: memoryImageArea.bottom
                    anchors.topMargin: Theme.paddingSmall
                    width: parent.width
                    text: model.memoryDate ? (new Date(model.memoryDate)).toLocaleDateString() : ""
                    color: memoryDelegate.highlighted ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    truncationMode: TruncationMode.Fade
                }

                Label {
                    anchors.top: dateLabel.bottom
                    width: parent.width
                    text: (model.assetCount === 1
                        //% "1 asset"
                        ? qsTrId("memoriesPage.asset")
                        //% "%1 assets"
                        : qsTrId("memoriesPage.assets").arg(model.assetCount))
                    color: memoryDelegate.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }

            onClicked: {
                pageStack.push(Qt.resolvedUrl("MemoryDetailPage.qml"), {
                    memoryTitle: page.memoryDetailTitle(model.memoryYear, model.memoryType, model.personName),
                    birthYear: model.memoryType === "birthday" ? model.memoryYear : 0,
                    memoryId: model.memoryId,
                    memoryIsSaved: model.isSaved,
                    assets: JSON.parse(model.assetsJson)
                })
            }
        }

        VerticalScrollDecorator {}
    }

    LoadingIndicator {
        anchors.fill: parent
        loading: page.loading && memoriesModel.count === 0
        //% "Loading memories..."
        message: qsTrId("memoriesPage.loading")
    }

    EmptyState {
        anchors.fill: parent
        visible: !page.loading && memoriesModel.count === 0
        iconSource: "image://theme/icon-m-image"
        //% "No memories found"
        message: qsTrId("memoriesPage.noMemories")
    }

    Component.onCompleted: page.refresh()

    Connections {
        target: syncEngine
        onSyncFinished: if (ok) page.refresh()
    }

    Connections {
        target: immichApi
        onMemoriesReceived: {
            if (tag !== "memoriesPage") return
            memoriesModel.clear()
            memoriesModel.appendMemories(memories)
            page.loading = false
        }
        onMemoryUpdated: memoriesModel.setSaved(memoryId, isSaved)
    }
}
