import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../components/FilterHelper.js" as FilterHelper

Page {
    id: page

    property var placesModel: []
    property bool loading: true
    property string filterText: ""

    property var filteredModel: FilterHelper.filterByField(placesModel, filterText, "city")

    signal requestViewportCheck()

    function refresh() {
        loading = true
        immichApi.fetchCities()
    }

    Timer {
        id: viewportCheckTimer
        interval: 50
        onTriggered: page.requestViewportCheck()
    }

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                //% "Refresh"
                text: qsTrId("pullDownMenu.refresh")
                onClicked: page.refresh()
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                //% "Places"
                title: qsTrId("placesPage.places")
            }

            SearchField {
                width: parent.width
                visible: placesModel.length > 5
                //% "Filter places..."
                placeholderText: qsTrId("placesPage.filter")

                onTextChanged: {
                    page.filterText = text.toLowerCase()
                    viewportCheckTimer.restart()
                }

                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            Repeater {
                model: filteredModel

                ListItem {
                    id: listItem
                    width: column.width
                    contentHeight: Theme.itemSizeLarge

                    property var place: modelData
                    property string thumbnailId: place ? (place.thumbnailId || "") : ""
                    property string thumbhash: place ? (place.thumbhash || "") : ""
                    property bool thumbnailTriggered: false

                    function checkViewport() {
                        if (thumbnailTriggered || !visible) return
                        var mapped = mapToItem(flickable.contentItem, 0, 0)
                        var itemY = mapped.y
                        if (itemY + height > flickable.contentY - height && itemY < flickable.contentY + flickable.height + height) {
                            thumbnailTriggered = true
                        }
                    }

                    Connections {
                        target: flickable
                        onContentYChanged: listItem.checkViewport()
                    }

                    Connections {
                        target: page
                        onRequestViewportCheck: listItem.checkViewport()
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: Theme.paddingMedium
                        spacing: Theme.paddingMedium

                        Item {
                            width: Theme.itemSizeLarge
                            height: width

                            Image {
                                id: placeThumbhash
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                source: listItem.thumbhash ? "image://thumbhash/" + listItem.thumbhash : ""
                                visible: placeThumbnail.status !== Image.Ready
                                asynchronous: false
                                cache: true
                            }

                            Image {
                                id: placeThumbnail
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                source: listItem.thumbnailTriggered && listItem.thumbnailId ? "image://immich/thumbnail/" + listItem.thumbnailId : ""
                                asynchronous: true
                                cache: true
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                                visible: placeThumbnail.status !== Image.Ready && !listItem.thumbhash
                            }

                            Image {
                                anchors.centerIn: parent
                                source: "image://theme/icon-m-location"
                                visible: placeThumbnail.status !== Image.Ready && !listItem.thumbhash
                            }
                        }

                        Column {
                            width: parent.width - Theme.itemSizeLarge - 3 * Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.paddingSmall

                            Label {
                                width: parent.width
                                text: place ? (place.city || "") : ""
                                color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                font.pixelSize: Theme.fontSizeMedium
                                truncationMode: TruncationMode.Fade
                            }

                            Label {
                                width: parent.width
                                text: {
                                    if (!place) return ""
                                    var parts = []
                                    if (place.state) parts.push(place.state)
                                    if (place.country) parts.push(place.country)
                                    return parts.join(", ")
                                }
                                color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeSmall
                                truncationMode: TruncationMode.Fade
                                visible: text !== ""
                            }
                        }
                    }

                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("PlaceDetailPage.qml"), {
                            cityName: place.city || "",
                            stateName: place.state || "",
                            countryName: place.country || ""
                        })
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }

    // Loading
    LoadingIndicator {
        anchors.fill: flickable
        loading: page.loading && placesModel.length === 0
        //% "Loading places..."
        message: qsTrId("placesPage.loading")
    }

    // Empty state
    EmptyState {
        anchors.fill: flickable
        visible: !page.loading && placesModel.length === 0
        iconSource: "image://theme/icon-m-location"
        //% "No places found"
        message: qsTrId("placesPage.noPlaces")
    }

    Component.onCompleted: page.refresh()

    Connections {
        target: immichApi
        onCitiesReceived: {
            var result = []
            for (var i = 0; i < cities.length; i++) {
                var item = cities[i]
                var exifInfo = item["exifInfo"] || {}
                if (exifInfo["city"] === undefined || exifInfo["city"] === "") continue
                result.push({
                    city: exifInfo["city"] || "",
                    state: exifInfo["state"] || "",
                    country: exifInfo["country"] || "",
                    thumbnailId: item["id"] || "",
                    thumbhash: item["thumbhash"] || ""
                })
            }
            result.sort(function(a, b) { return (a.city || "").localeCompare(b.city || "") })
            page.placesModel = result
            page.loading = false
            viewportCheckTimer.restart()
        }
    }
}
