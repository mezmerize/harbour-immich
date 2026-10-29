import QtQuick 2.6
import Sailfish.Silica 1.0
import QtFeedback 5.0
import "../components"

Page {
    backgroundColor: __silica_applicationwindow_instance.lightSurface(Theme.rgba(palette.overlayBackgroundColor, 0))
    id: page

    // DeviceFolderModel instance and the index to start on
    property var model: null
    property int initialIndex: 0
    property int currentIndex: -1
    property int totalAssets: model ? model.count : 0

    property string currentPath: ""
    property string currentName: ""
    property bool currentIsVideo: false
    property bool currentBackedUp: false

    // Zoom + pan state
    property real imageScale: 1.0
    property real panX: 0
    property real panY: 0
    property bool zoomed: imageScale > 1.05

    // Horizontal slide state (for prev/next peek)
    property real slideOffset: 0

    // Vertical drag-to-dismiss state
    property real dragOffsetY: 0
    property bool draggingVertical: false
    property real dismissThreshold: page.height * 0.2
    property real dragOpacity: draggingVertical ? Math.max(0.2, 1.0 - Math.abs(dragOffsetY) / (page.height * 0.5)) : 1.0
    property bool controlsShown: true

    allowedOrientations: Orientation.All
    backNavigation: false
    backgroundColor: "transparent"

    ThemeEffect {
        id: hapticFeedback
        effect: ThemeEffect.Press
    }

    function getAssetSource(index) {
        if (!model || index < 0 || index >= totalAssets) return ""
        var item = model.get(index)
        if (!item || item.filePath === undefined) return ""
        return item.isVideo ? "image://localthumbnail/fit/" + item.filePath : "file://" + item.filePath
    }

    function updateCurrent() {
        if (!model || currentIndex < 0 || currentIndex >= totalAssets) return
        var item = model.get(currentIndex)
        if (!item || item.filePath === undefined) return
        currentPath = item.filePath
        currentName = item.fileName
        currentIsVideo = item.isVideo
        currentBackedUp = item.backupStatus === 1
    }

    function navigateToAsset(index) {
        if (!model || index < 0 || index >= totalAssets) return

        imageScale = 1.0
        panX = 0
        panY = 0

        currentIndex = index
        updateCurrent()
        videoPlayer.active = currentIsVideo && page.status === PageStatus.Active
    }

    function activateIfReady() {
        if (page.status !== PageStatus.Active) return
        if (currentIndex < 0) {
            currentIndex = Math.max(0, Math.min(initialIndex, totalAssets - 1))
            updateCurrent()
        }
        if (currentIsVideo && !videoPlayer.active) {
            videoPlayer.active = true
        }
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            activateIfReady()
        } else if (status === PageStatus.Deactivating && currentIsVideo) {
            videoPlayer.pause()
        }
    }

    Component.onCompleted: activateIfReady()

    // Semi-transparent backdrop that fades during drag
    DismissDragBackdrop {
        anchors.fill: parent
        dragOpacity: page.dragOpacity
        dragOffsetY: page.dragOffsetY
        draggingVertical: page.draggingVertical
        dismissThreshold: page.dismissThreshold
        //% "Release to close"
        releaseText: qsTrId("assetDetailPage.releaseToClose")
        //% "Drag to close"
        dragText: qsTrId("assetDetailPage.dragToClose")
        z: -1
    }

    AssetInfoPeek {
        dragOffsetY: page.dragOffsetY
        openThreshold: page.dismissThreshold
        assetInfo: page.currentPath ? assetDatabase.localAssetInfo(page.currentPath) : null
    }

    // Main content container - moves vertically during drag-to-dismiss
    Item {
        id: contentContainer
        anchors.fill: parent
        opacity: dragOpacity
        transform: Translate { y: dragOffsetY }

        // Image viewport with prev/current/next for horizontal peek
        Item {
            id: imageViewport
            anchors.fill: parent
            clip: true

            // Previous asset (left of current)
            Image {
                id: prevImage
                x: -imageViewport.width + slideOffset
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                source: getAssetSource(currentIndex - 1)
                asynchronous: true
                cache: true
                autoTransform: true
            }

            // Current asset image
            Image {
                id: assetImage
                x: zoomed ? 0 : slideOffset
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                source: currentIsVideo ? "" : (currentPath ? "file://" + currentPath : "")
                autoTransform: true
                sourceSize.width: page.width
                sourceSize.height: page.height
                asynchronous: true
                smooth: true
                scale: imageScale
                transformOrigin: Item.Center

                onStatusChanged: {
                    if (status === Image.Ready && transitionCover.visible) {
                        transitionCover.visible = false
                        transitionCover.source = ""
                    }
                }

                transform: Translate {
                    x: panX
                    y: panY
                }

                LoadingIndicator {
                    anchors.centerIn: parent
                    visible: assetImage.status === Image.Loading
                }

                Label {
                    anchors.centerIn: parent
                    visible: !page.currentIsVideo && assetImage.status === Image.Error
                    //% "Failed to load image"
                    text: qsTrId("deviceAssetDetailPage.failed")
                    color: Theme.lightSecondaryColor
                }
            }

            // Next asset (right of current)
            Image {
                id: nextImage
                x: imageViewport.width + slideOffset
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                source: getAssetSource(currentIndex + 1)
                asynchronous: true
                cache: true
                autoTransform: true
            }

            // Transition cover to prevent flash during asset switch
            Image {
                id: transitionCover
                width: imageViewport.width
                height: imageViewport.height
                fillMode: Image.PreserveAspectFit
                visible: false
                asynchronous: false
                cache: true
                autoTransform: true
                z: 2
            }
        }

        VideoPlayer {
            id: videoPlayer
            x: zoomed ? 0 : slideOffset
            width: page.width
            height: page.height
            z: 2
            visible: page.currentIsVideo
            filePath: page.currentIsVideo ? page.currentPath : ""
            posterSource: page.currentIsVideo && page.currentPath ? "image://localthumbnail/fit/" + page.currentPath : ""
            controlsBottomMargin: actionBar.height
            onLoaded: {
                if (transitionCover.visible) {
                    transitionCover.visible = false
                    transitionCover.source = ""
                }
            }
            onControlsVisibleChanged: {
                if (page.currentIsVideo) page.controlsShown = controlsVisible
            }
        }

        ZoomSwipeArea {
            anchors.fill: parent
            z: 1
            stateTarget: page
            imageTarget: assetImage
            viewportWidth: page.width
            viewportHeight: page.height
            currentIndex: page.currentIndex
            totalCount: page.totalAssets
            enableZoom: !page.currentIsVideo
            onTapped: {
                if (page.currentIsVideo) {
                    videoPlayer.toggleControls()
                } else {
                    page.controlsShown = !page.controlsShown
                }
            }
            onPrevRequested: {
                transitionCover.source = prevImage.source
                transitionCover.visible = true
                page.navigateToAsset(page.currentIndex - 1)
            }
            onNextRequested: {
                transitionCover.source = nextImage.source
                transitionCover.visible = true
                page.navigateToAsset(page.currentIndex + 1)
            }
            onDismissRequested: pageStack.pop()
            onInfoRequested: {
                pageStack.push(Qt.resolvedUrl("DeviceAssetInfoPage.qml"), {
                    filePath: page.currentPath,
                    backedUp: page.currentBackedUp
                })
            }
        }

        // Back button (top-right)
        IconButton {
            anchors {
                top: parent.top
                right: parent.right
                topMargin: Theme.paddingLarge
                rightMargin: Theme.horizontalPageMargin
            }
            icon.source: "image://theme/icon-m-reset"
            icon.color: Theme.lightPrimaryColor
            visible: opacity > 0
            opacity: (controlsShown && !zoomed && !draggingVertical) ? 1.0 : 0.0
            Behavior on opacity { FadeAnimation { duration: 200 } }
            onClicked: pageStack.pop()
            z: 10
        }

        // Backed-up indicator
        Label {
            anchors {
                bottom: actionBar.top
                horizontalCenter: parent.horizontalCenter
                bottomMargin: Theme.paddingMedium
            }
            visible: page.currentBackedUp
            //% "Backed up"
            text: qsTrId("deviceAssetDetailPage.backedUp")
            color: Theme.lightPrimaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            z: 10
            opacity: (controlsShown && !draggingVertical) ? 1.0 : 0.0
            Behavior on opacity { FadeAnimation { duration: 200 } }
        }

        // Bottom action bar
        Rectangle {
            id: actionBar
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
            }
            height: actionRow.height + Theme.paddingMedium * 2
            color: Theme.rgba("black", 0.6)
            visible: opacity > 0
            opacity: (controlsShown && !zoomed && !draggingVertical) ? 1.0 : 0.0
            Behavior on opacity { FadeAnimation { duration: 200 } }
            z: 10

            // Gradient top edge
            Rectangle {
                anchors.bottom: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Theme.paddingLarge * 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Theme.rgba("black", 0.6) }
                }
            }

            Row {
                id: actionRow
                anchors.centerIn: parent
                width: parent.width

                IconButton {
                    width: parent.width / 3
                    icon.source: "image://theme/icon-m-cloud-upload"
                    icon.color: Theme.lightPrimaryColor
                    enabled: !page.currentBackedUp
                    opacity: enabled ? 1.0 : 0.4
                    onClicked: {
                        hapticFeedback.play()
                        immichApi.uploadAssets([page.currentPath])
                        //% "Uploading file"
                        notification.show(qsTrId("notification.uploadingFile"))
                    }
                }

                IconButton {
                    width: parent.width / 3
                    icon.source: "image://theme/icon-m-delete"
                    icon.color: Theme.lightPrimaryColor
                    onClicked: {
                        hapticFeedback.play()
                        var path = page.currentPath
                        //% "Deleting file from device"
                        deleteRemorse.execute(qsTrId("notification.deletingFile"), function() {
                            if (page.model) page.model.removeLocalFiles([path])
                            pageStack.pop()
                        })
                    }
                }

                IconButton {
                    width: parent.width / 3
                    icon.source: "image://theme/icon-m-about"
                    icon.color: Theme.lightPrimaryColor
                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("DeviceAssetInfoPage.qml"), {
                            filePath: page.currentPath,
                            backedUp: page.currentBackedUp
                        })
                    }
                }
            }
        }

        NotificationBanner {
            id: notification
            anchors.bottom: actionBar.top
            z: 11
        }
    }

    RemorsePopup {
        id: deleteRemorse
    }

    Connections {
        target: page.model
        onEntryChanged: {
            if (index === page.currentIndex) page.updateCurrent()
        }
    }

    Connections {
        target: immichApi
        onAssetUploaded: {
            if (filePath === page.currentPath) {
                page.currentBackedUp = true
                //% "Uploaded"
                notification.show(qsTrId("notification.uploadedFile"))
            }
        }
        onUploadFailed: {
            if (filePath === page.currentPath) {
                //% "Upload failed"
                notification.showError(qsTrId("notification.uploadFileFailed"))
            }
        }
    }
}
