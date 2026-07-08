import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page

    property string memoryTitle: ""
    property var assets: []
    property int currentIndex: 0
    property bool slideshowRunning: false

    property bool showingA: true
    property bool crossfading: false

    // Horizontal slide state (for prev/next peek)
    property real slideOffset: 0

    // Vertical drag-to-dismiss state
    property real dragOffsetY: 0
    property bool draggingVertical: false
    property real dismissThreshold: page.height * 0.2
    property real dragOpacity: draggingVertical ? Math.max(0.2, 1.0 - Math.abs(dragOffsetY) / (page.height * 0.5)) : 1.0

    function getMemoryAssetSource(index) {
        if (!assets || assets.length === 0) return ""
        var wrapped = ((index % assets.length) + assets.length) % assets.length
        return assets[wrapped] && assets[wrapped].id ? "image://immich/detail/" + assets[wrapped].id : ""
    }

    function crossfadeTo(newIndex) {
        if (!assets || assets.length === 0) return
        var newSource = "image://immich/detail/" + assets[newIndex].id
        if (showingA) {
            slideshowImageB.source = newSource
            crossfadeToB.start()
        } else {
            slideshowImageA.source = newSource
            crossfadeToA.start()
        }
        showingA = !showingA
        currentIndex = newIndex
    }

    function switchTo(newIndex) {
        if (!assets || assets.length === 0) return
        crossfadeToA.stop()
        crossfadeToB.stop()
        var newSource = "image://immich/detail/" + assets[newIndex].id
        slideshowImageA.source = newSource
        slideshowImageA.opacity = 1
        slideshowImageB.opacity = 0
        slideshowImageB.source = ""
        showingA = true
        currentIndex = newIndex
    }

    Timer {
        id: slideshowTimer
        interval: 3000
        repeat: true
        running: slideshowRunning && page.status === PageStatus.Active
        onTriggered: {
            if (assets && assets.length > 1) {
                crossfadeTo((currentIndex + 1) % assets.length)
            }
        }
    }

    allowedOrientations: Orientation.All
    backNavigation: false
    backgroundColor: "transparent"

    // Semi-transparent backdrop that fades during drag
    DismissDragBackdrop {
        anchors.fill: parent
        dragOpacity: page.dragOpacity
        dragOffsetY: page.dragOffsetY
        draggingVertical: page.draggingVertical
        dismissThreshold: page.dismissThreshold
        //% "Release to close"
        releaseText: qsTrId("memoryDetailPage.releaseToClose")
        //% "Drag to close"
        dragText: qsTrId("memoryDetailPage.dragToClose")
        z: -1
    }

    // Main content container - moves vertically during drag-to-dismiss
    Item {
        id: contentContainer
        anchors.fill: parent
        opacity: dragOpacity
        transform: Translate { y: dragOffsetY }

        // Main slideshow view with prev/current/next for horizontal peek
        Item {
            id: slideshowContainer
            width: page.width
            height: page.height
            clip: true

            // Previous asset (left of current)
            Image {
                id: prevImage
                x: -page.width + slideOffset
                width: page.width
                height: page.height
                fillMode: Image.PreserveAspectFit
                source: getMemoryAssetSource(currentIndex - 1)
                asynchronous: true
                cache: true
            }

            // Thumbhash placeholder
            Image {
                id: mainThumbhash
                x: slideOffset
                width: page.width
                height: page.height
                fillMode: Image.PreserveAspectFit
                source: (assets && assets.length > 0 && assets[currentIndex] && assets[currentIndex].thumbhash) ? "image://thumbhash/" + assets[currentIndex].thumbhash : ""
                visible: !crossfading && (showingA ? slideshowImageA.status : slideshowImageB.status) !== Image.Ready
                asynchronous: false
                smooth: true
                cache: true
            }

            // Current image container
            Item {
                id: currentImageContainer
                x: slideOffset
                width: page.width
                height: page.height

                // Slideshow image A
                Image {
                    id: slideshowImageA
                    width: page.width
                    height: page.height
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    opacity: 1
                    onStatusChanged: {
                        if (status === Image.Ready && memoryTransitionCover.visible) {
                            memoryTransitionCover.visible = false
                            memoryTransitionCover.source = ""
                        }
                    }
                    source: (assets && assets.length > 0 && assets[0]) ? "image://immich/detail/" + assets[0].id : ""
                }

                // Slideshow image B (for crossfade)
                Image {
                    id: slideshowImageB
                    width: page.width
                    height: page.height
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    opacity: 0
                    source: ""
                }
            }

            // Next asset (right of current)
            Image {
                id: nextImage
                x: page.width + slideOffset
                width: page.width
                height: page.height
                fillMode: Image.PreserveAspectFit
                source: getMemoryAssetSource(currentIndex + 1)
                asynchronous: true
                cache: true
            }

            // Transition cover to prevent flash during asset switch
            Image {
                id: memoryTransitionCover
                width: page.width
                height: page.height
                fillMode: Image.PreserveAspectFit
                visible: false
                asynchronous: false
                cache: true
                z: 2
            }

            // Crossfade A -> B
            ParallelAnimation {
                id: crossfadeToB
                onStarted: crossfading = true
                onStopped: crossfading = false
                NumberAnimation { target: slideshowImageA; property: "opacity"; to: 0; duration: 1000; easing.type: Easing.InOutQuad }
                NumberAnimation { target: slideshowImageB; property: "opacity"; to: 1; duration: 1000; easing.type: Easing.InOutQuad }
            }

            // Crossfade B -> A
            ParallelAnimation {
                id: crossfadeToA
                onStarted: crossfading = true
                onStopped: crossfading = false
                NumberAnimation { target: slideshowImageA; property: "opacity"; to: 1; duration: 1000; easing.type: Easing.InOutQuad }
                NumberAnimation { target: slideshowImageB; property: "opacity"; to: 0; duration: 1000; easing.type: Easing.InOutQuad }
            }

            LoadingIndicator {
                anchors.centerIn: parent
                loading: slideshowImageA.status === Image.Loading && slideshowImageB.status === Image.Loading
                indicatorSize: Theme.iconSizeMedium
            }

            ZoomSwipeArea {
                anchors.fill: parent
                stateTarget: page
                imageTarget: showingA ? slideshowImageA : slideshowImageB
                viewportWidth: page.width
                viewportHeight: page.height
                currentIndex: page.currentIndex
                totalCount: page.assets ? page.assets.length : 0
                enableZoom: false
                wrapAround: true
                onPrevRequested: {
                    memoryTransitionCover.source = prevImage.source
                    memoryTransitionCover.visible = true
                    slideshowRunning = false
                    page.switchTo(((page.currentIndex - 1) % page.assets.length + page.assets.length) % page.assets.length)
                }
                onNextRequested: {
                    memoryTransitionCover.source = nextImage.source
                    memoryTransitionCover.visible = true
                    slideshowRunning = false
                    page.switchTo((page.currentIndex + 1) % page.assets.length)
                }
                onDismissRequested: pageStack.pop()
            }
        }

        // Title overlay (top)
        Item {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: titleLabel.height + Theme.paddingLarge * 2
            z: 10

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.rgba("black", 0.6) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Label {
                id: titleLabel
                anchors {
                    left: parent.left
                    right: backButton.left
                    top: parent.top
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.paddingMedium
                    topMargin: Theme.paddingLarge
                }
                text: memoryTitle
                color: Theme.lightPrimaryColor
                font.pixelSize: Theme.fontSizeLarge
                truncationMode: TruncationMode.Fade
            }

            // Back button (top-right)
            IconButton {
                id: backButton
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: Theme.paddingLarge
                    rightMargin: Theme.horizontalPageMargin
                }
                icon.source: "image://theme/icon-m-reset"
                icon.color: Theme.lightPrimaryColor
                visible: !draggingVertical
                opacity: visible ? 1.0 : 0.0
                Behavior on opacity { FadeAnimation { duration: 150 } }
                onClicked: pageStack.pop()
            }
        }

        // Bottom panel: counter, thumbnails, action bar
        Item {
            id: bottomPanel
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
            }
            height: bottomColumn.height
            visible: !draggingVertical
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { FadeAnimation { duration: 150 } }
            z: 10

            Rectangle {
                anchors.fill: parent
                color: Theme.rgba("black", 0.6)
            }

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

            Column {
                id: bottomColumn
                width: parent.width
                spacing: Theme.paddingSmall

                // Asset counter
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    topPadding: Theme.paddingMedium
                    //% "%1 / %2"
                    text: assets && assets.length > 0 ? qsTrId("memoryDetailPage.assetCounter").arg(currentIndex + 1).arg(assets.length) : ""
                    color: Theme.lightSecondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                }

                // Thumbnail strip
                SilicaListView {
                    id: thumbnailStrip
                    width: parent.width
                    height: Theme.itemSizeMedium
                    orientation: ListView.Horizontal
                    clip: true
                    spacing: Theme.paddingSmall
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin

                    model: assets ? assets.length : 0

                    delegate: BackgroundItem {
                        width: Theme.itemSizeMedium
                        height: Theme.itemSizeMedium
                        highlighted: index === currentIndex

                        Image {
                            id: stripThumbhash
                            anchors.fill: parent
                            anchors.margins: 2
                            fillMode: Image.PreserveAspectCrop
                            source: (assets && assets[index] && assets[index].thumbhash) ? "image://thumbhash/" + assets[index].thumbhash : ""
                            visible: stripThumbnail.status !== Image.Ready
                            asynchronous: false
                            smooth: true
                            cache: true
                        }

                        Image {
                            id: stripThumbnail
                            anchors.fill: parent
                            anchors.margins: 2
                            source: (assets && assets[index]) ? "image://immich/thumbnail/" + assets[index].id : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 128
                            sourceSize.height: 128

                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.width: index === currentIndex ? 3 : 0
                                border.color: Theme.highlightColor
                            }
                        }

                        onClicked: {
                            slideshowRunning = false
                            switchTo(index)
                        }
                    }

                    HorizontalScrollDecorator {}
                }

                // Action bar
                Row {
                    id: actionRow
                    width: parent.width

                    property int buttonCount: assets && assets.length > 1 ? 3 : 2

                    IconButton {
                        width: parent.width / actionRow.buttonCount
                        icon.source: slideshowRunning ? "image://theme/icon-m-pause" : "image://theme/icon-m-play"
                        icon.color: Theme.lightPrimaryColor
                        visible: assets && assets.length > 1
                        onClicked: slideshowRunning = !slideshowRunning
                    }

                    IconButton {
                        width: parent.width / actionRow.buttonCount
                        icon.source: "image://theme/icon-m-search"
                        icon.color: Theme.lightPrimaryColor
                        enabled: assets && assets.length > 0 && assets[currentIndex]
                        onClicked: {
                            var asset = assets[currentIndex]
                            if (asset && asset.id) {
                                pageStack.push(Qt.resolvedUrl("SearchResultsPage.qml"), {
                                    smartSearchAssetId: asset.id
                                })
                            }
                        }
                    }


                    IconButton {
                        width: parent.width / actionRow.buttonCount
                        icon.source: "image://theme/icon-m-whereami"
                        icon.color: Theme.lightPrimaryColor
                        enabled: assets && assets.length > 0 && assets[currentIndex]
                        onClicked: {
                            var asset = assets[currentIndex]
                            if (asset && asset.id) {
                                var assetDate = asset.localDateTime || asset.fileCreatedAt || ""
                                pageStack.pop(pageStack.find(function(p) {
                                    return p.objectName === "timelinePage"
                                }))
                                timelineModel.scrollToAsset(asset.id, assetDate)
                            }
                        }
                    }
                }

                // Bottom spacing
                Item {
                    width: 1
                    height: Theme.paddingMedium
                }
            }
        }
    }
}
