import QtQuick 2.0
import Sailfish.Silica 1.0

PinchArea {
    id: root

    property var stateTarget
    property var imageTarget
    property real viewportWidth: 0
    property real viewportHeight: 0
    property int currentIndex: -1
    property int totalCount: 0
    property bool enableZoom: true
    property bool enableHorizontal: true
    property bool enableDismiss: true
    property bool enableInfo: true
    property bool wrapAround: false
    property real maxScale: 4.0
    property real doubleTapScale: 2.5

    signal prevRequested()
    signal nextRequested()
    signal infoRequested()
    signal dismissRequested()
    signal tapped()

    property real startScale: 1.0

    function clampPan() {
        if (!stateTarget || !imageTarget) return
        if (stateTarget.imageScale <= 1.0) {
            stateTarget.panX = 0
            stateTarget.panY = 0
            return
        }
        var pw = imageTarget.paintedWidth * stateTarget.imageScale
        var ph = imageTarget.paintedHeight * stateTarget.imageScale
        var maxX = Math.max(0, (pw - viewportWidth) / 2)
        var maxY = Math.max(0, (ph - viewportHeight) / 2)
        stateTarget.panX = Math.max(-maxX, Math.min(maxX, stateTarget.panX))
        stateTarget.panY = Math.max(-maxY, Math.min(maxY, stateTarget.panY))
    }

    ParallelAnimation {
        id: zoomResetAnim
        NumberAnimation { target: root.stateTarget; property: "imageScale"; to: 1.0; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { target: root.stateTarget; property: "panX"; to: 0; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { target: root.stateTarget; property: "panY"; to: 0; duration: 200; easing.type: Easing.OutQuad }
    }

    NumberAnimation {
        id: dragResetAnim
        target: root.stateTarget
        property: "dragOffsetY"
        to: 0
        duration: 200
        easing.type: Easing.OutQuad
    }

    NumberAnimation {
        id: slideToNextAnim
        target: root.stateTarget
        property: "slideOffset"
        to: -root.viewportWidth
        duration: 250
        easing.type: Easing.OutQuad
        onStopped: {
            if (!root.stateTarget) return
            root.stateTarget.slideOffset = 0
            root.nextRequested()
        }
    }

    NumberAnimation {
        id: slideToPrevAnim
        target: root.stateTarget
        property: "slideOffset"
        to: root.viewportWidth
        duration: 250
        easing.type: Easing.OutQuad
        onStopped: {
            if (!root.stateTarget) return
            root.stateTarget.slideOffset = 0
            root.prevRequested()
        }
    }

    NumberAnimation {
        id: slideResetAnim
        target: root.stateTarget
        property: "slideOffset"
        to: 0
        duration: 200
        easing.type: Easing.OutQuad
    }

    onPinchStarted: {
        if (!enableZoom || !stateTarget) return
        startScale = stateTarget.imageScale
    }

    onPinchUpdated: {
        if (!enableZoom || !stateTarget) return
        stateTarget.imageScale = Math.max(1.0, Math.min(maxScale, startScale * pinch.scale))
        stateTarget.panX += pinch.center.x - pinch.previousCenter.x
        stateTarget.panY += pinch.center.y - pinch.previousCenter.y
        clampPan()
    }

    onPinchFinished: {
        if (!enableZoom || !stateTarget) return
        if (stateTarget.imageScale < 1.1) {
            zoomResetAnim.start()
        }
    }

    MouseArea {
        anchors.fill: parent

        property real lastPageX: 0
        property real lastPageY: 0
        property bool gestureDecided: false
        property bool horizontalGesture: false

        onPressed: {
            if (!root.stateTarget) return
            slideToNextAnim.stop()
            slideToPrevAnim.stop()
            slideResetAnim.stop()
            dragResetAnim.stop()
            root.stateTarget.slideOffset = 0

            var pp = mapToItem(root.stateTarget, mouse.x, mouse.y)
            lastPageX = pp.x
            lastPageY = pp.y
            gestureDecided = false
            horizontalGesture = false
        }

        onPositionChanged: {
            if (!root.stateTarget) return
            var pp = mapToItem(root.stateTarget, mouse.x, mouse.y)
            var deltaX = pp.x - lastPageX
            var deltaY = pp.y - lastPageY
            var zoomed = root.stateTarget.imageScale > 1.05

            if (enableZoom && zoomed) {
                root.stateTarget.panX += deltaX
                root.stateTarget.panY += deltaY
                root.clampPan()
            } else {
                if (!gestureDecided) {
                    if (Math.abs(deltaX) > Theme.startDragDistance || Math.abs(deltaY) > Theme.startDragDistance) {
                        gestureDecided = true
                        horizontalGesture = Math.abs(deltaX) > Math.abs(deltaY)
                    }
                }

                if (gestureDecided) {
                    if (horizontalGesture && enableHorizontal) {
                        var slideD = deltaX
                        if (!wrapAround && ((currentIndex <= 0 && root.stateTarget.slideOffset + slideD > 0) ||
                                (currentIndex >= totalCount - 1 && root.stateTarget.slideOffset + slideD < 0))) {
                            slideD *= 0.3
                        }
                        root.stateTarget.slideOffset += slideD
                    } else if (enableDismiss) {
                        root.stateTarget.draggingVertical = true
                        root.stateTarget.dragOffsetY += deltaY
                    }
                }
            }

            lastPageX = pp.x
            lastPageY = pp.y
        }

        onReleased: {
            if (!root.stateTarget) return
            var zoomed = root.stateTarget.imageScale > 1.05
            if (enableZoom && zoomed) {
            } else if (root.stateTarget.draggingVertical) {
                root.stateTarget.draggingVertical = false
                if (root.stateTarget.dragOffsetY > root.stateTarget.dismissThreshold) {
                    root.dismissRequested()
                } else {
                    if (root.enableInfo && root.stateTarget.dragOffsetY < - root.stateTarget.dismissThreshold) {
                        root.infoRequested()
                    }
                    dragResetAnim.start()
                }
            } else if (gestureDecided && horizontalGesture && enableHorizontal) {
                if (root.stateTarget.slideOffset > root.viewportWidth * 0.15 && (wrapAround || currentIndex > 0)) {
                    slideToPrevAnim.start()
                } else if (root.stateTarget.slideOffset < -root.viewportWidth * 0.15 && (wrapAround || currentIndex < totalCount - 1)) {
                    slideToNextAnim.start()
                } else {
                    slideResetAnim.start()
                }
            } else if (!gestureDecided) {
                root.tapped()
            }

            gestureDecided = false
            horizontalGesture = false
        }

        onDoubleClicked: {
            if (!enableZoom || !root.stateTarget) return
            var zoomed = root.stateTarget.imageScale > 1.05
            if (zoomed) {
                zoomResetAnim.start()
            } else {
                var pp = mapToItem(root.stateTarget, mouse.x, mouse.y)
                root.stateTarget.panX = (pp.x - root.viewportWidth / 2) * (1 - doubleTapScale)
                root.stateTarget.panY = (pp.y - root.viewportHeight / 2) * (1 - doubleTapScale)
                root.stateTarget.imageScale = doubleTapScale
                root.clampPan()
            }
        }
    }
}
