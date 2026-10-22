import QtQuick 2.6
import Sailfish.Silica 1.0

SilicaFlickable {
    id: grid

    property var assetModel: timelineModel
    property int columns: 4
    property real cellSize: width / Math.max(1, columns)
    property string highlightAssetId: ""
    property Component headerComponent: null
    property bool pinchEnabled: true
    property real viewportMargin: Math.max(height, cellSize * 3)

    property int pinchColumns: -1
    readonly property int activeColumns: pinchColumns > 0 ? pinchColumns : columns
    readonly property real activeCellSize: width / Math.max(1, activeColumns)

    readonly property real modelViewTop: Math.max(0, contentY - rowLayer.y - viewportMargin)
    readonly property real modelViewBottom: Math.min(assetModel ? assetModel.renderContentHeight : 0, contentY + height - rowLayer.y + viewportMargin)
    readonly property int firstVisibleRow: assetModel ? (assetModel.layoutVersion, assetModel.firstRowAtY(modelViewTop)) : 0
    readonly property int lastVisibleRow: assetModel ? (assetModel.layoutVersion, assetModel.lastRowAtY(modelViewBottom)) : -1
    readonly property int poolSize: {
        if (!assetModel) return 0
        var minRow = Math.min(Math.max(activeCellSize, 10), Math.max(Theme.itemSizeExtraSmall, 10))
        return Math.ceil((height + 2 * viewportMargin) / minRow) + 4
    }
    readonly property real gridContentHeight: assetModel ? assetModel.renderContentHeight : 0

    // Scroll to asset state
    property int pendingBucket: -1
    property int pendingAssetIndex: -1
    property string pendingAssetId: ""
    property bool pendingJumped: false
    property real lastHeaderHeight: 0

    property real scrollComp: 0
    property alias headerItem: headerLoader.item
    readonly property real headerHeight: headerLoader.height

    signal assetClicked(string assetId, bool isFavorite, bool isVideo, string thumbhash, int currentIndex, string stackId, int stackAssetCount)
    signal localAssetClicked(int globalIndex)
    signal columnsSettled(int columns)
    signal assetScrolled(string assetId)

    function syncGeometry() {
        if (!assetModel) return
        assetModel.columns = activeColumns
        assetModel.cellSize = activeCellSize
        assetModel.monthHeaderHeight = Theme.itemSizeSmall
        assetModel.dayHeaderHeight = Theme.itemSizeExtraSmall
    }

    function updateVisibleLoads() {
        if (!assetModel || assetModel.renderRowCount <= 0) return
        var first = assetModel.firstRowAtY(modelViewTop)
        var last = assetModel.lastRowAtY(modelViewBottom)
        if (last < first) return
        var seen = {}
        for (var r = first; r <= last; ++r) {
            var row = assetModel.renderRowAt(r)
            if (row.bucketIndex === undefined || row.bucketIndex < 0) continue
            if (seen[row.bucketIndex]) continue
            seen[row.bucketIndex] = true
            if (row.needsLoad) {
                assetModel.requestBucketLoad(row.bucketIndex)
            }
        }
    }

    function resetScroll() {
        pendingBucket = -1
        pendingAssetIndex = -1
        pendingAssetId = ""
        pendingJumped = false
        scrollComp = 0
        contentY = 0
    }

    function scrollToAssetRow(bucketIndex, assetIndex, assetId) {
        pendingBucket = bucketIndex
        pendingAssetIndex = assetIndex
        pendingAssetId = assetId
        pendingJumped = false
        tryPendingScroll()
    }

    function tryPendingScroll() {
        if (pendingBucket < 0 || !assetModel) return
        var rowIndex = assetModel.rowIndexForAsset(pendingBucket, pendingAssetIndex)
        if (rowIndex < 0) {
            pendingBucket = -1
            return
        }
        var row = assetModel.renderRowAt(rowIndex)
        if (!row || row.y === undefined || isNaN(row.y)) {
            pendingBucket = -1
            pendingAssetIndex = -1
            pendingAssetId = ""
            pendingJumped = false
            return
        }
        foldComp()
        var targetY = rowLayer.y + row.y + row.height / 2 - height / 2
        var maxY = Math.max(0, contentHeight - height)
        if (row.loading) {
            if (!row.inflight) {
                assetModel.requestBucketLoad(pendingBucket)
                if (!pendingJumped) {
                    pendingJumped = true
                    contentY = Math.max(0, Math.min(targetY, maxY))
                }
            }
            return
        }
        pendingJumped = false
        contentY = Math.max(0, Math.min(targetY, maxY))
        var assetId = pendingAssetId
        pendingBucket = -1
        pendingAssetIndex = -1
        pendingAssetId = ""
        if (assetId !== "") {
            assetScrolled(assetId)
        }
    }

    function feedViewport() {
        if (!assetModel || !rowLayer) return
        assetModel.setViewport(contentY - rowLayer.y, height)
    }

    function shift(dy) {
        if (moving) scrollComp -= dy
        else contentY = Math.max(0, Math.min(contentY + dy, Math.max(0, contentHeight - height)))
        feedViewport()
    }

    function foldComp() {
        var c = scrollComp
        if (c === 0) return
        if (c < 0) {
            scrollComp = 0
            contentY -= c
        } else {
            contentY = Math.max(0, contentY - c)
            scrollComp = 0
        }
        feedViewport()
    }

    clip: true
    contentHeight: rowLayer.y + gridContentHeight + Theme.paddingLarge
    contentWidth: width
    pixelAligned: true

    onAssetModelChanged: {
        syncGeometry()
        feedViewport()
    }
    onActiveColumnsChanged: syncGeometry()
    onActiveCellSizeChanged: syncGeometry()
    onColumnsChanged: pinchColumns = -1
    onContentYChanged: {
        feedViewport()
        updateVisibleLoads()
    }
    onHeightChanged: {
        feedViewport()
        updateVisibleLoads()
    }
    onMovingChanged: if (!moving) foldComp()

    Component.onCompleted: {
        syncGeometry()
        feedViewport()
    }

    Connections {
        target: assetModel
        onLayoutShifted: grid.shift(dy)
        onRenderLayoutChanged: {
            grid.updateVisibleLoads()
            grid.tryPendingScroll()
        }
    }

    PinchArea {
        width: grid.width
        height: Math.max(grid.contentHeight, grid.height)
        pinch.target: null

        property int startColumns: 0

        onPinchStarted: {
            if (!grid.pinchEnabled) return
            startColumns = grid.activeColumns
        }
        onPinchUpdated: {
            if (!grid.pinchEnabled) return
            if (startColumns <= 0 || pinch.scale <= 0) return
            var cols = Math.max(2, Math.min(8, Math.round(startColumns / pinch.scale)))
            if (cols !== grid.pinchColumns && cols !== grid.activeColumns) {
                grid.pinchColumns = cols
            }
        }
        onPinchFinished: {
            if (!grid.pinchEnabled) return
            if (grid.pinchColumns > 0 && grid.pinchColumns !== grid.columns) {
                grid.columnsSettled(grid.pinchColumns)
            } else if (grid.pinchColumns === grid.columns) {
                grid.pinchColumns = -1
            }
        }

        // Header
        Loader {
            id: headerLoader
            width: grid.width
            sourceComponent: grid.headerComponent

            onHeightChanged: {
                var d = height - grid.lastHeaderHeight
                grid.lastHeaderHeight = height
                grid.feedViewport()
                if (grid.contentY > 0 && d !== 0) grid.shift(d)
            }
        }

        // Row container
        Item {
            id: rowLayer
            y: headerLoader.height + grid.scrollComp
            width: grid.width
            height: grid.gridContentHeight

            Repeater {
                model: grid.poolSize

                Item {
                    id: poolItem

                    property int rowIndex: {
                        var pool = grid.poolSize
                        if (pool <= 0 || grid.assetModel === null) return -1
                        var first = grid.firstVisibleRow
                        var r = first - (first % pool) + index
                        if (r < first) r += pool
                        return r < grid.assetModel.renderRowCount ? r : -1
                    }
                    property var row: {
                        if (!grid.assetModel) return null
                        grid.assetModel.layoutVersion
                        return rowIndex >= 0 ? grid.assetModel.renderRowAt(rowIndex) : null
                    }
                    property string contentKey: row ? (row.contentKey || "") : ""
                    property var rowAssets: {
                        var k = contentKey
                        if (!grid.assetModel || rowIndex < 0 || k === "") return null
                        return grid.assetModel.renderRowAssets(rowIndex)
                    }
                    property bool inWindow: rowIndex >= grid.firstVisibleRow && rowIndex <= grid.lastVisibleRow && row !== null

                    visible: inWindow
                    x: 0
                    y: row ? row.y : 0
                    width: grid.width
                    height: row ? row.height : 0

                    // Month header
                    Rectangle {
                        anchors.fill: parent
                        visible: inWindow && row && row.type === 0
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            text: (inWindow && row && row.type === 0) ? row.label : ""
                            font.pixelSize: Theme.fontSizeLarge
                            font.bold: true
                            color: Theme.highlightColor
                        }
                    }

                    // Day subgroup header
                    Item {
                        anchors.fill: parent
                        visible: inWindow && row && row.type === 1

                        property var groupAssetIds: {
                            if (!inWindow || !poolItem.rowAssets) return []
                            var ids = []
                            for (var i = 0; i < poolItem.rowAssets.length; i++) {
                                ids.push(poolItem.rowAssets[i].id)
                            }
                            return ids
                        }
                        property bool isGroupSelected: {
                            if (!grid.assetModel || grid.assetModel.selectedCount === 0) return false
                            return grid.assetModel.areAllAssetsSelected(groupAssetIds)
                        }

                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            text: (inWindow && row && row.type === 1) ? row.label : ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.secondaryHighlightColor
                        }

                        IconButton {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                            visible: parent.groupAssetIds.length > 0
                            anchors.verticalCenter: parent.verticalCenter
                            icon.source: parent.isGroupSelected ? "image://theme/icon-m-remove" : "image://theme/icon-m-add"
                            icon.color: parent.isGroupSelected ? Theme.errorColor : Theme.primaryColor
                            onClicked: grid.assetModel.setSelectionForAssets(parent.groupAssetIds, !parent.isGroupSelected)
                        }
                    }

                    // Asset row
                    Row {
                        anchors.fill: parent
                        visible: inWindow && row && row.type === 2

                        Repeater {
                            model: (inWindow && row && row.type === 2) ? poolItem.rowAssets : null

                            AssetGridItem {
                                id: gridItem
                                width: grid.activeCellSize
                                height: grid.activeCellSize
                                assetId: modelData.id
                                isFavorite: modelData.isFavorite
                                isSelected: {
                                    grid.assetModel.selectedCount
                                    return grid.assetModel.isAssetSelected(modelData.id)
                                }
                                isVideo: modelData.type === "VIDEO"
                                isLocal: modelData.isLocal || false
                                localPath: modelData.localPath || ""
                                assetIndex: modelData.assetIndex
                                thumbhash: modelData.thumbhash || ""
                                duration: modelData.duration || ""
                                stackId: modelData.stackId || ""
                                stackAssetCount: modelData.stackAssetCount || 0
                                livePhotoVideoId: modelData.livePhotoVideoId || ""
                                isHighlighted: grid.highlightAssetId === modelData.id

                                onClicked: {
                                    if (grid.assetModel.selectedCount > 0) {
                                        grid.assetModel.toggleSelection(row.bucketIndex, modelData.assetIndex)
                                    } else if (modelData.isLocal) {
                                        grid.localAssetClicked(grid.assetModel.globalIndexForAssetId(modelData.id))
                                    } else {
                                        grid.assetClicked(modelData.id, gridItem.isFavorite, modelData.type === "VIDEO", modelData.thumbhash || "", grid.assetModel.globalIndexForAssetId(modelData.id), modelData.stackId || "", modelData.stackAssetCount || 0)
                                    }
                                }
                                onPressAndHold: grid.assetModel.toggleSelection(row.bucketIndex, modelData.assetIndex)
                                onAddToSelection: grid.assetModel.toggleSelection(row.bucketIndex, modelData.assetIndex)
                            }
                        }
                    }

                    // Placeholder for an unloaded bucket
                    Item {
                        anchors.fill: parent
                        visible: inWindow && row && row.type === 3
                        clip: true

                        Repeater {
                            model: {
                                if (!inWindow || !row || row.type !== 3) return 0
                                var maxTiles = Math.ceil(grid.height / grid.activeCellSize + 1) * grid.activeColumns
                                return Math.min(row.bucketCount || 0, maxTiles)
                            }

                            Rectangle {
                                property int tileIndex: index
                                width: grid.activeCellSize
                                height: grid.activeCellSize
                                x: (tileIndex % Math.max(1, grid.activeColumns)) * grid.activeCellSize
                                y: Math.floor(tileIndex / Math.max(1, grid.activeColumns)) * grid.activeCellSize
                                color: Theme.rgba(Theme.highlightBackgroundColor, 0.06)
                                border.width: 1
                                border.color: Theme.rgba(Theme.primaryColor, 0.03)
                            }
                        }

                        LoadingIndicator {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.min(parent.height / 2, grid.height / 2) - height / 2
                            loading: inWindow && row && row.type === 3 && row.loading
                            useMonochrome: true
                        }
                    }
                }
            }
        }
    }
}
