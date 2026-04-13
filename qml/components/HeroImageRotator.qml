import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    id: root

    property var assetIds: []
    property bool active: true
    property int interval: 6000
    property real gradientHeight: 0.6
    property real gradientOpacity: 0.95

    clip: true

    Image {
        id: heroImageA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        opacity: 1
        scale: 1.0
        source: root.assetIds.length > 0 ? "image://immich/detail/" + root.assetIds[0] : ""
    }

    Image {
        id: heroImageB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        opacity: 0
        scale: 1.0
        source: ""
    }

    NumberAnimation {
        id: zoomAnimA
        target: heroImageA
        property: "scale"
        from: 1.0
        to: 1.15
        duration: 8000
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: zoomAnimB
        target: heroImageB
        property: "scale"
        from: 1.0
        to: 1.15
        duration: 8000
        easing.type: Easing.Linear
    }

    ParallelAnimation {
        id: crossfadeToB
        NumberAnimation { target: heroImageA; property: "opacity"; to: 0; duration: 1500; easing.type: Easing.InOutQuad }
        NumberAnimation { target: heroImageB; property: "opacity"; to: 1; duration: 1500; easing.type: Easing.InOutQuad }
    }

    ParallelAnimation {
        id: crossfadeToA
        NumberAnimation { target: heroImageA; property: "opacity"; to: 1; duration: 1500; easing.type: Easing.InOutQuad }
        NumberAnimation { target: heroImageB; property: "opacity"; to: 0; duration: 1500; easing.type: Easing.InOutQuad }
    }

    property int _heroIndex: 0
    property bool _showingA: true

    Timer {
        id: heroTimer
        interval: root.interval
        repeat: true
        running: root.assetIds.length > 1 && root.active
        onTriggered: {
            root._heroIndex = (root._heroIndex + 1) % root.assetIds.length
            var nextSource = "image://immich/detail/" + root.assetIds[root._heroIndex]

            if (root._showingA) {
                heroImageB.scale = 1.0
                heroImageB.source = nextSource
                crossfadeToB.start()
                zoomAnimB.start()
            } else {
                heroImageA.scale = 1.0
                heroImageA.source = nextSource
                crossfadeToA.start()
                zoomAnimA.start()
            }
            root._showingA = !root._showingA
        }
    }

    Component.onCompleted: {
        if (root.assetIds.length > 0) {
            zoomAnimA.start()
        }
    }

    onAssetIdsChanged: {
        if (root.assetIds.length > 0 && heroImageA.source === "") {
            heroImageA.source = "image://immich/detail/" + root.assetIds[0]
            zoomAnimA.start()
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * root.gradientHeight
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightDimmerColor, root.gradientOpacity) }
        }
    }
}
