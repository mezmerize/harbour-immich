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

    // Public state (read by parent for scroll-to-asset)
    property var bucketData: null
    property var bucketSubGroups: null
    property int bucketAssetCount: bucketData && typeof bucketData.count === "number" ? bucketData.count : 0
    property bool isFirstOfMonth: false
    property bool dataLoaded: false
    property bool assetsLoaded: false
    property bool initialized: false

    visible: !assetsLoaded || (bucketSubGroups && bucketSubGroups.length > 0)

    // Signals for parent to handle navigation
    signal assetClicked(string assetId, bool isFavorite, bool isVideo, string thumbhash, int currentIndex, string stackId, int stackAssetCount)

    Component.onCompleted: {
        initialized = true
        resetState()
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

    function resetState() {
        bucketData = null
        bucketSubGroups = null
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
        assetsLoaded = true
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
                bucketSubGroups = assetModel.getBucketSubGroups(bucketColumn.bucketIndex)
            }
        }
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
        width: parent.width
        height: !bucketColumn.assetsLoaded ? estimateContentHeight(bucketColumn.bucketAssetCount) : 0
        visible: !bucketColumn.assetsLoaded

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Small
            running: parent.visible
        }
    }

    // Sub-groups by date
    Column {
        width: parent.width
        visible: assetsLoaded
        spacing: 0

        Repeater {
            model: bucketColumn.assetsLoaded ? bucketSubGroups : null

            Column {
                width: parent.width
                spacing: 0

                property var subGroupData: modelData

                // Sub-group date header
                Rectangle {
                    width: parent.width
                    height: Theme.itemSizeExtraSmall
                    color: "transparent"

                    property bool isSubGroupSelected: {
                        if (!subGroupData || !subGroupData.assets || assetModel.selectedCount === 0) return false
                        for (var i = 0; i < subGroupData.assets.length; i++) {
                            if (!assetModel.isAssetSelected(subGroupData.assets[i].id)) {
                                return false
                            }
                        }
                        return true
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: subGroupData ? subGroupData.displayDate : ""
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
                            if (!subGroupData || !subGroupData.assets) return
                            var assets = subGroupData.assets
                            if (parent.isSubGroupSelected) {
                                // Deselect all assets in this subgroup
                                for (var i = 0; i < assets.length; i++) {
                                    if (assetModel.isAssetSelected(assets[i].id)) {
                                        assetModel.toggleSelection(bucketColumn.bucketIndex, assets[i].assetIndex)
                                    }
                                }
                            } else {
                                // Select all assets in this subgroup
                                for (var i = 0; i < assets.length; i++) {
                                    if (!assetModel.isAssetSelected(assets[i].id)) {
                                        assetModel.toggleSelection(bucketColumn.bucketIndex, assets[i].assetIndex)
                                    }
                                }
                            }
                        }
                    }
                }

                // Assets in this sub-group
                Flow {
                    width: parent.width

                    Repeater {
                        model: subGroupData ? subGroupData.assets : null

                        AssetGridItem {
                            width: bucketColumn.cellSize
                            height: bucketColumn.cellSize
                            id: gridItem
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
                                    var idx = modelData.globalIndex
                                    bucketColumn.assetClicked(modelData.id, gridItem.isFavorite, modelData.isVideo, modelData.thumbhash || "", idx, modelData.stackId || "", modelData.stackAssetCount || 0)
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
