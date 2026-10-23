import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: root

    property var assetIds: []
    property string sourcePrefix: "image://immich/detail/"
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
        source: ""
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

    property int heroIndex: 0
    property bool showingA: true
    property string currentId: ""

    // Crossfades to the given asset id on whichever image is hidden
    function showId(id) {
        var nextSource = sourcePrefix + id
        if (showingA) {
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
        showingA = !showingA
        currentId = id
    }

    Timer {
        id: heroTimer
        interval: root.interval
        repeat: true
        running: root.assetIds.length > 1 && root.active
        onTriggered: {
            root.heroIndex = (root.heroIndex + 1) % root.assetIds.length
            root.showId(root.assetIds[root.heroIndex])
        }
    }

    Component.onCompleted: {
        if (root.assetIds.length > 0) {
            heroImageA.source = root.sourcePrefix + root.assetIds[0]
            root.currentId = root.assetIds[0]
            zoomAnimA.start()
        }
    }

    onAssetIdsChanged: {
        if (root.assetIds.length === 0) {
            crossfadeToA.stop()
            crossfadeToB.stop()
            zoomAnimA.stop()
            zoomAnimB.stop()
            heroImageA.source = ""
            heroImageB.source = ""
            root.currentId = ""
            root.heroIndex = 0
            root.showingA = true
            heroImageA.opacity = 1
            heroImageB.opacity = 0
        } else if (root.currentId === "") {
            heroImageA.source = root.sourcePrefix + root.assetIds[0]
            root.currentId = root.assetIds[0]
            root.heroIndex = 0
            zoomAnimA.start()
        } else if (root.assetIds.indexOf(root.currentId) < 0) {
            root.heroIndex = 0
            root.showId(root.assetIds[0])
        } else {
            root.heroIndex = root.assetIds.indexOf(root.currentId)
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
