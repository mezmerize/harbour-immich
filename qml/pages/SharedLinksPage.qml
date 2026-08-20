import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../components/SharedLinksHelper.js" as SharedLinksHelper

Page {
    id: page

    property var sharedLinks: []
    property bool loading: true

    function refresh() {
        loading = true
        immichApi.fetchSharedLinks()
    }

    function getLinkDescription(link) {
        //% "Individual share"
        return SharedLinksHelper.shareTitle(link, qsTrId("sharedLinksPage.individualShare"))
    }

    function getLinkThumbnailId(link) {
        if (link.album && link.album.albumThumbnailAssetId) {
            return link.album.albumThumbnailAssetId
        }
        if (link.assets && link.assets.length > 0) {
            return link.assets[0].id
        }
        return ""
    }

    function copyLinkToClipboard(link) {
        var shareUrl = immichApi.serverUrl()
        if (link.slug && link.slug !== "") {
            shareUrl += "/s/" + link.slug
        } else {
            shareUrl += "/share/" + link.key
        }
        Clipboard.text = shareUrl
        //% "Link copied to clipboard"
        notification.show(qsTrId("notification.linkCopied"))
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: sharedLinks.length

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }
        }

        header: Column {
            width: listView.width

            PageHeader {
                //% "Shared Links"
                title: qsTrId("sharedLinksPage.sharedLinks")
            }
        }

        delegate: ListItem {
            id: listItem
            contentHeight: Math.max(thumbnailItem.height, infoColumn.height) + 2 * Theme.paddingMedium

            property var link: page.sharedLinks[index]

            onClicked: {
                if (link.type === "ALBUM") {
                    pageStack.push(Qt.resolvedUrl("AlbumShareDetailPage.qml"), {
                        linkId: link.id
                    })
                } else {
                    pageStack.push(Qt.resolvedUrl("IndividualShareDetailPage.qml"), {
                        linkId: link.id
                    })
                }
            }

            Row {
                anchors.fill: parent
                anchors.margins: Theme.paddingMedium
                spacing: Theme.paddingMedium

                Item {
                    id: thumbnailItem
                    width: Theme.itemSizeLarge
                    height: width

                    Image {
                        id: thumbnail
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: {
                            var tid = page.getLinkThumbnailId(link)
                            return tid ? "image://immich/thumbnail/" + tid : ""
                        }
                        asynchronous: true

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                            visible: thumbnail.status !== Image.Ready
                        }

                        Image {
                            anchors.centerIn: parent
                            source: "image://theme/icon-m-link"
                            visible: thumbnail.status !== Image.Ready
                        }
                    }
                }

                Column {
                    id: infoColumn
                    width: parent.width - thumbnailItem.width - 3 * Theme.paddingMedium - actionsRow.width
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall / 2

                    Label {
                        width: parent.width
                        text: page.getLinkDescription(link)
                        color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        width: parent.width
                        text: SharedLinksHelper.shareExpiration(
                            link.expiresAt,
                            //% "Expired"
                            qsTrId("sharedLinksPage.expired"),
                            //% "Expires: %1"
                            qsTrId("sharedLinksPage.expires"),
                            //% "No expiration"
                            qsTrId("sharedLinksPage.noExpiry"))
                        color: {
                            if (link.expiresAt && new Date(link.expiresAt) < new Date()) {
                                return Theme.errorColor
                            }
                            return listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        }
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }

                    // Tags row
                    Flow {
                        width: parent.width
                        spacing: Theme.paddingSmall

                        Rectangle {
                            width: metadataLabel.width + Theme.paddingSmall * 2
                            height: metadataLabel.height + Theme.paddingSmall
                            radius: Theme.paddingSmall / 2
                            color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                            visible: link.showMetadata

                            Label {
                                id: metadataLabel
                                anchors.centerIn: parent
                                //% "Metadata"
                                text: qsTrId("sharedLinksPage.metadata")
                                font.pixelSize: Theme.fontSizeTiny
                                color: Theme.highlightColor
                            }
                        }

                        Rectangle {
                            width: uploadLabel.width + Theme.paddingSmall * 2
                            height: uploadLabel.height + Theme.paddingSmall
                            radius: Theme.paddingSmall / 2
                            color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                            visible: link.allowUpload

                            Label {
                                id: uploadLabel
                                anchors.centerIn: parent
                                //% "Upload"
                                text: qsTrId("sharedLinksPage.upload")
                                font.pixelSize: Theme.fontSizeTiny
                                color: Theme.highlightColor
                            }
                        }

                        Rectangle {
                            width: downloadLabel.width + Theme.paddingSmall * 2
                            height: downloadLabel.height + Theme.paddingSmall
                            radius: Theme.paddingSmall / 2
                            color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                            visible: link.allowDownload

                            Label {
                                id: downloadLabel
                                anchors.centerIn: parent
                                //% "Download"
                                text: qsTrId("sharedLinksPage.download")
                                font.pixelSize: Theme.fontSizeTiny
                                color: Theme.highlightColor
                            }
                        }

                        Rectangle {
                            width: passwordLabel.width + Theme.paddingSmall * 2
                            height: passwordLabel.height + Theme.paddingSmall
                            radius: Theme.paddingSmall / 2
                            color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                            visible: link.password && link.password !== ""

                            Label {
                                id: passwordLabel
                                anchors.centerIn: parent
                                //% "Password"
                                text: qsTrId("sharedLinksPage.password")
                                font.pixelSize: Theme.fontSizeTiny
                                color: Theme.highlightColor
                            }
                        }
                    }
                }

                Row {
                    id: actionsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    IconButton {
                        icon.source: "image://theme/icon-m-clipboard"
                        icon.sourceSize.width: Theme.iconSizeSmallPlus
                        icon.sourceSize.height: Theme.iconSizeSmallPlus
                        width: Theme.itemSizeSmall
                        height: Theme.itemSizeSmall
                        onClicked: page.copyLinkToClipboard(link)
                    }

                    IconButton {
                        icon.source: "image://theme/icon-m-edit"
                        icon.sourceSize.width: Theme.iconSizeSmallPlus
                        icon.sourceSize.height: Theme.iconSizeSmallPlus
                        width: Theme.itemSizeSmall
                        height: Theme.itemSizeSmall
                        onClicked: {
                            pageStack.push(Qt.resolvedUrl("../components/EditSharedLinkDialog.qml"), {
                                linkData: link
                            })
                        }
                    }

                    IconButton {
                        icon.source: "image://theme/icon-m-delete"
                        icon.sourceSize.width: Theme.iconSizeSmallPlus
                        icon.sourceSize.height: Theme.iconSizeSmallPlus
                        width: Theme.itemSizeSmall
                        height: Theme.itemSizeSmall
                        onClicked: {
                            //% "Deleting shared link"
                            listItem.remorseAction(qsTrId("notification.deletingLink"), function() {
                                immichApi.deleteSharedLink(link.id)
                            })
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    // Loading
    LoadingIndicator {
        anchors.fill: listView
        loading: page.loading && sharedLinks.length === 0
        //% "Loading shared links..."
        message: qsTrId("sharedLinksPage.loading")
    }

    EmptyState {
        anchors.fill: listView
        visible: !page.loading && sharedLinks.length === 0
        iconSource: "image://theme/icon-m-link"
        //% "No shared links"
        message: qsTrId("sharedLinksPage.noLinks")
        //% "Create shared links from the share action on assets or albums"
        hint: qsTrId("sharedLinksPage.noLinksHint")
    }

    NotificationBanner {
        id: notification
        anchors.bottom: parent.bottom
    }

    Component.onCompleted: page.refresh()

    Connections {
        target: immichApi
        onSharedLinksReceived: {
            var linksArray = []
            for (var i = 0; i < links.length; i++) {
                linksArray.push(links[i])
            }
            page.sharedLinks = linksArray
            page.loading = false
        }
        onSharedLinkDeleted: {
            //% "Shared link deleted"
            notification.show(qsTrId("notification.linkDeleted"))
            page.refresh()
        }
        onSharedLinkUpdated: {
            //% "Shared link updated"
            notification.show(qsTrId("notification.linkUpdated"))
            page.refresh()
        }
    }
}
