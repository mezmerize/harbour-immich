import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.KeepAlive 1.2
import "pages"
import "components"

ApplicationWindow
{
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations
    _defaultPageOrientations: Orientation.All

    // Appearance mode (system / light / dark) — Settings > Display > Appearance.
    // Silica's Theme.setColorScheme() is in-memory only, so it is re-applied on
    // launch, on setting change, and whenever the app regains focus (so "system"
    // picks up OS theme changes made while in the background).
    // Note: the Theme enum is counter-intuitive — LightOnDark is the DARK theme and
    // DarkOnLight is the LIGHT theme.
    // Never "keep the current scheme" when the target cannot be resolved: doing so can
    // strand the UI on a stale palette (e.g. black text on the dark system background
    // after a light → system switch). Always fall back to the captured system default.
    function applyThemeMode() {
        var mode = settingsManager.themeMode
        var scheme = -1
        if (mode === "light") {
            scheme = Theme.DarkOnLight
        } else if (mode === "dark") {
            scheme = Theme.LightOnDark
        } else {
            // Follow the system: prefer the live OS value from dconf (async,
            // see SettingsManager::refreshSystemColorScheme); fall back to the
            // scheme Silica started with (the system derives it from the OS theme).
            if (settingsManager.systemColorScheme >= 0) {
                scheme = settingsManager.systemColorScheme === 1 ? Theme.DarkOnLight : Theme.LightOnDark
            } else {
                scheme = settingsManager.systemDefaultScheme
            }
        }
        if (scheme >= 0 && scheme === Theme.colorScheme) {
            return // already correct
        }
        if (scheme >= 0) {
            console.log("Theme: applying mode=" + mode + " scheme=" + scheme + " (was " + Theme.colorScheme + ")")
            Theme.setColorScheme(scheme)
        } else {
            console.log("Theme: mode=" + mode + " no usable scheme, keeping current " + Theme.colorScheme)
        }
    }

    function shouldShowClientCertWarning() {
        if (!clientCertManager.hasCertificate) return
        if (!clientCertManager.isExpired && !clientCertManager.isExpiringSoon) return
        clientCertWarningTimer.restart()
    }

    // Light (appearance) mode: Silica turns its palette light but the system
    // window background stays dark, so a page/menu surface would render dark with
    // black text (unreadable). In light mode we force an opaque light surface;
    // otherwise we keep the caller's own dark-mode surface (transparent for pages,
    // the highlight-bar color for menus). Defined ONCE here and used everywhere
    // as __silica_applicationwindow_instance.lightSurface(<darkFallback>).
    function lightSurface(darkFallback) {
        return Theme.colorScheme === Theme.DarkOnLight
            ? Qt.rgba(0.95, 0.95, 0.95)
            : darkFallback
    }

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
            backupManager.scanNowIfDue()
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
        // Capture the system-derived scheme BEFORE applying our saved mode —
        // this is what "system" falls back to when dconf is unavailable.
        settingsManager.setSystemDefaultScheme(Theme.colorScheme)
        // Kick the async dconf read so "system" has a live value ready.
        settingsManager.refreshSystemColorScheme()
        applyThemeMode()
        pageStack.push(loadingPageComponent)
    }

    // NOTE: use the classic onX: handler, NOT the `function onX() {}` syntax —
    // the function form silently never fires on this Qt (5.6).
    Connections {
        target: settingsManager
        onThemeModeChanged: applyThemeMode()
        onSystemColorSchemeChanged: {
            // async dconf result landed: re-apply while in "system" mode
            if (settingsManager.themeMode === "system") {
                applyThemeMode()
            }
        }
    }

    // NOTE: the SFOS ApplicationWindow is NOT a QtQuick.Window Window — it has no
    // "active" property. Use Silica's applicationActive instead.
    onApplicationActiveChanged: {
        // Re-sync when returning to the foreground so "system" follows OS changes.
        if (applicationActive && settingsManager.themeMode === "system") {
            settingsManager.refreshSystemColorScheme()
            applyThemeMode()
        }
    }

    Timer {
        id: clientCertWarningTimer
        interval: 1200
        onTriggered: clientCertManager.isExpired
            //% "Client certificate has expired. Update it to keep connecting."
            ? notification.showError(qsTrId("app.clientCertExpired"))
            //% "Client certificate expires in %1 day(s)."
            : notification.showError(qsTrId("app.clientCertExpiringSoon").arg(clientCertManager.daysUntilExpiry))
    }

    NotificationBanner {
        id: notification
        anchors.top: parent.top
        z: 10
    }

    Component {
        id: loadingPageComponent
        Page {
            objectName: "loadingPage"
            backgroundColor: __silica_applicationwindow_instance.lightSurface(Theme.rgba(palette.overlayBackgroundColor, 0))

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
            if (pageName === "loadingPage" || pageName === "loginPage" || pageName === "oauthPage") {
                pageStack.clear()
                pageStack.push(Qt.resolvedUrl("pages/TimelinePage.qml"))
            }
            if (!authManager.serverSupported) {
                notification.showError(qsTrId("loginPage.versionUnsupported"))
            }
            shouldShowClientCertWarning()
        }
        onLoginFailed: {
            // Redirect to server page should happen only during automatic credentials check not when user interacts with it
            var currentPage = pageStack.currentPage
            var pageName = currentPage && currentPage.objectName ? currentPage.objectName : ""
            if (pageName === "loadingPage" || pageName === "") {
                pageStack.clear()
                pageStack.push(Qt.resolvedUrl("pages/ServerPage.qml"), { errorText: error })
            }
        }
    }
}
