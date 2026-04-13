import QtQuick 2.0
import Sailfish.Silica 1.0

Column {
    id: root

    property var groupedAssets: []
    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow

    property bool selectionMode: false
    property var selectedAssets: []

    signal assetClicked(string assetId, bool isFavorite, bool isVideo, string thumbhash)
    signal assetPressAndHold(string assetId)
    signal subGroupSelectToggled(var assets, bool allSelected)

    function isAssetSelected(assetId) {
        return selectedAssets.indexOf(assetId) > -1
    }

    Repeater {
        model: root.groupedAssets

        Column {
            width: root.width
            spacing: 0

            property var monthData: modelData

            Rectangle {
                width: parent.width
                height: Theme.itemSizeSmall
                color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: monthData.monthYear
                    font.pixelSize: Theme.fontSizeLarge
                    font.bold: true
                    color: Theme.highlightColor
                }
            }

            Repeater {
                model: monthData.groups

                Column {
                    width: root.width
                    spacing: 0

                    property var subGroupData: modelData

                    Rectangle {
                        width: parent.width
                        height: Theme.itemSizeExtraSmall
                        color: "transparent"

                        property bool isSubGroupSelected: {
                            if (!subGroupData || !subGroupData.assets || root.selectedAssets.length === 0) return false
                            for (var i = 0; i < subGroupData.assets.length; i++) {
                                if (!root.isAssetSelected(subGroupData.assets[i].id)) return false
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
                                root.subGroupSelectToggled(subGroupData.assets, parent.isSubGroupSelected)
                            }
                        }
                    }

                    Flow {
                        width: parent.width

                        Repeater {
                            model: subGroupData ? subGroupData.assets : null

                            AssetGridItem {
                                width: root.cellSize
                                height: root.cellSize
                                assetId: modelData.id
                                isFavorite: modelData.isFavorite
                                isSelected: root.selectedAssets.length >= 0 && root.isAssetSelected(modelData.id)
                                isVideo: modelData.isVideo
                                thumbhash: modelData.thumbhash || ""
                                duration: modelData.duration || ""

                                onClicked: {
                                    if (root.selectionMode) {
                                        root.assetPressAndHold(modelData.id)
                                    } else {
                                        root.assetClicked(modelData.id, modelData.isFavorite, modelData.isVideo, modelData.thumbhash || "")
                                    }
                                }
                                onPressAndHold: root.assetPressAndHold(modelData.id)
                                onAddToSelection: root.assetPressAndHold(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
