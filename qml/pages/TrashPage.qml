import QtQuick 2.0
import Sailfish.Silica 1.0
import harbour.immich.models 1.0
import "../components"

Page {
    id: page

    property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
    property real cellSize: width / assetsPerRow
    property string activeFilter: "all"
    property string sortOrder: "desc"
    property string contextId: "trash"
    property var queryParams: ({"isTrashed": "true", "order": sortOrder})

    TimelineModel {
        id: trashModel
    }

    function refresh() {
        var params = {"isTrashed": "true", "order": sortOrder}
        if (activeFilter === "favorites") params["isFavorite"] = "true"
        queryParams = params
        trashModel.clear()
        trashModel.setLoading(true)
        immichApi.fetchTimelineBuckets(contextId, queryParams)
    }

    SilicaListView {
        id: bucketsList
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: selectionActionBar.visible ? selectionActionBar.top : parent.bottom
        clip: true
        cacheBuffer: Math.max(height * 2, 2000)
        model: trashModel

        PullDownMenu {
            enabled: trashModel.selectedCount === 0

            MenuItem {
                //% "Refresh"
                text: qsTrId("trashPage.refresh")
                onClicked: page.refresh()
            }

            MenuItem {
                //% "Restore all"
                text: qsTrId("trashPage.restoreAll")
                visible: trashModel.totalCount > 0
                onClicked: {
                    remorse.execute(
                        //% "Restoring all items from trash"
                        qsTrId("trashPage.restoringAll"), function() {
                        immichApi.restoreAllTrash()
                    })
                }
            }

            MenuItem {
                //% "Empty trash"
                text: qsTrId("trashPage.emptyTrash")
                visible: trashModel.totalCount > 0
                onClicked: {
                    remorse.execute(
                        //% "Permanently deleting all trashed items"
                        qsTrId("trashPage.emptyingTrash"), function() {
                        immichApi.emptyTrash()
                    })
                }
            }
        }

        header: Column {
            width: bucketsList.width

            PageHeader {
                //% "Trash"
                title: qsTrId("trashPage.trash")
            }

            // Info banner
            Rectangle {
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                height: infoBannerColumn.height + 2 * Theme.paddingMedium
                radius: Theme.paddingMedium
                color: Theme.rgba(Theme.highlightBackgroundColor, 0.15)
                visible: trashModel.totalCount > 0

                Column {
                    id: infoBannerColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Theme.paddingMedium
                    spacing: Theme.paddingSmall

                    Row {
                        spacing: Theme.paddingMedium
                        anchors.horizontalCenter: parent.horizontalCenter

                        Icon {
                            source: "image://theme/icon-s-high-importance"
                            color: Theme.highlightColor
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.iconSizeSmall
                            height: Theme.iconSizeSmall
                        }

                        Label {
                            //% "Trashed items will be permanently deleted after 30 days"
                            text: qsTrId("trashPage.autoDeleteInfo")
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.highlightColor
                            wrapMode: Text.WordWrap
                            width: bucketsList.width - 2 * Theme.horizontalPageMargin - 2 * Theme.paddingMedium - Theme.iconSizeSmall - Theme.paddingMedium
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
                visible: trashModel.totalCount > 0
            }

            TimelineFilterBar {
                activeFilter: page.activeFilter
                sortOrder: page.sortOrder
                onFilterActivated: {
                    page.activeFilter = filter
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

        delegate: TimelineBucketDelegate {
            width: bucketsList.width
            bucketIndex: index
            bucketKey: trashModel.getBucketTimeBucket(index)
            cellSize: page.cellSize
            assetsPerRow: page.assetsPerRow
            assetModel: trashModel

            onAssetClicked: {
                pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                    assetId: assetId,
                    isFavorite: false,
                    isVideo: isVideo,
                    thumbhash: thumbhash
                })
            }
        }

        footer: Item {
            width: parent.width
            height: Theme.paddingLarge
        }

        VerticalScrollDecorator {}
    }

    // Loading
    LoadingIndicator {
        anchors.fill: bucketsList
        loading: trashModel.loading && trashModel.bucketCount === 0
    }

    // Empty state
    EmptyState {
        anchors.fill: bucketsList
        visible: !trashModel.loading && trashModel.totalCount === 0
        iconSource: "image://theme/icon-m-delete"
        //% "Trash is empty"
        message: qsTrId("trashPage.noAssets")
    }

    SelectionActionBar {
        id: selectionActionBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: trashModel.selectedCount > 0
        selectedCount: trashModel.selectedCount
        isTrashPage: true

        onRestoreFromTrash: {
            immichApi.restoreFromTrash(trashModel.getSelectedAssetIds())
        }
        onDeleteSelected: {
            var selectedIds = trashModel.getSelectedAssetIds()
            remorse.execute(selectedIds.length > 1
                //% "Deleting %1 assets"
                ? qsTrId("trashPage.deletingAssets").arg(selectedIds.length)
                //% "Deleting asset"
                : qsTrId("trashPage.deletingAsset"), function() {
                immichApi.deleteAssets(selectedIds)
                trashModel.clearSelection()
            })
        }
        onClearSelection: trashModel.clearSelection()
    }

    RemorsePopup {
        id: remorse
    }

    ScrollToTopButton {
        targetFlickable: bucketsList
        actionBarHeight: selectionActionBar.visible ? selectionActionBar.contentHeight : 0
    }

    NotificationBanner {
        id: notification
        anchors.bottom: trashModel.selectedCount > 0 ? selectionActionBar.top : parent.bottom
    }

    Component.onCompleted: {
        trashModel.setServerUrl(authManager.serverUrl)
        page.refresh()
    }

    Connections {
        target: immichApi
        onTimelineBucketsReceived: {
            if (context !== page.contextId) return
            trashModel.loadBuckets(buckets)
            trashModel.setLoading(false)
        }
        onTimelineBucketReceived: {
            if (context !== page.contextId) return
            trashModel.loadBucketAssets(timeBucket, bucketData)
        }
        onTrashRestored: {
            //% "Restored from trash"
            notification.show(qsTrId("trashPage.restored"))
            trashModel.clearSelection()
            page.refresh()
        }
        onTrashEmptied: {
            //% "Trash emptied"
            notification.show(qsTrId("trashPage.emptied"))
            page.refresh()
        }
        onAllTrashRestored: {
            //% "All items restored"
            notification.show(qsTrId("trashPage.allRestored"))
            page.refresh()
        }
        onAssetsDeleted: {
            page.refresh()
        }
    }

    Connections {
        target: trashModel
        onBucketLoadRequested: {
            immichApi.fetchTimelineBucket(page.contextId, timeBucket, page.queryParams)
        }
    }
}
