import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Dialog {
    id: dialog

    property var assetIds: []
    property var albumId: null
    property string shareType: "INDIVIDUAL" // INDIVIDUAL or ALBUM
    property bool albumShare: shareType === "ALBUM"
    property var albumInfo: null
    property bool isOwner: albumInfo && albumInfo.owner && albumInfo.owner.id === authManager.userId
    property bool albumActivityEnabled: true
    property bool suppressAlbumActivitySave: false
    property var selectedUserIds: []
    property string selectedRole: "editor"
    property bool usersLoaded: false
    property var allUsers: []

    canAccept: false  // Prevent normal dialog acceptance

    function rebuildMemberModel() {
        memberListModel.clear()
        var albumUsers = albumInfo && albumInfo.albumUsers ? albumInfo.albumUsers : []
        for (var i = 0; i < albumUsers.length; i++) {
            var au = albumUsers[i]
            var u = au.user
            if (!u) continue
            memberListModel.append({
                odUserId: u.id || "",
                odName: u.name || "",
                odEmail: u.email || "",
                odRole: au.role || "editor",
                odIsMe: (u.id || "") === authManager.userId
            })
        }
    }

    function rebuildAvailableModel() {
        userListModel.clear()
        // Build existing IDs from current albumInfo
        var existingIds = []
        var albumUsers = albumInfo && albumInfo.albumUsers ? albumInfo.albumUsers : []
        for (var i = 0; i < albumUsers.length; i++) {
            var u = albumUsers[i].user
            if (u && u.id) existingIds.push(u.id)
        }
        if (albumInfo && albumInfo.owner && albumInfo.owner.id)
            existingIds.push(albumInfo.owner.id)

        var count = 0
        for (var j = 0; j < allUsers.length; j++) {
            var user = allUsers[j]
            var userId = user.id || ""
            if (existingIds.indexOf(userId) > -1) continue
            userListModel.append({
                userId: userId,
                name: user.name || "",
                email: user.email || ""
            })
            count++
        }
        noUsersLabel.visible = (count === 0 && dialog.isOwner && dialog.usersLoaded)
    }

    function startRemoveUser(uid) {
        //% "Removing user"
        remorseItem.execute(qsTrId("notification.removingUser"), function() {
            immichApi.removeAlbumUser(dialog.albumId, uid)
        })
    }

    function startLeaveAlbum() {
        //% "Leaving album"
        remorseItem.execute(qsTrId("notification.leavingAlbum"), function() {
            immichApi.removeAlbumUser(dialog.albumId, authManager.userId)
        })
    }

    function saveAlbumSettings() {
        if (!dialog.albumShare || !dialog.isOwner || !dialog.albumInfo)
            return

        immichApi.updateAlbum(dialog.albumId, dialog.albumInfo.albumName || "", dialog.albumInfo.description ? dialog.albumInfo.description : "", dialog.albumActivityEnabled, dialog.albumInfo.albumThumbnailAssetId ? dialog.albumInfo.albumThumbnailAssetId : "")
    }

    onAlbumInfoChanged: {
        var activityEnabled = albumInfo && albumInfo.isActivityEnabled !== undefined ? albumInfo.isActivityEnabled : true
        dialog.suppressAlbumActivitySave = true
        dialog.albumActivityEnabled = activityEnabled
        if (activitySwitch) {
            activitySwitch.checked = activityEnabled
        }
        dialog.suppressAlbumActivitySave = false
        rebuildMemberModel()
        if (usersLoaded) rebuildAvailableModel()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: dialog.albumShare
                    //% "Share Album"
                    ? qsTrId("sharePage.shareAlbum")
                    //% "Create Share Link"
                    : qsTrId("sharePage.createShareLink")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: dialog.albumShare
                text: dialog.isOwner
                    //% "Manage album members here. Public share links are configured separately below."
                    ? qsTrId("sharePage.albumAccessOwner")
                    //% "Album membership is managed separately from the optional public share link below."
                    : qsTrId("sharePage.albumAccessNotOwner")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                //% "Album members"
                text: qsTrId("sharePage.albumMembers")
                visible: dialog.albumShare && memberListModel.count > 0
            }

            Repeater {
                model: ListModel { id: memberListModel }
                visible: dialog.albumShare

                ListItem {
                    id: memberItem
                    contentHeight: Theme.itemSizeSmall
                    menu: dialog.isOwner ? memberContextMenu : null

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.horizontalPageMargin
                        anchors.rightMargin: Theme.horizontalPageMargin
                        spacing: Theme.paddingMedium

                        Image {
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            anchors.verticalCenter: parent.verticalCenter
                            source: "image://theme/icon-m-contact"
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium

                            Label {
                                width: parent.width
                                //% " (you)"
                                text: model.odName + (model.odIsMe ? qsTrId("sharePage.you") : "")
                                color: memberItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                            }

                            Label {
                                width: parent.width
                                text: model.odRole === "editor"
                                    //% "Editor"
                                    ? qsTrId("sharePage.roleEditor")
                                    //% "Viewer"
                                    : qsTrId("sharePage.roleViewer")
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: memberItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                            }
                        }
                    }

                    Component {
                        id: memberContextMenu
                        ContextMenu {
                            MenuItem {
                                text: model.odRole === "editor"
                                    //% "Change to viewer"
                                    ? qsTrId("sharePage.changeToViewer")
                                    //% "Change to editor"
                                    : qsTrId("sharePage.changeToEditor")
                                onClicked: {
                                    var newRole = model.odRole === "editor" ? "viewer" : "editor"
                                    immichApi.updateAlbumUserRole(dialog.albumId, model.odUserId, newRole)
                                }
                            }
                            MenuItem {
                                //% "Remove from album"
                                text: qsTrId("sharePage.removeFromAlbum")
                                onClicked: {
                                    dialog.startRemoveUser(model.odUserId)
                                }
                            }
                        }
                    }
                }
            }

            // Leave album (non-owner)
            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: dialog.albumShare && !dialog.isOwner && memberListModel.count > 0

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.rightMargin: Theme.horizontalPageMargin
                    spacing: Theme.paddingMedium

                    Image {
                        width: Theme.iconSizeMedium
                        height: Theme.iconSizeMedium
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-dismiss"
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        //% "Leave album"
                        text: qsTrId("sharePage.leaveAlbum")
                        color: Theme.errorColor
                    }
                }

                onClicked: dialog.startLeaveAlbum()
            }

            SectionHeader {
                //% "Add users"
                text: qsTrId("sharePage.addUsersSection")
                visible: dialog.albumShare && dialog.isOwner
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: dialog.albumShare && !dialog.usersLoaded && dialog.isOwner
                visible: running
            }

            Label {
                id: noUsersLabel
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Theme.horizontalPageMargin * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Theme.secondaryHighlightColor
                //% "No users available to add"
                text: qsTrId("sharePage.noUsers")
                visible: false
            }

            Repeater {
                model: ListModel { id: userListModel }
                visible: dialog.albumShare && dialog.isOwner

                BackgroundItem {
                    id: userItem
                    width: parent.width
                    height: Theme.itemSizeSmall
                    visible: dialog.isOwner

                    property bool isSelected: dialog.selectedUserIds.indexOf(model.userId) > -1

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.horizontalPageMargin
                        anchors.rightMargin: Theme.horizontalPageMargin
                        spacing: Theme.paddingMedium

                        Image {
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            anchors.verticalCenter: parent.verticalCenter
                            source: "image://theme/icon-m-contact"

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.width: userItem.isSelected ? 2 : 0
                                border.color: Theme.highlightColor
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.iconSizeMedium - checkIcon.width - Theme.paddingMedium * 2

                            Label {
                                width: parent.width
                                text: model.name
                                color: userItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                            }

                            Label {
                                width: parent.width
                                text: model.email
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: Theme.secondaryColor
                                truncationMode: TruncationMode.Fade
                            }
                        }

                        Icon {
                            id: checkIcon
                            width: Theme.iconSizeSmall
                            height: Theme.iconSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                            source: "image://theme/icon-s-installed"
                            visible: userItem.isSelected
                        }
                    }

                    onClicked: {
                        var idx = dialog.selectedUserIds.indexOf(model.userId)
                        if (idx > -1) {
                            dialog.selectedUserIds.splice(idx, 1)
                        } else {
                            dialog.selectedUserIds.push(model.userId)
                        }
                        dialog.selectedUserIds = dialog.selectedUserIds
                    }
                }
            }

            ComboBox {
                width: parent.width
                visible: dialog.albumShare && dialog.isOwner && dialog.selectedUserIds.length > 0
                //% "Role"
                label: qsTrId("sharePage.role")
                currentIndex: dialog.selectedRole === "editor" ? 0 : 1

                menu: ContextMenu {
                    //% "Editor"
                    MenuItem { text: qsTrId("sharePage.roleEditorOption") }
                    //% "Viewer"
                    MenuItem { text: qsTrId("sharePage.roleViewerOption") }
                }

                onCurrentIndexChanged: {
                    dialog.selectedRole = currentIndex === 0 ? "editor" : "viewer"
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: dialog.albumShare && dialog.isOwner && dialog.selectedUserIds.length > 0
                //% "Add selected users"
                text: qsTrId("sharePage.addSelected")
                enabled: dialog.selectedUserIds.length > 0
                onClicked: immichApi.addUsersToAlbum(dialog.albumId, dialog.selectedUserIds, dialog.selectedRole)
            }

            SectionHeader {
                //% "Album settings"
                text: qsTrId("sharePage.albumSettings")
                visible: dialog.albumShare && dialog.isOwner
            }

            TextSwitch {
                id: activitySwitch
                visible: dialog.albumShare && dialog.isOwner
                //% "Comments and likes"
                text: qsTrId("sharePage.commentsAndLikes")
                //% "Allow comments and likes on this album"
                description: qsTrId("sharePage.commentsAndLikesInfo")
                checked: false
                onCheckedChanged: {
                    dialog.albumActivityEnabled = checked
                    if (!dialog.suppressAlbumActivitySave) {
                        dialog.saveAlbumSettings()
                    }
                }
            }

            SectionHeader {
                //% "Share link"
                text: qsTrId("sharePage.publicShareLinkSection")
                visible: dialog.albumShare
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: dialog.albumShare
                //% "These settings apply only to the generated public share link."
                text: qsTrId("sharePage.publicShareLink")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                wrapMode: Text.WordWrap
            }

            TextArea {
                id: descriptionField
                width: parent.width
                //% "Description"
                label: qsTrId("sharePage.description")
                placeholderText: label
            }

            PasswordField {
                id: passwordField
                width: parent.width
                //% "Password (optional)"
                label: qsTrId("sharePage.password")
                //% "Enter password to protect share"
                placeholderText: qsTrId("sharePage.passwordPlaceholder")

                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }

            TextField {
                id: slugField
                width: parent.width
                //% "Custom share URL"
                label: qsTrId("sharePage.customShareUrl")
                //% "Optional custom URL slug"
                placeholderText: qsTrId("sharePage.customShareUrlPlaceholder")
                color: slugField.acceptableInput ? Theme.primaryColor : Theme.errorColor
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

                validator: RegExpValidator {
                    regExp: /^(?:[A-Za-z0-9._~!$&'()*+,;=:@\-\s]|%[0-9A-Fa-f]{2})*$/
                }

                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: focus = false
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: slugField.text !== "" && slugField.acceptableInput
                text: immichApi.serverUrl() + "/s/" + slugField.text
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.WrapAnywhere
            }

            Rectangle {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: errorLabel.height + Theme.paddingMedium * 2
                radius: Theme.paddingSmall
                color: Theme.rgba(Theme.errorColor, 0.2)
                visible: !slugField.acceptableInput

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.paddingMedium
                    width: parent.width - Theme.paddingMedium * 2

                    Icon {
                        source: "image://theme/icon-s-warning"
                        color: Theme.errorColor
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Label {
                        id: errorLabel
                        width: parent.width - parent.spacing - Theme.iconSizeSmall
                        wrapMode: Text.WordWrap
                        color: Theme.errorColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        //% "Please enter a valid custom share URL"
                        text: qsTrId("sharePage.customShareUrlError")
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            ComboBox {
                id: expirationCombo
                //% "Expiration"
                label: qsTrId("sharePage.expiration")
                currentIndex: 0

                // Duration values in milliseconds (0 = never)
                property var durations: [0, 30*60*1000, 60*60*1000, 6*60*60*1000, 24*60*60*1000, 7*24*60*60*1000, 30*24*60*60*1000, 90*24*60*60*1000, 365*24*60*60*1000]

                function getExpiresAt() {
                    var ms = durations[currentIndex]
                    if (ms === 0) return ""
                    return new Date(Date.now() + ms).toISOString()
                }

                menu: ContextMenu {
                    //% "Never"
                    MenuItem { text: qsTrId("sharePage.expirationNever") }
                    //% "30 minutes"
                    MenuItem { text: qsTrId("sharePage.expiration30Min") }
                    //% "1 hour"
                    MenuItem { text: qsTrId("sharePage.expiration1Hour") }
                    //% "6 hours"
                    MenuItem { text: qsTrId("sharePage.expiration6Hours") }
                    //% "1 day"
                    MenuItem { text: qsTrId("sharePage.expiration1Day") }
                    //% "7 days"
                    MenuItem { text: qsTrId("sharePage.expiration7Days") }
                    //% "30 days"
                    MenuItem { text: qsTrId("sharePage.expiration30Days") }
                    //% "3 months"
                    MenuItem { text: qsTrId("sharePage.expiration3Months") }
                    //% "1 year"
                    MenuItem { text: qsTrId("sharePage.expiration1Year") }
                }
            }

            TextSwitch {
                id: showMetadataSwitch
                //% "Show metadata"
                text: qsTrId("sharePage.showMetadata")
                //% "Recipients can view metadata for shared assets"
                description: qsTrId("sharePage.showMetadataDescription")
                checked: true

                onCheckedChanged: {
                    if (!checked) {
                        allowDownloadSwitch.checked = false
                    }
                }
            }

            TextSwitch {
                id: allowDownloadSwitch
                //% "Allow download"
                text: qsTrId("sharePage.allowDownload")
                //% "Recipients can download assets/albums from this share"
                description: qsTrId("sharePage.allowDownloadDescription")
                checked: true
                enabled: showMetadataSwitch.checked
            }

            TextSwitch {
                id: allowUploadSwitch
                //% "Allow upload"
                text: qsTrId("sharePage.allowUpload")
                //% "Recipients can upload assets/albums to this share"
                description: qsTrId("sharePage.allowUploadDescription")
                checked: false
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: shareType === "INDIVIDUAL" ? (assetIds.length === 1
                    //% "Sharing asset"
                    ? qsTrId("sharePage.sharingAsset")
                    //% "Sharing %1 assets"
                    : qsTrId("sharePage.sharingAssets").arg(assetIds.length))
                    //% "Sharing album"
                    : qsTrId("sharePage.sharingAlbum")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                wrapMode: Text.WordWrap
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                //% "Create Share link"
                text: qsTrId("sharePage.createShareLinkButton")
                enabled: (assetIds.length > 0 || albumId) && slugField.acceptableInput
                onClicked: {
                    var ids = shareType === "INDIVIDUAL" ? assetIds : albumId
                    immichApi.createSharedLink(shareType, ids, passwordField.text, expirationCombo.getExpiresAt(), allowDownloadSwitch.checked, allowUploadSwitch.checked, showMetadataSwitch.checked, descriptionField.text, slugField.text)
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }
    }

    RemorsePopup {
        id: remorseItem
    }

    NotificationBanner {
        id: notification
    }

    Connections {
        target: immichApi
        onSharedLinkCreated: {
            var sharePath = isSlug ? "/s/" : "/share/"
            var shareUrl = immichApi.serverUrl() + sharePath + shareKey
            // Clear selection after successful share creation
            if (shareType === "INDIVIDUAL") {
                timelineModel.clearSelection()
            }
            pageStack.replace(Qt.resolvedUrl("ShareResultPage.qml"), {
                shareUrl: shareUrl
            })
        }
        onUsersReceived: {
            if (!dialog.albumShare || !dialog.isOwner) {
                return
            }
            var all = []
            for (var i = 0; i < users.length; i++) {
                all.push(users[i])
            }
            dialog.allUsers = all
            dialog.usersLoaded = true
            dialog.rebuildAvailableModel()
        }
        onUsersAddedToAlbum: {
            if (albumId === dialog.albumId) {
                dialog.selectedUserIds = []
                immichApi.fetchAlbumDetails(dialog.albumId)
            }
        }
        onAlbumUserRoleUpdated: {
            if (albumId === dialog.albumId) {
                immichApi.fetchAlbumDetails(dialog.albumId)
            }
        }
        onAlbumUserRemoved: {
            if (albumId === dialog.albumId) {
                if (!dialog.isOwner) {
                    pageStack.pop()
                } else {
                    immichApi.fetchAlbumDetails(dialog.albumId)
                }
            }
        }
        onAlbumDetailsReceived: {
            if (dialog.albumShare && details && details.id === dialog.albumId) {
                dialog.albumInfo = details
                if (dialog.isOwner && !dialog.usersLoaded) {
                    immichApi.fetchUsers()
                }
            }
        }
        onAlbumUpdated: {
            if (albumId === dialog.albumId && dialog.albumInfo) {
                var updated = dialog.albumInfo
                updated.albumName = albumName
                updated.description = description
                updated.isActivityEnabled = isActivityEnabled
                updated.albumThumbnailAssetId = albumThumbnailAssetId
                dialog.suppressAlbumActivitySave = true
                dialog.albumInfo = updated
                dialog.albumActivityEnabled = isActivityEnabled
                if (activitySwitch) {
                    activitySwitch.checked = isActivityEnabled
                }
                dialog.suppressAlbumActivitySave = false
            }
        }
        onErrorOccurred: {
            notification.showError(error)
        }
    }

    Component.onCompleted: {
        if (dialog.albumShare && dialog.albumId) {
            immichApi.fetchAlbumDetails(dialog.albumId)
        }
    }
}
