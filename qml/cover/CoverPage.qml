import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    id: cover

    property var coverMemories: []
    property int currentMemoryIndex: 0
    property int currentAssetIndex: 0
    property bool showingA: true
    property bool coverWasActive: false

    function memoryImageSource(memIdx, assetIdx) {
        if (coverMemories.length > 0 && coverMemories[memIdx] && coverMemories[memIdx].assets && coverMemories[memIdx].assets[assetIdx]) {
            return "image://immich/thumbnail/" + coverMemories[memIdx].assets[assetIdx].id
        }
        return ""
    }

    function nextMemorySource() {
        if (coverMemories.length === 0) return ""
        var nextMemIdx = currentMemoryIndex
        var nextAssetIdx = currentAssetIndex
        var currentMemory = coverMemories[nextMemIdx]
        if (currentMemory && currentMemory.assets) {
            if (nextAssetIdx < currentMemory.assets.length - 1) {
                nextAssetIdx++
            } else {
                nextAssetIdx = 0
                nextMemIdx = (nextMemIdx + 1) % coverMemories.length
            }
        }
        currentMemoryIndex = nextMemIdx
        currentAssetIndex = nextAssetIdx
        return memoryImageSource(nextMemIdx, nextAssetIdx)
    }

    function crossfadeTo(newSource) {
        if (newSource === "") return
        if (showingA) {
            coverImageB.source = newSource
            crossfadeToB.start()
        } else {
            coverImageA.source = newSource
            crossfadeToA.start()
        }
        showingA = !showingA
    }

    function showInitialImage(src) {
        crossfadeToA.stop()
        crossfadeToB.stop()
        coverImageA.source = src
        coverImageA.opacity = 1
        coverImageB.opacity = 0
        coverImageB.source = ""
        showingA = true
    }

    function clearCoverImages() {
        crossfadeToA.stop()
        crossfadeToB.stop()
        coverImageA.source = ""
        coverImageB.source = ""
        coverImageA.opacity = 1
        coverImageB.opacity = 0
        showingA = true
    }

    function loadInitialMemory() {
        if (!settingsManager.coverShowAssets) return
        if (coverMemories.length === 0) return
        currentMemoryIndex = 0
        currentAssetIndex = 0
        var src = memoryImageSource(0, 0)
        if (src !== "") showInitialImage(src)
    }

    // Cover image A
    Image {
        id: coverImageA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 1
        source: ""
    }

    // Cover image B
    Image {
        id: coverImageB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0
        source: ""
    }

    // Crossfade A to B
    ParallelAnimation {
        id: crossfadeToB
        NumberAnimation { target: coverImageA; property: "opacity"; to: 0; duration: 1000; easing.type: Easing.InOutQuad }
        NumberAnimation { target: coverImageB; property: "opacity"; to: 1; duration: 1000; easing.type: Easing.InOutQuad }
    }

    // Crossfade B to A
    ParallelAnimation {
        id: crossfadeToA
        NumberAnimation { target: coverImageA; property: "opacity"; to: 1; duration: 1000; easing.type: Easing.InOutQuad }
        NumberAnimation { target: coverImageB; property: "opacity"; to: 0; duration: 1000; easing.type: Easing.InOutQuad }
    }

    property bool hasVisibleImage: settingsManager.coverShowAssets && (coverImageA.status === Image.Ready || coverImageB.status === Image.Ready)

    // Darkening overlay for text readability
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: hasVisibleImage ? Theme.rgba("black", 0.1) : "transparent" }
            GradientStop { position: 0.6; color: hasVisibleImage ? Theme.rgba("black", 0.3) : "transparent" }
            GradientStop { position: 1.0; color: hasVisibleImage ? Theme.rgba("black", 0.7) : "transparent" }
        }
    }

    // Fallback icon when no assets
    Image {
        id: coverIcon
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -parent.height * 0.1
        width: parent.width * 0.4
        height: width
        source: Qt.resolvedUrl("../../icons/cover-icon.png")
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        opacity: hasVisibleImage ? 0 : 0.8
        visible: opacity > 0
        Behavior on opacity { FadeAnimation { duration: 500 } }
    }

    // Bottom info area
    Column {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.itemSizeLarge + Theme.paddingSmall
        anchors.left: parent.left
        anchors.leftMargin: Theme.paddingMedium
        anchors.right: parent.right
        anchors.rightMargin: Theme.paddingMedium
        spacing: Theme.paddingSmall / 2

        // Memory title
        Label {
            id: memoryTitle
            width: parent.width
            text: {
                if (settingsManager.coverShowAssets && coverMemories.length > 0 && coverMemories[currentMemoryIndex]) {
                    var memory = coverMemories[currentMemoryIndex]
                    var currentYear = new Date().getFullYear()
                    var memoryYear = 0
                    if (memory.data && memory.data.year) {
                        memoryYear = memory.data.year
                    } else if (memory.assets && memory.assets[0] && memory.assets[0].fileCreatedAt) {
                        memoryYear = new Date(memory.assets[0].fileCreatedAt).getFullYear()
                    }
                    var yearsAgo = currentYear - memoryYear
                    if (yearsAgo <= 0) yearsAgo = 1
                    return yearsAgo === 1
                        //% "A year ago"
                        ? qsTrId("coverPage.yearAgo")
                        //% "%1 years ago"
                        : qsTrId("coverPage.yearsAgo").arg(yearsAgo)
                }
                return ""
            }
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
            color: Theme.primaryColor
            visible: text !== ""
            truncationMode: TruncationMode.Fade
        }

        // Timeline asset count
        Label {
            width: parent.width
            visible: authManager.isAuthenticated && timelineModel.totalCount > 0
            //% "%1 assets"
            text: qsTrId("coverPage.assetCount").arg(timelineModel.totalCount)
            font.pixelSize: Theme.fontSizeTiny
            color: Theme.primaryColor
        }

        //Backup status row
        Row {
            width: parent.width
            spacing: Theme.paddingSmall
            visible: settingsManager.backupEnabled && authManager.isAuthenticated

            Image {
                width: Theme.iconSizeExtraSmall
                height: width
                anchors.verticalCenter: parent.verticalCenter
                source: {
                    if (backupManager.currentFile)
                        return "image://theme/icon-s-sync"
                    if (backupManager.pendingCount > 0)
                        return "image://theme/icon-s-cloud-download"
                    return "image://theme/icon-s-installed"
                }
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Theme.fontSizeTiny
                color: Theme.highlightColor
                text: {
                    if (backupManager.currentFile) {
                        //% "Backing up..."
                        return qsTrId("coverPage.backingUp")
                    }
                    if (backupManager.pendingCount > 0) {
                        //% "%1 pending"
                        return qsTrId("coverPage.pending").arg(backupManager.pendingCount)
                    }
                    if (backupManager.backedUpCount > 0) {
                        //% "All backed up"
                        return qsTrId("coverPage.allBackedUp")
                    }
                    return ""
                }
                visible: text !== ""
            }
        }

        // App name + connection status
        Row {
            width: parent.width
            spacing: Theme.paddingSmall

            Label {
                text: "Immich"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.primaryColor
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.paddingMedium
                height: width
                radius: width / 2
                color: authManager.isAuthenticated ? Theme.rgba("green", 0.8) : Theme.rgba("red", 0.6)
            }
        }
    }

    // Slideshow timer
    Timer {
        id: slideshowTimer
        interval: 10000
        running: cover.status === Cover.Active && settingsManager.coverShowAssets && settingsManager.coverSlideshow && coverMemories.length > 0
        repeat: true
        onTriggered: {
            var src = nextMemorySource()
            crossfadeTo(src)
        }
    }

    // Track cover active for single change
    onStatusChanged: {
        if (status === Cover.Active && !coverWasActive) {
            coverWasActive = true
            if (settingsManager.coverShowAssets && !settingsManager.coverSlideshow && coverMemories.length > 0) {
                var src = nextMemorySource()
                if (src !== "") crossfadeTo(src)
            }
        } else if (status !== Cover.Active) {
            coverWasActive = false
        }
    }

    // Cover actions when backup is enabled
    CoverActionList {
        enabled: authManager.isAuthenticated && settingsManager.backupEnabled

        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: {
                immichApi.fetchMemories()
            }
        }

        CoverAction {
            iconSource: "image://theme/icon-cover-sync"
            onTriggered: {
                backupManager.scanNow()
            }
        }
    }

    // Cover actions when backup is disabled
    CoverActionList {
        enabled: authManager.isAuthenticated && !settingsManager.backupEnabled

        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: {
                immichApi.fetchMemories()
            }
        }
    }

    Connections {
        target: immichApi
        onMemoriesReceived: {
            var filtered = []
            for (var i = 0; i < memories.length; i++) {
                var memory = memories[i]
                if (memory.type === "on_this_day" && memory.assets && memory.assets.length > 0) {
                    filtered.push(memory)
                }
            }
            cover.coverMemories = filtered
            if (settingsManager.coverShowAssets && filtered.length > 0) {
                loadInitialMemory()
            }
        }
    }

    Connections {
        target: settingsManager
        onCoverShowAssetsChanged: {
            if (!settingsManager.coverShowAssets) {
                clearCoverImages()
            } else {
                loadInitialMemory()
            }
        }
    }

    Connections {
        target: authManager
        onIsAuthenticatedChanged: {
            if (!authManager.isAuthenticated) {
                coverMemories = []
                clearCoverImages()
            }
        }
    }
}
