import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"

ApplicationWindow
{
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    // Start with empty page stack to be populated after credentials check
    Component.onCompleted: {
        pageStack.push(loadingPageComponent)
    }

    Component {
        id: loadingPageComponent
        Page {
            BusyIndicator {
                anchors.centerIn: parent
                size: BusyIndicatorSize.Large
                running: true
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
            pageStack.clear()
            pageStack.push(Qt.resolvedUrl("pages/TimelinePage.qml"))
        }
        onLoginFailed: {
            // No valid credentials, show login
            pageStack.clear()
            pageStack.push(Qt.resolvedUrl("pages/ServerPage.qml"))
        }
    }
}
