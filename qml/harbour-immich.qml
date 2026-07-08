import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.KeepAlive 1.2
import "pages"
import "components"

ApplicationWindow
{
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    // Background backup job - wakes the device periodically to scan and upload
    BackgroundJob {
        id: backupJob
        enabled: settingsManager.backupEnabled && authManager.isAuthenticated && settingsManager.backupScanInterval > 0
        frequency: {
            var mins = settingsManager.backupScanInterval
            if (mins <= 30) return BackgroundJob.ThirtyMinutes
            if (mins <= 60) return BackgroundJob.OneHour
            if (mins <= 240) return BackgroundJob.FourHours
            return BackgroundJob.EightHours
        }
        onTriggered: {
            console.log("BackgroundJob: Wakeup triggered, starting backup scan")
            backupManager.scanNow()
            // If no active work finish immediately, otherwise wait for completion
            if (!backupManager.backgroundActive) {
                backupJob.finished()
            }
        }
    }

    Connections {
        target: backupManager
        onBackgroundActiveChanged: {
            // Release wakelock when background work completes
            if (!backupManager.backgroundActive && backupJob.running) {
                console.log("BackgroundJob: Work complete, releasing wakelock")
                backupJob.finished()
            }
        }
    }

    // Start with empty page stack to be populated after credentials check
    Component.onCompleted: {
        pageStack.push(loadingPageComponent)
    }

    Component {
        id: loadingPageComponent
        Page {
            objectName: "loadingPage"

            LoadingIndicator {
                anchors.centerIn: parent
                loading: true
            }
        }
    }

    Connections {
        target: secureStorage
        onInitialized: {
            authManager.checkStoredCredentials()
        }
        onError: {
            // Secrets unavailable for some reason (SDK emulator for example)
            pageStack.clear()
            pageStack.push(Qt.resolvedUrl("pages/ServerPage.qml"))
        }
    }

    Connections {
        target: authManager
        onLoginSucceeded: {
            var currentPage = pageStack.currentPage
            var pageName = currentPage && currentPage.objectName ? currentPage.objectName : ""
            if (pageName === "loadingPage" || pageName === "loginPage") {
                pageStack.clear()
                pageStack.push(Qt.resolvedUrl("pages/TimelinePage.qml"))
            }
        }
        onLoginFailed: {
            // Redirect to server page should happen only during automatic credentials check not when user interacts with it
            var currentPage = pageStack.currentPage
            var pageName = currentPage && currentPage.objectName ? currentPage.objectName : ""
            if (pageName === "loadingPage" || pageName === "") {
                pageStack.clear()
                pageStack.push(Qt.resolvedUrl("pages/ServerPage.qml"))
            }
        }
    }
}
