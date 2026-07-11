import QtQuick 2.0
import Sailfish.Silica 1.0

Column {
    id: bucketColumn
    spacing: 0

    // Required properties from parent
    property int bucketIndex
    property string bucketKey: ""
    property real cellSize
    property int assetsPerRow
    property string highlightAssetId: ""
    property bool autoLoadAssets: true
    property var assetModel: timelineModel
    property Flickable viewportFlickable: ListView.view

    // Public state (read by parent for scroll-to-asset)
    property var bucketData: null
    property var bucketSubGroups: null
    property int bucketAssetCount: bucketData && typeof bucketData.count === "number" ? bucketData.count : 0
    property bool isFirstOfMonth: false
    property bool dataLoaded: false
    property bool assetsLoaded: false
    property bool initialized: false

    // Rendered area
    property var rowLayout: []
    property real bucketContentHeight: 0
    property real contentTop: 0
    property real viewportMargin: viewportFlickable ? Math.max(viewportFlickable.height, cellSize * 3) : 0

    property int firstVisibleRow: {
        if (!assetsLoaded || rowLayout.length === 0) return 0
        if (!viewportFlickable) return 0
        return firstRowAtOrAfter(viewportFlickable.contentY - contentTop - viewportMargin)
    }
    property int lastVisibleRow: {
        if (!assetsLoaded || rowLayout.length === 0) return -1
        if (!viewportFlickable) return rowLayout.length - 1
        return lastRowAfterOrBefore(viewportFlickable.contentY + viewportFlickable.height - contentTop + viewportMargin)
    }
    property int poolRowCount: {
        if (!viewportFlickable || cellSize <= 0) return 0
        var minRow = Math.min(cellSize, Theme.itemSizeExtraSmall)
        if (minRow <= 0) return 0
        return Math.ceil((viewportFlickable.height + 2 * viewportMargin) / minRow) + 4
    }
    property real visibleCenterY: {
        if (!viewportFlickable) return 0
        var caTop = contentTop
        var caBottom = contentTop + contentArea.height
        var visTop = Math.max(viewportFlickable.contentY, caTop)
        var visBottom = Math.min(viewportFlickable.contentY + viewportFlickable.height, caBottom)
        if (visBottom <= visTop) return 0
        return (visTop + visBottom) / 2 - caTop
    }

    visible: !assetsLoaded || (bucketSubGroups && bucketSubGroups.length > 0)

    // Signals for parent to handle navigation
    signal assetClicked(string assetId, bool isFavorite, bool isVideo, string thumbhash, int currentIndex, string stackId, int stackAssetCount)

    Component.onCompleted: {
        initialized = true
        resetState()
        updateContentTop()
    }

    onBucketIndexChanged: {
        if (initialized) {
            resetState()
        }
    }

    onBucketKeyChanged: {
        if (initialized) {
            resetState()
        }
    }

    onAutoLoadAssetsChanged: {
        if (autoLoadAssets) {
            loadBucketData()
            requestAssets()
        }
    }

    onCellSizeChanged: {
        if (assetsLoaded) {
            buildRowLayout()
            updateContentTop()
        }
    }

    onAssetsPerRowChanged: {
        if (assetsLoaded) {
            buildRowLayout()
            updateContentTop()
        }
    }

    onYChanged: updateContentTop()

    function resetState() {
        bucketData = null
        bucketSubGroups = null
        rowLayout = []
        bucketContentHeight = 0
        isFirstOfMonth = false
        dataLoaded = false
        assetsLoaded = false
        loadBucketData()
        if (autoLoadAssets) {
            requestAssets()
        }
    }

    function loadBucketData() {
        if (dataLoaded || !assetModel) return
        bucketData = assetModel.getBucketAt(bucketIndex)
        if (bucketIndex === 0) {
            isFirstOfMonth = true
        } else if (bucketData) {
            var prevBucket = assetModel.getBucketAt(bucketIndex - 1)
            isFirstOfMonth = prevBucket ? prevBucket.monthYear !== bucketData.monthYear : false
        }
        dataLoaded = true
    }

    function requestAssets() {
        if (!assetModel || !bucketData) return
        if (!assetModel.isBucketLoaded(bucketIndex)) {
            assetModel.requestBucketLoad(bucketIndex)
        } else {
            loadAssets()
        }
    }

    function loadAssets() {
        bucketSubGroups = assetModel.getBucketSubGroups(bucketIndex)
        buildRowLayout()
        assetsLoaded = true
        updateContentTop()
    }

    function buildRowLayout() {
        var rows = []
        var y = 0
        var headerHeight = Theme.itemSizeExtraSmall
        var apr = assetsPerRow
        var ch = cellSize
        var sg = bucketSubGroups
        if (sg) {
            for (var i = 0; i < sg.length; i++) {
                var group = sg[i]
                var assets = group.assets || []
                rows.push({ "t": 0, "y": y, "h": headerHeight, "displayDate": group.displayDate, "groupAssets": assets })
                y += headerHeight
                for (var r = 0; r < assets.length; r += apr) {
                    rows.push({ "t": 1, "y": y, "h": ch, "assets": assets.slice(r, Math.min(r + apr, assets.length)) })
                    y += ch
                }
            }
        }
        rowLayout = rows
        bucketContentHeight = y
    }

    function firstRowAtOrAfter(viewY) {
        var lo = 0
        var hi = rowLayout.length -1
        var res = rowLayout.length
        while (lo <= hi) {
            var mid = (lo + hi) >> 1
            var row = rowLayout[mid]
            if (row.y + row.h > viewY) {
                res = mid
                hi = mid - 1
            } else {
                lo = mid + 1
            }
        }
        return res
    }

    function lastRowAfterOrBefore(viewY) {
        var lo = 0
        var hi = rowLayout.length -1
        var res = -1
        while (lo <= hi) {
            var mid = (lo + hi) >> 1
            var row = rowLayout[mid]
            if (row.y < viewY) {
                res = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return res
    }

    function updateContentTop() {
        if (!viewportFlickable || !viewportFlickable.contentItem) return
        contentTop = contentArea.mapToItem(viewportFlickable.contentItem, 0, 0).y
    }

    // Listen for bucket load completion
    Connections {
        target: assetModel
        onBucketAssetsLoaded: {
            if (bucketIndex === bucketColumn.bucketIndex && !bucketColumn.assetsLoaded) {
                if (bucketColumn.autoLoadAssets) {
                    bucketColumn.loadAssets()
                }
            }
        }
        onBucketDataUpdated: {
            if (bucketIndex === bucketColumn.bucketIndex && bucketColumn.assetsLoaded) {
                bucketColumn.bucketSubGroups = assetModel.getBucketSubGroups(bucketColumn.bucketIndex)
                bucketColumn.buildRowLayout()
            }
        }
        onBucketLoadsIdle: {
            if (!bucketColumn.assetsLoaded && bucketColumn.autoLoadAssets) {
                bucketColumn.requestAssets()
            }
        }
    }

    Connections {
        target: viewportFlickable
        onContentHeightChanged: bucketColumn.updateContentTop()
    }

    // Helper for height estimation (used by both placeholders)
    function estimateContentHeight(count) {
        if (!count || count <= 0) return 0
        var apr = assetsPerRow
        // Conservative subgroup estimate: small buckets have more subgroups relative to count
        var estimatedSubgroups
        if (count <= 5) estimatedSubgroups = count
        else if (count <= 20) estimatedSubgroups = Math.ceil(count / 2)
        else estimatedSubgroups = Math.min(Math.ceil(count / 4), 31)
        // Each subgroup starts its own flow, so partial last rows are wasted
        var estimatedRows = estimatedSubgroups + Math.max(0, Math.ceil(Math.max(0, count - estimatedSubgroups) / apr))
        var subgroupHeaderHeight = estimatedSubgroups * Theme.itemSizeExtraSmall
        return estimatedRows * cellSize + subgroupHeaderHeight
    }

    // Bucket header
    Rectangle {
        width: parent.width
        height: Theme.itemSizeSmall
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

        Label {
            anchors.left: parent.left
            anchors.leftMargin: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            text: bucketData && bucketData.monthYear ? bucketData.monthYear : ""
            font.pixelSize: Theme.fontSizeLarge
            font.bold: true
            color: Theme.highlightColor
            visible: isFirstOfMonth
        }

        // Asset count indicator when not loaded
        Label {
            anchors.left: parent.left
            anchors.leftMargin: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            text: bucketData && typeof bucketData.count === "number" ? (bucketData.count === 1
                //% "1 item"
                ? qsTrId("timelineBucketDelegate.item")
                //% "%1 items"
                : qsTrId("timelineBucketDelegate.items").arg(bucketData.count)) : ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
            visible: !isFirstOfMonth && !assetsLoaded
        }
    }

    // Stable-height placeholder for unloaded bucket content
    Item {
        id: contentArea
        width: parent.width
        height: bucketColumn.assetsLoaded ? bucketColumn.bucketContentHeight : estimateContentHeight(bucketColumn.bucketAssetCount)

        onYChanged: bucketColumn.updateContentTop()

        LoadingIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            y: bucketColumn.visibleCenterY - height / 2
            loading: !bucketColumn.assetsLoaded && bucketColumn.bucketAssetCount > 0
            useMonochrome: true
        }

        Repeater {
            model: bucketColumn.assetsLoaded ? bucketColumn.poolRowCount : 0

            Item {
                width: contentArea.width
                property int rowIndex: {
                    var pool = bucketColumn.poolRowCount
                    if (pool <= 0) return -1
                    var first = bucketColumn.firstVisibleRow
                    var r = first - (first % pool) + index
                    if (r < first) r+= pool
                    return r
                }
                property var rowData: (rowIndex >= 0 && rowIndex < bucketColumn.rowLayout.length) ? bucketColumn.rowLayout[rowIndex] : null
                property bool inWindow: rowData !== null && rowIndex >= bucketColumn.firstVisibleRow && rowIndex <= bucketColumn.lastVisibleRow
                visible: inWindow
                y: rowData ? rowData.y : 0
                height: rowData ? rowData.h : 0

                // Sub-group date header
                Item {
                    anchors.fill: parent
                    visible: inWindow && rowData && rowData.t === 0

                    property var groupAssets: (inWindow && rowData && rowData.t === 0) ? rowData.groupAssets : null
                    property bool isSubGroupSelected: {
                        if (!groupAssets || assetModel.selectedCount === 0) return false
                        for (var i = 0; i < groupAssets.length; i++) {
                            if (!assetModel.isAssetSelected(groupAssets[i].id)) {
                                return false
                            }
                        }
                        return true
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: (rowData && rowData.t === 0) ? rowData.displayDate : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                    }

                    IconButton {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                        anchors.verticalCenter: parent.verticalCenter
                        icon.source: parent.isSubGroupSelected ? "image://theme/icon-m-remove" : "image://theme/icon-m-add"
                        icon.color: parent.isSubGroupSelected ? Theme.errorColor : Theme.primaryColor

                        onClicked: {
                            var assets = parent.groupAssets
                            if (!assets) return
                            var model = bucketColumn.assetModel
                            var bucketIdx = bucketColumn.bucketIndex
                            var select = !parent.isSubGroupSelected
                            var toToggle = []
                            for (var i = 0; i < assets.length; i++) {
                                if (model.isAssetSelected(assets[i].id) !== select) {
                                    toToggle.push(assets[i].assetIndex)
                                }
                            }
                            for (var j = 0; j < toToggle.length; j++) {
                                model.toggleSelection(bucketIdx, toToggle[j])
                            }
                        }
                    }
                }

                // Assets in this sub-group
                Row {
                    anchors.fill: parent
                    visible: inWindow && rowData && rowData.t === 1

                    Repeater {
                        model: (inWindow && rowData && rowData.t === 1) ? rowData.assets : null

                        AssetGridItem {
                            id: gridItem
                            width: bucketColumn.cellSize
                            height: bucketColumn.cellSize
                            assetId: modelData.id
                            isFavorite: modelData.isFavorite
                            isSelected: {
                                assetModel.selectedCount
                                return assetModel.isAssetSelected(modelData.id)
                            }
                            isVideo: modelData.isVideo
                            assetIndex: modelData.assetIndex
                            thumbhash: modelData.thumbhash || ""
                            duration: modelData.duration || ""
                            stackId: modelData.stackId || ""
                            stackAssetCount: modelData.stackAssetCount || 0

                            isHighlighted: bucketColumn.highlightAssetId === modelData.id

                            onClicked: {
                                if (assetModel.selectedCount > 0) {
                                    assetModel.toggleSelection(bucketColumn.bucketIndex, modelData.assetIndex)
                                } else {
                                    bucketColumn.assetClicked(modelData.id, gridItem.isFavorite, modelData.isVideo, modelData.thumbhash || "", modelData.globalIndex, modelData.stackId || "", modelData.stackAssetCount || 0)
                                }
                            }

                            onPressAndHold: {
                                assetModel.toggleSelection(bucketColumn.bucketIndex, modelData.assetIndex)
                            }

                            onAddToSelection: {
                                assetModel.toggleSelection(bucketColumn.bucketIndex, modelData.assetIndex)
                            }
                        }
                    }
                }
            }
        }
    }
}
