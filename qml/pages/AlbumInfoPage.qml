import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property string albumId
    property var albumInfo
    property var albumAssetIds: []
    property var albumOwner: {
        if (albumInfo && albumInfo.albumUsers) {
            for (var i = 0; i < albumInfo.albumUsers.length; i++) {
                if (albumInfo.albumUsers[i].role === "owner") return albumInfo.albumUsers[i].user
            }
        }
        return null
    }
    property var sharedUsers: {
        var res = []
        if (albumInfo && albumInfo.albumUsers) {
            for (var i = 0; i < albumInfo.albumUsers.length; i++) {
                if (albumInfo.albumUsers[i].role !== "owner") res.push(albumInfo.albumUsers[i])
            }
        }
        return res
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                //% "Edit album"
                text: qsTrId("pullDownMenu.editAlbum")
                visible: !!(albumOwner && albumOwner.id === authManager.userId)
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("EditAlbumDialog.qml"), {
                        albumId: page.albumId,
                        albumName: !!albumInfo && albumInfo.albumName ? albumInfo.albumName : "",
                        albumDescription: !!albumInfo && albumInfo.description ? albumInfo.description : "",
                        isActivityEnabled: !!albumInfo && albumInfo.isActivityEnabled !== undefined ? albumInfo.isActivityEnabled : true,
                        albumThumbnailAssetId: !!albumInfo && albumInfo.albumThumbnailAssetId ? albumInfo.albumThumbnailAssetId : ""
                    })
                }
            }
        }

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingMedium

            PageHeader {
                //% "Album Information"
                title: qsTrId("albumInfoPage.albumInformation")
            }

            DetailItem {
                //% "Album name"
                label: qsTrId("albumInfoPage.albumName")
                value: !!albumInfo ? albumInfo.albumName : ""
            }

            DetailItem {
                //% "Description"
                label: qsTrId("albumInfoPage.description")
                //% "No description"
                value: !!(albumInfo && albumInfo.description) ? albumInfo.description : qsTrId("albumInfoPage.noDescription")
            }

            DetailItem {
                //% "Created"
                label: qsTrId("albumInfoPage.created")
                value: !!albumInfo ? Qt.formatDateTime(new Date(albumInfo.createdAt), "dd.MM.yyyy hh:mm") : ""
            }

            DetailItem {
                //% "Updated"
                label: qsTrId("albumInfoPage.updated")
                value: !!albumInfo ? Qt.formatDateTime(new Date(albumInfo.updatedAt), "dd.MM.yyyy hh:mm") : ""
            }

            DetailItem {
                //% "Asset count"
                label: qsTrId("albumInfoPage.assetCount")
                value: !!albumInfo ? albumInfo.assetCount : ""
            }

            SectionHeader {
                //% "Owner"
                text: qsTrId("assetInfoPage.owner")
                visible: !!albumOwner
            }

            DetailItem {
                visible: !!(albumOwner && albumOwner.name)
                //% "Name"
                label: qsTrId("albumInfoPage.ownerName")
                value: !!(albumOwner && albumOwner.name) ? albumOwner.name : ""
            }

            DetailItem {
                visible: !!(albumOwner && albumOwner.email)
                //% "Email"
                label: qsTrId("albumInfoPage.ownerEmail")
                value: !!(albumOwner && albumOwner.email) ? albumOwner.email : ""
            }

            SectionHeader {
                //% "Shared with"
                text: qsTrId("albumInfoPage.sharedWith")
                visible: sharedUsers.length > 0
            }

            Repeater {
                model: sharedUsers

                DetailItem {
                    label: modelData.user ? modelData.user.name : ""
                    value: modelData.role ? (modelData.role === "editor"
                        //% "Editor"
                        ? qsTrId("albumInfoPage.roleEditor")
                        //% "Viewer"
                        : qsTrId("albumInfoPage.roleViewer")) : ""
                }
            }

            SectionHeader {
                //% "Sharing"
                text: qsTrId("albumInfoPage.sharing")
                visible: !!(albumInfo && (albumInfo.shared || albumInfo.isActivityEnabled))
            }

            DetailItem {
                visible: !!(albumInfo && albumInfo.shared)
                //% "Shared"
                label: qsTrId("albumInfoPage.shared")
                value: !!(albumInfo && albumInfo.shared)
                    //% "Yes"
                    ? qsTrId("albumInfoPage.sharedYes")
                    //% "No"
                    : qsTrId("albumInfoPage.sharedNo")
            }

            DetailItem {
                //% "Comments and likes"
                label: qsTrId("albumInfoPage.commentsAndLikes")
                value: !!(albumInfo && albumInfo.isActivityEnabled)
                    //% "Enabled"
                    ? qsTrId("albumInfoPage.activityEnabled")
                    //% "Disabled"
                    : qsTrId("albumInfoPage.activityDisabled")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }

    Component.onCompleted: {
        if (albumId) {
            immichApi.fetchAlbumDetails(albumId)
        }
    }

    Connections {
        target: immichApi
        onAlbumDetailsReceived: {
            if (details && details.id === page.albumId) {
                albumInfo = details
            }
        }
        onAlbumUpdated: {
            if (albumId === page.albumId) {
                var updated = albumInfo
                updated.albumName = albumName
                updated.description = description
                updated.isActivityEnabled = isActivityEnabled
                updated.albumThumbnailAssetId = albumThumbnailAssetId
                albumInfo = updated
            }
        }
    }
}
