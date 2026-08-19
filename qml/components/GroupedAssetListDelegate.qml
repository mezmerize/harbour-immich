import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: delegate

    property var rowData: ({})
    property real cellSize: 0
    property int assetsPerRow: 4
    property bool selectionMode: false
    property var selectedAssets: []

    signal assetClicked(string assetId, bool isFavorite, bool isVideo, string thumbhash, int assetIndex)
    signal assetPressAndHold(string assetId)
    signal subGroupSelectToggled(var assets, bool allSelected)

    function isAssetSelected(assetId) {
        return selectedAssets.indexOf(assetId) > -1
    }

    width: parent ? parent.width : 0
    height: content.height

    Column {
        id: content
        width: parent.width
        spacing: 0

        // Month header
        Rectangle {
            width: parent.width
            visible: delegate.rowData.type === "month"
            height: visible ? Theme.itemSizeSmall : 0
            color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

            Label {
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: delegate.rowData.type === "month" ? delegate.rowData.monthYear : ""
                font.pixelSize: Theme.fontSizeLarge
                font.bold: true
                color: Theme.highlightColor
            }
        }

        // Date sub-group header
        Rectangle {
            width: parent.width
            visible: delegate.rowData.type === "date"
            height: visible ? Theme.itemSizeExtraSmall : 0
            color: "transparent"

            property var groupAssets: (delegate.rowData.type === "date" && delegate.rowData.groupAssets) ? delegate.rowData.groupAssets : []
            property bool isSubGroupSelected: {
                if (groupAssets.length === 0 || delegate.selectedAssets.length === 0) return false
                for (var i = 0; i < groupAssets.length; i++) {
                    if (!delegate.isAssetSelected(groupAssets[i].id)) return false
                }
                return true
            }

            Label {
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: delegate.rowData.type === "date" ? delegate.rowData.displayDate : ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
            }

            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                anchors.verticalCenter: parent.verticalCenter
                icon.source: parent.isSubGroupSelected ? "image://theme/icon-m-remove" : "image://theme/icon-m-add"
                icon.color: parent.isSubGroupSelected ? Theme.errorColor : Theme.primaryColor
                onClicked: delegate.subGroupSelectToggled(parent.groupAssets, parent.isSubGroupSelected)
            }
        }

        // Asset row
        Row {
            width: parent.width
            visible: delegate.rowData.type === "assets"
            height: visible ? delegate.cellSize : 0

            Repeater {
                model: delegate.rowData.type === "assets" ? delegate.rowData.rowAssets : []

                AssetGridItem {
                    width: delegate.cellSize
                    height: delegate.cellSize
                    assetId: modelData.id
                    isFavorite: modelData.isFavorite
                    isSelected: delegate.isAssetSelected(modelData.id)
                    isVideo: modelData.isVideo
                    thumbhash: modelData.thumbhash || ""
                    duration: modelData.duration || ""

                    onClicked: {
                        if (delegate.selectionMode) {
                            delegate.assetPressAndHold(modelData.id)
                        } else {
                            delegate.assetClicked(modelData.id, modelData.isFavorite, modelData.isVideo, modelData.thumbhash || "", modelData.assetIndex)
                        }
                    }
                    onPressAndHold: delegate.assetPressAndHold(modelData.id)
                    onAddToSelection: delegate.assetPressAndHold(modelData.id)
                }
            }
        }
    }
}
