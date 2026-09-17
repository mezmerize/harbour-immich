import QtQuick 2.0
import Sailfish.Silica 1.0
import QtMultimedia 5.6
import harbour.immich.media 1.0

Item {
    id: root

    property string videoId: ""
    property string filePath: ""
    property string thumbhash: ""
    property bool active: false
    property real controlsBottomMargin: 0
    property bool controlsVisible: true
    property bool controlsEnabled: true

    signal loaded()
    signal finished()

    // Internal player variables
    property bool hasVideoFrame: false
    property bool sourceLoadedEmitted: false
    property var authManagerShaded: authManager
    property bool surfaceReady: false
    property bool loadPending: false

    function toggleControls() {
        if (!controlsEnabled) return
        if (controlsVisible) {
            controlsVisible = false
            controlsHideTimer.stop()
        } else {
            controlsVisible = true
            if (controller.playbackState === VideoController.PlayingState) {
                controlsHideTimer.restart()
            }
        }
    }

    function togglePlayback() {
        if (!controlsEnabled) return
        if (controller.playbackState === VideoController.PlayingState) {
            controller.pause()
            controlsVisible = true
            controlsHideTimer.stop()
        } else {
            controller.play()
            controlsHideTimer.restart()
        }
    }

    function play() {
        controller.play()
        controlsHideTimer.restart()
    }

    function pause() {
        controller.pause()
        controlsVisible = true
        controlsHideTimer.stop()
    }

    function stop() {
        controller.stop()
        controlsHideTimer.stop()
    }

    function loadSource() {
        if (!active || (!videoId && !filePath)) return
        if (!surfaceReady) {
            loadPending = true
            return
        }
        loadPending = false
        hasVideoFrame = false
        sourceLoadedEmitted = false
        controlsVisible = true
        if (filePath) {
            controller.loadLocalFile(filePath)
        } else {
            controller.load(videoId)
        }
    }

    function unloadSource() {
        loadPending = false
        controller.unload()
        controlsHideTimer.stop()
        hasVideoFrame = false
        sourceLoadedEmitted = false
    }

    onActiveChanged: {
        if (active) {
            loadSource()
        } else {
            unloadSource()
        }
    }

    onVideoIdChanged: {
        if (active) loadSource()
    }

    onFilePathChanged: {
        if (active) loadSource()
    }

    Component.onCompleted: checkSurfaceReady()

    onVisibleChanged: checkSurfaceReady()

    function checkSurfaceReady() {
        if (surfaceReady) return
        if (visible && videoSurface.width > 0 && videoSurface.height > 0) surfaceSettleTimer.start()
    }

    function markSurfaceReady() {
        if (surfaceReady) return
        if (!(visible && videoSurface.width > 0 && videoSurface.height > 0)) return
        surfaceReady = true
        if (loadPending) loadSource()
    }

    function formatTime(milliseconds) {
        if (!milliseconds || milliseconds < 0) return "0:00"
        var seconds = Math.floor(milliseconds / 1000)
        var minutes = Math.floor(seconds / 60)
        var hours = Math.floor(minutes / 60)

        seconds = seconds % 60
        minutes = minutes % 60

        if (hours > 0) {
            return hours + ":" + pad(minutes) + ":" + pad(seconds)
        } else {
            return minutes + ":" + pad(seconds)
        }
    }

    function pad(num) {
        return (num < 10 ? "0" : "") + num
    }

    Timer {
        id: controlsHideTimer
        interval: 4000
        onTriggered: {
            if (controller.playbackState === VideoController.PlayingState) {
                root.controlsVisible = false
            }
        }
    }

    Timer {
        id: surfaceSettleTimer
        interval: 0
        repeat: false
        onTriggered: root.markSurfaceReady()
    }

    VideoController {
        id: controller
        authManager: root.authManagerShaded

        onLoaded: {
            root.hasVideoFrame = true
            if (!root.sourceLoadedEmitted) {
                root.sourceLoadedEmitted = true
                root.loaded()
            }
        }

        onMediaStatusChanged: {
            if (mediaStatus === VideoController.EndOfMedia) {
                controller.seek(0)
                progressSlider.value = 0
                root.controlsVisible = true
                controlsHideTimer.stop()
                root.finished()
            }
        }

        onPositionChanged: {
            if (!progressSlider.userDragging) progressSlider.value = controller.position
        }

        onErrorChanged: {
            if (error !== VideoController.NoError) console.error("VideoPlayer: media error", error, errorString, "for", root.videoId)
        }
    }

    // Black backdrop behind the video frame
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    VideoOutput {
        id: videoSurface
        anchors.fill: parent
        source: controller
        fillMode: VideoOutput.PreserveAspectFit
    }

    // Thumbhash until the first frame is ready
    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        source: root.thumbhash ? "image://thumbhash/" + root.thumbhash : ""
        visible: !root.hasVideoFrame && root.thumbhash !== ""
        asynchronous: false
        smooth: true
        cache: true
    }

    // Play and pause button
    Rectangle {
        anchors.centerIn: parent
        width: Theme.itemSizeExtraLarge
        height: Theme.itemSizeExtraLarge
        radius: width / 2
        color: Theme.rgba("black", 0.4)
        visible: root.controlsEnabled && root.controlsVisible
        opacity: (root.controlsEnabled && root.controlsVisible) ? 1.0 : 0.0
        Behavior on opacity { FadeAnimation { duration: 200 } }

        Image {
            anchors.centerIn: parent
            source: controller.playbackState === VideoController.PlayingState ? "image://theme/icon-l-pause" : "image://theme/icon-l-play"
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.togglePlayback()
        }
    }

    // Loading indicator
    LoadingIndicator {
        anchors.centerIn: parent
        loading: controller.status === VideoController.Loading || controller.status === VideoController.Buffering
    }

    // Error state
    Column {
        anchors.centerIn: parent
        spacing: Theme.paddingMedium
        visible: controller.failed

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "image://theme/icon-m-video"
            width: Theme.iconSizeLarge
            height: Theme.iconSizeLarge
            opacity: 0.5
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            //% "Failed to load video"
            text: qsTrId("videoPlayer.failed")
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeMedium
        }
    }

    // Controls bar at bottom
    Rectangle {
        id: controlsBar
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.controlsBottomMargin
        anchors.left: parent.left
        anchors.right: parent.right
        height: controlsContent.height + Theme.paddingMedium * 2
        color: Theme.rgba("black", 0.6)
        visible: root.controlsEnabled && root.controlsVisible
        opacity: (root.controlsEnabled && root.controlsVisible) ? 1.0 : 0.0
        Behavior on opacity { FadeAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
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
            id: controlsContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.paddingMedium
            spacing: Theme.paddingSmall

            // Time row
            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingSmall

                Label {
                    id: positionLabel
                    width: Math.max(implicitWidth, Theme.itemSizeSmall)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatTime(controller.position)
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.primaryColor
                    horizontalAlignment: Text.AlignRight
                }

                Slider {
                    id: progressSlider
                    width: parent.width - positionLabel.width - durationLabel.width - Theme.paddingSmall * 2
                    anchors.verticalCenter: parent.verticalCenter
                    minimumValue: 0
                    maximumValue: Math.max(1, controller.duration)
                    enabled: controller.seekable
                    handleVisible: true

                    property bool userDragging: false

                    onPressed: {
                        userDragging = true
                        controlsHideTimer.stop()
                    }

                    onReleased: {
                        userDragging = false
                        controller.seek(value)
                        if (controller.playbackState === VideoController.PlayingState) {
                            controlsHideTimer.restart()
                        }
                    }
                }

                Label {
                    id: durationLabel
                    width: Math.max(implicitWidth, Theme.itemSizeSmall)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.formatTime(controller.duration)
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                }
            }
        }
    }
}
