import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

Page {
 id: page
 objectName: "timelinePage"

 property int assetsPerRow: isPortrait ? settingsManager.assetsPerRow : (settingsManager.assetsPerRow * 2)
 property bool loadingMore: false
 property real cellSize: width / assetsPerRow
 property int bucketCount: timelineModel.bucketCount

 // Filter state
 property string activeFilter: "all"  // all, favorites
 property string sortOrder: "desc"    // desc, asc

 // Selection mode
 property bool selectionMode: timelineModel.selectedCount > 0

 // Album selector state
 property var pendingAlbumAssetIds: []

 function refresh() {
     timelineModel.clear()
     timelineModel.setLoading(true)
     var isFavorite = activeFilter === "favorites"
     timelineModel.setFavoriteFilter(isFavorite)
     immichApi.fetchTimelineBuckets(isFavorite, sortOrder)
 }

 function applyFilter() {
     timelineModel.clear()
     timelineModel.setLoading(true)
     var isFavorite = activeFilter === "favorites"
     timelineModel.setFavoriteFilter(isFavorite)
     immichApi.fetchTimelineBuckets(isFavorite, sortOrder)
 }

 SilicaFlickable {
     id: flickable
     anchors.top: parent.top
     anchors.left: parent.left
     anchors.right: parent.right
     anchors.bottom: selectionActionBar.visible ? selectionActionBar.top : parent.bottom
     contentHeight: contentColumn.height
     clip: true

     flickableDirection: Flickable.VerticalFlick
     pixelAligned: true

     PullDownMenu {
         MenuItem {
             //% "Settings"
             text: qsTrId("timelinePage.settings")
             onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
         }

         MenuItem {
             //% "Search"
             text: qsTrId("timelinePage.search")
             onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
         }

         MenuItem {
             //% "Albums"
             text: qsTrId("timelinePage.albums")
             onClicked: pageStack.push(Qt.resolvedUrl("AlbumsPage.qml"))
         }

         MenuItem {
             //% "Refresh"
             text: qsTrId("timelinePage.refresh")
             onClicked: page.refresh()
         }
     }

     // Track visible range to optimize rendering
     property real viewportTop: contentY
     property real viewportBottom: contentY + height
     property real loadBuffer: height * 1.5

     Column {
         id: contentColumn
         width: parent.width
         spacing: 0

         PageHeader {
             title: timelineModel.selectedCount > 0 ?
                    //% "%1 asset(s) selected"
                    qsTrId("timelinePage.assetsSelected").arg(timelineModel.selectedCount) :
                    //% "Timeline"
                    qsTrId("timelinePage.timeline")
         }

         // Memories / On This Day section
         MemoriesBar {
             id: memoriesBar
             width: parent.width
             visible: activeFilter === "all" && settingsManager.showMemoriesBar
         }

         // Quick filters row
         Item {
             id: filterBar
             width: parent.width
             height: Theme.itemSizeExtraSmall + Theme.paddingMedium

             Row {
                 id: filterRow
                 anchors.left: parent.left
                 anchors.right: parent.right
                 anchors.leftMargin: Theme.horizontalPageMargin
                 anchors.rightMargin: Theme.horizontalPageMargin
                 anchors.verticalCenter: parent.verticalCenter
                 spacing: Theme.paddingSmall

                 Repeater {
                     model: [
                         //% "All"
                         { id: "all", label: qsTrId("timelinePage.all"), icon: "image://theme/icon-m-image" },
                         //% "Favorites"
                         { id: "favorites", label: qsTrId("timelinePage.favorites"), icon: "image://theme/icon-m-favorite" }
                     ]

                     BackgroundItem {
                         width: (filterRow.width - Theme.paddingSmall - sortButton.width - Theme.paddingMedium) / 2
                         height: Theme.itemSizeExtraSmall
                         highlighted: page.activeFilter === modelData.id


                         Rectangle {
                             anchors.fill: parent
                             radius: Theme.paddingSmall
                             color: page.activeFilter === modelData.id ?
                                    Theme.rgba(Theme.highlightBackgroundColor, 0.4) :
                                    Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                             border.width: page.activeFilter === modelData.id ? 1 : 0
                             border.color: Theme.highlightColor
                         }

                         Row {
                             anchors.centerIn: parent
                             spacing: Theme.paddingSmall

                             Icon {
                                 source: modelData.icon
                                 width: Theme.iconSizeSmall
                                 height: Theme.iconSizeSmall
                                 anchors.verticalCenter: parent.verticalCenter
                                 color: page.activeFilter === modelData.id ? Theme.highlightColor : Theme.primaryColor
                             }

                             Label {
                                 text: modelData.label
                                 font.pixelSize: Theme.fontSizeExtraSmall
                                 color: page.activeFilter === modelData.id ? Theme.highlightColor : Theme.primaryColor
                                 anchors.verticalCenter: parent.verticalCenter
                             }
                         }

                         onClicked: {
                             if (page.activeFilter !== modelData.id) {
                                 page.activeFilter = modelData.id
                                 page.applyFilter()
                             }
                         }
                     }
                 }

                 // Sort order button
                 BackgroundItem {
                     id: sortButton
                     width: Theme.itemSizeSmall
                     height: Theme.itemSizeExtraSmall

                     Rectangle {
                         anchors.fill: parent
                         radius: Theme.paddingSmall
                         color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                     }

                     Icon {
                         anchors.centerIn: parent
                         source: page.sortOrder === "desc" ? "image://theme/icon-m-down" : "image://theme/icon-m-up"
                         width: Theme.iconSizeSmall
                         height: Theme.iconSizeSmall
                     }

                     onClicked: {
                         page.sortOrder = page.sortOrder === "desc" ? "asc" : "desc"
                         page.applyFilter()
                     }
                 }
             }
         }

         Item {
             width: parent.width
             height: Theme.paddingSmall
         }

         // Loading indicator for initial load
         BusyIndicator {
             anchors.horizontalCenter: parent.horizontalCenter
             size: BusyIndicatorSize.Large
             running: timelineModel.loading && bucketCount === 0
             visible: running
         }

         Label {
             anchors.horizontalCenter: parent.horizontalCenter
             //% "Loading timeline..."
             text: qsTrId("timelinePage.loading")
             color: Theme.secondaryHighlightColor
             visible: timelineModel.loading && bucketCount === 0
         }

         Repeater {
             id: bucketsRepeater
             model: page.bucketCount

             Column {
                 id: bucketColumn
                 width: flickable.width
                 spacing: 0
                 visible: !assetsLoaded || (bucketSubGroups && bucketSubGroups.length > 0)
                 property int bucketIndex: index
                 property var bucketData: null
                 property var bucketSubGroups: null
                 property bool isFirstOfMonth: false
                 property bool dataLoaded: false
                 property bool assetsLoaded: false

                 // Visibility-based loading - only check after layout is complete
                 property real bucketTop: y
                 property real bucketBottom: y + height
                 property bool isNearViewport: false

                 function checkViewportVisibility() {
                     var nearTop = flickable.viewportTop - flickable.height
                     var nearBottom = flickable.viewportBottom + flickable.height
                     isNearViewport = (bucketBottom > nearTop) && (bucketTop < nearBottom)
                 }

                 onYChanged: checkViewportVisibility()

                 onIsNearViewportChanged: {
                     if (isNearViewport && !dataLoaded) {
                         loadBucketData()
                     }
                     if (isNearViewport && !assetsLoaded) {
                         // Delay asset loading to throttle requests during fast scrolling
                         loadDelayTimer.restart()
                     }
                 }

                 Timer {
                     id: loadDelayTimer
                     interval: 100
                     repeat: false
                     onTriggered: {
                         if (bucketColumn.isNearViewport && !bucketColumn.assetsLoaded) {
                             bucketColumn.requestAssets()
                         }
                     }
                 }

                 Component.onCompleted: {
                     // Only load first 3 buckets immediately, rest will load on scroll
                     if (bucketIndex < 3) {
                         loadBucketData()
                         requestAssets()
                     }
                 }

                 function loadBucketData() {
                     if (dataLoaded || !timelineModel) return
                     bucketData = timelineModel.getBucketAt(bucketIndex)
                     if (bucketIndex === 0) {
                         isFirstOfMonth = true
                     } else if (bucketData) {
                         var prevBucket = timelineModel.getBucketAt(bucketIndex - 1)
                         isFirstOfMonth = prevBucket ? prevBucket.monthYear !== bucketData.monthYear : false
                     }
                     dataLoaded = true
                 }

                 function requestAssets() {
                     if (!timelineModel || !bucketData) return
                     if (!timelineModel.isBucketLoaded(bucketIndex)) {
                         timelineModel.requestBucketLoad(bucketIndex)
                     } else {
                         loadAssets()
                     }
                 }

                 function loadAssets() {
                     bucketSubGroups = timelineModel.getBucketSubGroups(bucketIndex)
                     assetsLoaded = true
                 }

                 // Listen for bucket load completion
                 Connections {
                     target: timelineModel
                     onDataChanged: {
                         if (timelineModel.isBucketLoaded(bucketColumn.bucketIndex) && !bucketColumn.assetsLoaded) {
                             bucketColumn.loadAssets()
                         }
                     }
                 }

                 // Listen for scroll to check visibility (throttled)
                 Connections {
                     target: flickable
                     onContentYChanged: visibilityThrottleTimer.restart()
                 }

                 Timer {
                     id: visibilityThrottleTimer
                     interval: 16  // ~60fps
                     repeat: false
                     onTriggered: bucketColumn.checkViewportVisibility()
                 }

                 // Bucket header
                 Rectangle {
                     width: parent.width
                     height: Theme.itemSizeSmall
                     color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

                     Label {
                         anchors.left: parent.left
                         anchors.leftMargin: Theme.horizontalPageMargin
                         anchors.verticalCenter: parent.verticalCenter
                         text: bucketData ? bucketData.monthYear : ""
                         font.pixelSize: Theme.fontSizeLarge
                         font.bold: true
                         color: Theme.highlightColor
                         visible: isFirstOfMonth
                     }

                     // Asset count indicator when not loaded
                     Label {
                         anchors.left: parent.left
                         anchors.leftMargin: Theme.horizontalPageMargin
                         anchors.verticalCenter: parent.verticalCenter
                         //% "%1 item(s)"
                         text: bucketData ? qsTrId("timelinePage.items").arg(bucketData.count) : ""
                         font.pixelSize: Theme.fontSizeSmall
                         color: Theme.secondaryColor
                         visible: !isFirstOfMonth && !assetsLoaded
                     }
                 }

                 // Loading indicator for bucket assets
                 Item {
                     width: parent.width
                     height: !assetsLoaded && isNearViewport ? loadingPlaceholderHeight : 0
                     visible: !assetsLoaded && isNearViewport

                     // Use same height estimation as placeholder to prevent jumps
                     property real loadingPlaceholderHeight: {
                         if (!bucketData) return Theme.itemSizeLarge
                         var assetsPerRow = page.assetsPerRow
                         var rows = Math.ceil(bucketData.count / assetsPerRow)
                         var estimatedSubgroups = Math.min(Math.ceil(bucketData.count / 10), 15)
                         var subgroupHeaderHeight = estimatedSubgroups * Theme.itemSizeExtraSmall
                         return rows * page.cellSize + subgroupHeaderHeight
                     }

                     BusyIndicator {
                         anchors.centerIn: parent
                         size: BusyIndicatorSize.Small
                         running: parent.visible
                     }
                 }


                 // Placeholder for unloaded buckets (estimated height)
                 Item {
                     width: parent.width
                     height: !assetsLoaded && !isNearViewport ? estimatedHeight : 0
                     visible: !assetsLoaded && !isNearViewport

                     property real estimatedHeight: {
                         if (!bucketData) return 0
                         var assetsPerRow = page.assetsPerRow
                         var rows = Math.ceil(bucketData.count / assetsPerRow)
                         // Estimate subgroup count (assume ~3 days per month on average)
                         var estimatedSubgroups = Math.min(Math.ceil(bucketData.count / 10), 15)
                         var subgroupHeaderHeight = estimatedSubgroups * Theme.itemSizeExtraSmall
                         return rows * page.cellSize + subgroupHeaderHeight
                     }
                 }

                 // Sub-groups by date
                 Column {
                     width: parent.width
                     visible: assetsLoaded
                     spacing: 0

                     Repeater {
                         model: bucketColumn.assetsLoaded ? bucketSubGroups : null

                         Column {
                             width: parent.width
                             spacing: 0

                             property var subGroupData: modelData
                             property int subGroupIndex: index

                             // Sub-group date header
                             Rectangle {
                                 width: parent.width
                                 height: bucketSubGroups && bucketSubGroups.length > 0 ? Theme.itemSizeExtraSmall : 0
                                 visible: bucketSubGroups && bucketSubGroups.length > 0
                                 color: "transparent"

                                 property bool isSubGroupSelected: {
                                     if (!subGroupData || !subGroupData.assets || timelineModel.selectedCount === 0) return false
                                     for (var i = 0; i < subGroupData.assets.length; i++) {
                                         if (!timelineModel.isAssetSelected(subGroupData.assets[i].id)) {
                                             return false
                                         }
                                     }
                                     return true
                                 }

                                 Label {
                                     id: subGroupDateLabel
                                     anchors.left: parent.left
                                     anchors.leftMargin: Theme.horizontalPageMargin
                                     anchors.verticalCenter: parent.verticalCenter
                                     text: subGroupData ? subGroupData.displayDate : ""
                                     font.pixelSize: Theme.fontSizeSmall
                                     color: Theme.secondaryHighlightColor
                                 }

                                 IconButton {
                                     id: subGroupSelectButton
                                     anchors.right: parent.right
                                     anchors.rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                                     anchors.verticalCenter: parent.verticalCenter
                                     icon.source: parent.isSubGroupSelected ? "image://theme/icon-m-remove" : "image://theme/icon-m-add"
                                     icon.color: parent.isSubGroupSelected ? Theme.errorColor : Theme.primaryColor

                                     onClicked: {
                                         if (!subGroupData || !subGroupData.assets) return
                                         var assets = subGroupData.assets
                                         if (parent.isSubGroupSelected) {
                                             // Deselect all assets in this subgroup
                                             for (var i = 0; i < assets.length; i++) {
                                                 if (timelineModel.isAssetSelected(assets[i].id)) {
                                                     timelineModel.toggleSelection(bucketColumn.bucketIndex, assets[i].assetIndex)
                                                 }
                                             }
                                         } else {
                                             // Select all assets in this subgroup
                                             for (var i = 0; i < assets.length; i++) {
                                                 if (!timelineModel.isAssetSelected(assets[i].id)) {
                                                     timelineModel.toggleSelection(bucketColumn.bucketIndex, assets[i].assetIndex)
                                                 }
                                             }
                                         }
                                     }
                                 }
                             }

                             // Assets in this sub-group
                             Flow {
                                 width: parent.width

                                 Repeater {
                                     model: subGroupData ? subGroupData.assets : null

                                     Loader {
                                         id: assetLoader
                                         width: page.cellSize
                                         height: page.cellSize

                                         property bool shouldCreate: bucketColumn.isNearViewport
                                         active: shouldCreate

                                         sourceComponent: AssetGridItem {
                                             id: gridItem
                                             width: page.cellSize
                                             height: page.cellSize
                                             assetId: modelData.id
                                             isFavorite: modelData.isFavorite
                                             isSelected: timelineModel.selectedCount >= 0 && timelineModel.isAssetSelected(modelData.id)
                                             isVideo: modelData.isVideo
                                             assetIndex: modelData.assetIndex
                                             thumbhash: modelData.thumbhash || ""

                                             shouldLoad: bucketColumn.isNearViewport

                                             onClicked: {
                                                 if (timelineModel.selectedCount > 0) {
                                                     timelineModel.toggleSelection(bucketColumn.bucketIndex, modelData.assetIndex)
                                                 } else {
                                                     // Navigate to asset detail
                                                     var assetIndex = timelineModel.getAssetIndexById(modelData.id)
                                                     pageStack.push(Qt.resolvedUrl("AssetDetailPage.qml"), {
                                                         "assetId": modelData.id,
                                                         "isFavorite": modelData.isFavorite,
                                                         "isVideo": modelData.isVideo,
                                                         "thumbhash": modelData.thumbhash || "",
                                                         "currentIndex": assetIndex
                                                     })
                                                 }
                                             }

                                             onPressAndHold: {
                                                 timelineModel.toggleSelection(bucketColumn.bucketIndex, modelData.assetIndex)
                                             }

                                             onAddToSelection: {
                                                 timelineModel.toggleSelection(bucketColumn.bucketIndex, modelData.assetIndex)
                                             }
                                         }
                                     }
                                 }
                             }
                         }
                     }
                 }
             }
         }

         // Empty state
         Column {
             width: parent.width
             spacing: Theme.paddingLarge
             visible: !timelineModel.loading && bucketCount === 0

             Item {
                 width: parent.width
                 height: Theme.paddingLarge * 2
             }

             Icon {
                 anchors.horizontalCenter: parent.horizontalCenter
                 source: page.activeFilter === "favorites" ? "image://theme/icon-m-favorite" : "image://theme/icon-m-image"
                 color: Theme.highlightColor
             }

             Label {
                 x: Theme.horizontalPageMargin
                 width: parent.width - 2 * Theme.horizontalPageMargin
                 text: page.activeFilter === "favorites"
                       //% "No favorites yet"
                       ? qsTrId("timelinePage.noFavoritesLabel")
                       //% "No assets yet"
                       : qsTrId("timelinePage.noAssetsLabel")
                 font.pixelSize: Theme.fontSizeLarge
                 color: Theme.highlightColor
                 wrapMode: Text.WordWrap
                 horizontalAlignment: Text.AlignHCenter
             }

             Label {
                 x: Theme.horizontalPageMargin
                 width: parent.width - 2 * Theme.horizontalPageMargin
                 text: page.activeFilter === "favorites"
                       //% "Long-press an asset and add it to favorites to see it here"
                       ? qsTrId("timelinePage.noFavoritesInfo")
                       //% "Upload or import assets in Immich to start building your timeline"
                       : qsTrId("timelinePage.noAssetsInfo")
                 font.pixelSize: Theme.fontSizeSmall
                 color: Theme.secondaryHighlightColor
                 wrapMode: Text.WordWrap
                 horizontalAlignment: Text.AlignHCenter
             }
         }

         Item {
             width: parent.width
             height: Theme.paddingLarge
         }
     }

     VerticalScrollDecorator {}
 }


 // Selection action bar
 SelectionActionBar {
     id: selectionActionBar
     anchors.left: parent.left
     anchors.right: parent.right
     anchors.bottom: parent.bottom

     visible: timelineModel.selectedCount > 0
     selectedCount: timelineModel.selectedCount
     allAreFavorites: timelineModel.selectedCount > 0 && timelineModel.areAllSelectedFavorites()
     hasAnyFavorites: timelineModel.selectedCount > 0 && timelineModel.areAnySelectedFavorites()

     onAddToFavorites: {
         var selectedIds = timelineModel.getSelectedAssetIds()
         immichApi.toggleFavorite(selectedIds, true)
     }
     onRemoveFromFavorites: {
         var selectedIds = timelineModel.getSelectedAssetIds()
         immichApi.toggleFavorite(selectedIds, false)
     }
     onShare: {
         var selectedIds = timelineModel.getSelectedAssetIds()
         pageStack.push(Qt.resolvedUrl("SharePage.qml"), {
             assetIds: selectedIds,
             shareType: "INDIVIDUAL"
         })
     }
     onAddToAlbum: {
         page.pendingAlbumAssetIds = timelineModel.getSelectedAssetIds()
         var dialog = pageStack.push(albumSelectorDialog)
         dialog.accepted.connect(function() {
             if (dialog.createNew) {
                 // Album will be created, then we add assets in albumCreated handler
             } else if (dialog.selectedAlbumId !== "") {
                 immichApi.addAssetsToAlbum(dialog.selectedAlbumId, page.pendingAlbumAssetIds)
                 timelineModel.clearSelection()
             }
         })
     }
     onClearSelection: timelineModel.clearSelection()
     onDownload: {
         var selectedIds = timelineModel.getSelectedAssetIds()
         for (var i = 0; i < selectedIds.length; i++) {
             immichApi.downloadAsset(selectedIds[i], "asset_" + selectedIds[i])
         }
         timelineModel.clearSelection()
         //% "Downloading %1 asset(s)..."
         errorNotification.show(qsTrId("timelinePage.downloading").arg(selectedIds.length))
     }
     onDeleteSelected: {
         var selectedIds = timelineModel.getSelectedAssetIds()
         //% "Deleting %1 asset(s)"
         deleteRemorse.execute(qsTrId("timelinePage.deleting").arg(selectedIds.length), function() {
             immichApi.deleteAssets(selectedIds)
             timelineModel.clearSelection()
         })
     }
 }

 ScrollToTopButton {
     targetFlickable: flickable
     actionBarHeight: selectionActionBar.visible ? selectionActionBar.contentHeight : 0
     forceHidden: selectionActionBar.menuOpen
 }

 RemorsePopup {
     id: deleteRemorse
 }

 Component {
     id: albumSelectorDialog
     Dialog {
         id: albumDialog
         property string selectedAlbumId: ""
         property bool createNew: false
         property string newAlbumName: ""
         property string activeAlbumFilter: "all"

         function applyAlbumFilter() {
             if (activeAlbumFilter === "shared") {
                 immichApi.fetchAlbums("true")
             } else if (activeAlbumFilter === "mine") {
                 immichApi.fetchAlbums("false")
             } else {
                 immichApi.fetchAlbums()
             }
         }

         canAccept: selectedAlbumId !== "" || (createNew && newAlbumName.length > 0)

         onAccepted: {
             if (createNew && newAlbumName.length > 0) {
                 immichApi.createAlbum(newAlbumName, "")
             }
         }

         SilicaFlickable {
             anchors.fill: parent
             contentHeight: albumColumn.height

             Column {
                 id: albumColumn
                 width: parent.width

                 DialogHeader {
                     //% "Select or create album"
                     title: qsTrId("timelinePage.selectOrCreate")
                 }

                 // Create new album section
                 SectionHeader {
                     //% "Create new album"
                     text: qsTrId("timelinePage.createNew")
                 }

                 TextField {
                     id: newAlbumField
                     width: parent.width
                     //% "Album name"
                     placeholderText: qsTrId("timelinePage.albumName")
                     //% "New album name"
                     label: qsTrId("timelinePage.newAlbumName")
                     onTextChanged: {
                         albumDialog.newAlbumName = text
                         if (text.length > 0) {
                             albumDialog.createNew = true
                             albumDialog.selectedAlbumId = ""
                         } else {
                             albumDialog.createNew = false
                         }
                     }
                     EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                     EnterKey.onClicked: {
                         if (text.length > 0) {
                             albumDialog.accept()
                         }
                     }
                 }

                 // Existing albums section
                 SectionHeader {
                     //% "Existing albums"
                     text: qsTrId("timelinePage.existingAlbums")
                     visible: albumModel.rowCount() > 0
                 }

                 // Album type filter row
                 Item {
                     width: parent.width
                     height: Theme.itemSizeExtraSmall + Theme.paddingMedium
                     visible: albumModel.rowCount() > 0

                     Row {
                         id: selectorFilterRow
                         anchors.left: parent.left
                         anchors.right: parent.right
                         anchors.leftMargin: Theme.horizontalPageMargin
                         anchors.rightMargin: Theme.horizontalPageMargin
                         anchors.verticalCenter: parent.verticalCenter
                         spacing: Theme.paddingSmall

                         Repeater {
                             model: [
                                 //% "All"
                                 { id: "all", label: qsTrId("timelinePage.filterAll"), icon: "image://theme/icon-m-folder" },
                                 //% "Shared with me"
                                 { id: "shared", label: qsTrId("timelinePage.filterSharedWithMe"), icon: "image://theme/icon-m-share" },
                                 //% "My albums"
                                 { id: "mine", label: qsTrId("timelinePage.filterMyAlbums"), icon: "image://theme/icon-m-person" }
                             ]

                             BackgroundItem {
                                 width: (selectorFilterRow.width - 2 * Theme.paddingSmall) / 3
                                 height: Theme.itemSizeExtraSmall
                                 highlighted: albumDialog.activeAlbumFilter === modelData.id

                                 Rectangle {
                                     anchors.fill: parent
                                     radius: Theme.paddingSmall
                                     color: albumDialog.activeAlbumFilter === modelData.id ?
                                            Theme.rgba(Theme.highlightBackgroundColor, 0.4) :
                                            Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                                     border.width: albumDialog.activeAlbumFilter === modelData.id ? 1 : 0
                                     border.color: Theme.highlightColor
                                 }

                                 Row {
                                     anchors.centerIn: parent
                                     spacing: Theme.paddingSmall

                                     Icon {
                                         source: modelData.icon
                                         width: Theme.iconSizeSmall
                                         height: Theme.iconSizeSmall
                                         anchors.verticalCenter: parent.verticalCenter
                                         color: albumDialog.activeAlbumFilter === modelData.id ? Theme.highlightColor : Theme.primaryColor
                                     }

                                     Label {
                                         text: modelData.label
                                         font.pixelSize: Theme.fontSizeExtraSmall
                                         color: albumDialog.activeAlbumFilter === modelData.id ? Theme.highlightColor : Theme.primaryColor
                                         anchors.verticalCenter: parent.verticalCenter
                                     }
                                 }

                                 onClicked: {
                                     if (albumDialog.activeAlbumFilter !== modelData.id) {
                                         albumDialog.activeAlbumFilter = modelData.id
                                         albumDialog.applyAlbumFilter()
                                     }
                                 }
                             }
                         }
                     }
                 }

                 Repeater {
                     model: albumModel

                     ListItem {
                         contentHeight: Theme.itemSizeMedium
                         highlighted: down || albumDialog.selectedAlbumId === albumId

                         Row {
                             anchors.left: parent.left
                             anchors.leftMargin: Theme.horizontalPageMargin
                             anchors.verticalCenter: parent.verticalCenter
                             spacing: Theme.paddingMedium

                             Icon {
                                 source: "image://theme/icon-m-folder"
                                 width: Theme.iconSizeMedium
                                 height: Theme.iconSizeMedium
                                 anchors.verticalCenter: parent.verticalCenter
                             }

                             Column {
                                 anchors.verticalCenter: parent.verticalCenter

                                 Label {
                                     text: albumName
                                     color: highlighted ? Theme.highlightColor : Theme.primaryColor
                                 }

                                 Label {
                                     //% "%1 asset(s)"
                                     text: qsTrId("timelinePage.assets").arg(assetCount || 0)
                                     font.pixelSize: Theme.fontSizeSmall
                                     color: Theme.secondaryColor
                                 }
                             }
                         }

                         onClicked: {
                             albumDialog.selectedAlbumId = albumId
                             albumDialog.createNew = false
                             newAlbumField.text = ""
                             albumDialog.accept()
                         }
                     }
                 }

                 Label {
                     x: Theme.horizontalPageMargin
                     width: parent.width - 2 * Theme.horizontalPageMargin
                     //% "No albums yet"
                     text: qsTrId("timelinePage.noAlbums")
                     color: Theme.secondaryColor
                     visible: albumModel.rowCount() === 0
                 }

                 Item {
                     width: parent.width
                     height: Theme.paddingLarge
                 }
             }


             VerticalScrollDecorator {}
         }
     }
 }


 // Pending scroll state
 property string pendingScrollAssetId: ""
 property int pendingScrollBucketIndex: -1
 property bool scrollInProgress: pendingScrollBucketIndex >= 0

 function performScrollToBucket(bucketIndex) {
     // Calculate Y position by summing heights of preceding buckets
     var bucketY = 0
     for (var i = 0; i < bucketIndex; i++) {
         var item = bucketsRepeater.itemAt(i)
         if (item) {
             bucketY += item.height
         }
     }
     // Add offset for page header, filter bar and memories bar
     var headerOffset = Theme.itemSizeLarge + filterBar.height + Theme.paddingSmall
     if (memoriesBar.visible) {
         headerOffset += memoriesBar.height
     }
     bucketY += headerOffset
     flickable.contentY = Math.max(0, bucketY - Theme.paddingLarge)

     // Force viewport visibility check after scroll
     viewportCheckTimer.restart()
 }

 Connections {
     target: timelineModel
     onScrollToAssetRequested: {
         // First, ensure the target bucket's data is loaded
         var targetItem = bucketsRepeater.itemAt(bucketIndex)
         if (targetItem) {
             targetItem.loadBucketData()
         }

         // Check if bucket assets are already loaded
         if (timelineModel.isBucketLoaded(bucketIndex)) {
             // Bucket is loaded, scroll immediately
             performScrollToBucket(bucketIndex)
         } else {
             // Request bucket load and wait
             pendingScrollAssetId = assetId
             pendingScrollBucketIndex = bucketIndex
             timelineModel.requestBucketLoad(bucketIndex)

             // Also pre-load a few surrounding buckets to stabilize heights
             for (var i = Math.max(0, bucketIndex - 2); i <= Math.min(bucketIndex + 2, bucketCount - 1); i++) {
                 if (i !== bucketIndex) {
                     var item = bucketsRepeater.itemAt(i)
                     if (item) {
                         item.loadBucketData()
                     }
                     if (!timelineModel.isBucketLoaded(i)) {
                         timelineModel.requestBucketLoad(i)
                     }
                 }
             }
         }
     }

     onDataChanged: {
         // Check if pending scroll bucket is now loaded
         if (pendingScrollBucketIndex >= 0 && timelineModel.isBucketLoaded(pendingScrollBucketIndex)) {
             var targetItem = bucketsRepeater.itemAt(pendingScrollBucketIndex)
             if (targetItem) {
                 targetItem.loadAssets()
             }
             // Small delay to let layout stabilize
             scrollDelayTimer.restart()
         }
     }
 }

 Timer {
     id: scrollDelayTimer
     interval: 100
     repeat: false
     onTriggered: {
         if (pendingScrollBucketIndex >= 0) {
             performScrollToBucket(pendingScrollBucketIndex)
             pendingScrollAssetId = ""
             pendingScrollBucketIndex = -1
         }
     }
 }

 Timer {
     id: viewportCheckTimer
     interval: 50
     repeat: false
     onTriggered: {
         // Force all buckets to check their viewport visibility
         for (var i = 0; i < bucketsRepeater.count; i++) {
             var item = bucketsRepeater.itemAt(i)
             if (item && item.checkViewportVisibility) {
                 item.checkViewportVisibility();
             }
         }
     }
 }

 Component.onCompleted: {
     // Load timeline using buckets API
     timelineModel.setLoading(true)
     immichApi.fetchTimelineBuckets()
     // Load memories
     immichApi.fetchMemories()
     memoriesBar.loading = true
 }

 Connections {
     target: immichApi
     onTimelineBucketsReceived: {
         timelineModel.setLoading(false)
     }
     onMemoriesReceived: {
         memoriesBar.loading = false
         memoriesBar.loadMemories(memories)
     }
     onErrorOccurred: {
         timelineModel.setLoading(false)
         errorNotification.show(error)
     }
     onAssetsDeleted: {
         //% "Deleted %1 asset(s)"
         errorNotification.show(qsTrId("timelinePage.deleted").arg(assetIds.length))
     }
     onAssetDownloaded: {
         //% "Downloaded to: %1"
         errorNotification.show(qsTrId("timelinePage.downloaded").arg(filePath))
     }
     onAssetsAddedToAlbum: {
         timelineModel.clearSelection()
         page.pendingAlbumAssetIds = []
         //% "Added asset(s) to album"
         errorNotification.show(qsTrId("timelinePage.addedToAlbum"))
     }
     onFavoritesToggled: {
         timelineModel.clearSelection()
         errorNotification.show(isFavorite
              //% "Added %1 asset(s) to favorites"
              ? qsTrId("timelinePage.addedToFavorites").arg(assetIds.length)
              //% "Removed %1 asset(s) from favorites"
              : qsTrId("timelinePage.removedFromFavorites").arg(assetIds.length))
     }
     onAlbumCreated: {
         // After album is created, add pending assets to it
         if (page.pendingAlbumAssetIds.length > 0) {
             immichApi.addAssetsToAlbum(albumId, page.pendingAlbumAssetIds)
         }
         //% "Created album: %1"
         errorNotification.show(qsTrId("timelinePage.createdAlbum").arg(albumName))
         // Refresh albums list
         immichApi.fetchAlbums()
     }
 }

 Rectangle {
     id: errorNotification
     anchors.bottom: parent.bottom
     anchors.left: parent.left
     anchors.right: parent.right
     height: errorLabel.height + Theme.paddingLarge * 2
     color: Theme.rgba(Theme.errorColor, 0.9)
     visible: opacity > 0
     opacity: 0

     Behavior on opacity {
         NumberAnimation { duration: 300 }
     }

     Label {
         id: errorLabel
         anchors.centerIn: parent
         width: parent.width - Theme.paddingLarge * 2
         wrapMode: Text.WordWrap
         horizontalAlignment: Text.AlignHCenter
         color: Theme.primaryColor
     }

     function show(message) {
         errorLabel.text = message
         opacity = 1
         hideTimer.restart()
     }

     Timer {
         id: hideTimer
         interval: 5000
         onTriggered: errorNotification.opacity = 0
     }

     MouseArea {
         anchors.fill: parent
         onClicked: errorNotification.opacity = 0
     }
 }
}
