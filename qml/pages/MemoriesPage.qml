import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"

Page {
    id: page

    property bool loading: true
    property bool loadingPage: false
    property bool showFavorites: false
    property bool showUpcoming: false
    property string sortOrder: "desc"
    property int pageSize: 20
    property int currentPage: 0

    MemoriesModel {
        id: memoriesModel
    }

    function queryParams() {
        var params = {"order": sortOrder, "isTrashed": "false"}
        if (showFavorites) params["isSaved"] = "true"
        if (showUpcoming) params["isUpcoming"] = "true"
        return params
    }

    function refresh() {
        loading = true
        loadingPage = false
        currentPage = 0
        memoriesModel.clear()
        immichApi.fetchMemoriesStatistics(queryParams())
    }

    function loadNextPage() {
        if (loadingPage) return
        if (memoriesModel.count >= memoriesModel.totalCount) return
        loadingPage = true
        var params = queryParams()
        params["page"] = currentPage + 1
        params["size"] = pageSize
        immichApi.searchMemories(params)
    }

    function memoryDetailTitle(year) {
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
        cellHeight: cellWidth
        cacheBuffer: Math.round(cellHeight * 3)

        model: memoriesModel

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
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

            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.paddingSmall / 2
                color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                radius: Theme.paddingSmall

                Image {
                    id: thumbhashImage
                    anchors.fill: parent
                    anchors.margins: 2
                    fillMode: Image.PreserveAspectCrop
                    source: model.thumbhash ? "image://thumbhash/" + model.thumbhash : ""
                    visible: memoryImage.status !== Image.Ready
                    asynchronous: false
                    smooth: true
                }

                Image {
                    id: memoryImage
                    anchors.fill: parent
                    anchors.margins: 2
                    source: model.thumbnailId ? "image://immich/thumbnail/" + model.thumbnailId : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: memoriesGrid.cellWidth
                    sourceSize.height: memoriesGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        radius: Theme.paddingSmall - 2
                        border.width: memoryDelegate.highlighted ? 3 : 0
                        border.color: Theme.highlightColor
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

                // Memory date overlay at bottom
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: dateLabel.height + Theme.paddingSmall
                    radius: Theme.paddingSmall
                    color: Theme.rgba("black", 0.6)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: parent.radius
                        color: parent.color
                    }

                    Label {
                        id: dateLabel
                        anchors.centerIn: parent
                        text: model.memoryDate ? Qt.formatDate(new Date(model.memoryDate), "dd MMMM yyyy") : ""
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.lightPrimaryColor
                    }
                }
            }

            onClicked: {
                pageStack.push(Qt.resolvedUrl("MemoryDetailPage.qml"), {
                    memoryTitle: page.memoryDetailTitle(model.memoryYear),
                    memoryId: model.memoryId,
                    memoryIsSaved: model.isSaved,
                    assets: JSON.parse(model.assetsJson)
                })
            }
        }

        onContentYChanged: {
            if (contentHeight > 0 && contentY + height > contentHeight - cellHeight * 2) page.loadNextPage()
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
        target: immichApi
        onMemoriesStatisticsReceived: {
            memoriesModel.totalCount = total
            if (total > 0) {
                page.loadNextPage()
            } else {
                page.loading = false
                page.loadingPage = false
            }
        }
        onMemoriesSearchReceived: {
            memoriesModel.appendMemories(memories)
            page.currentPage = pageNumber
            page.loading = false
            page.loadingPage = false
            // Keep loading until the viewport filled
            if (memoriesModel.count < memoriesModel.totalCount && memoriesGrid.contentHeight <= memoriesGrid.height) {
                page.loadNextPage()
            }
        }
        onMemoryUpdated: memoriesModel.setSaved(memoryId, isSaved)
    }
}
