import QtQuick 2.0
import Sailfish.Silica 1.0
import QtGraphicalEffects 1.0
import "../components"

Page {
   id: searchPage

   property var selectedPeople: []
   property var peopleData: []  // Array of {personId, name, thumbnailId}
   property var searchSuggestions: ({})

   // Store selection data for filterable pickers
   //% "Any"
   property var stateData: ({ index: 0, value: "", display: qsTrId("searchPage.stateAny") })
   //% "Any"
   property var countryData: ({ index: 0, value: "", display: qsTrId("searchPage.countryAny") })
   //% "Any"
   property var cityData: ({ index: 0, value: "", display: qsTrId("searchPage.cityAny") })
   //% "Any"
   property var cameraMakeData: ({ index: 0, value: "", display: qsTrId("searchPage.cameraMakeAny") })
   //% "Any"
   property var cameraModelData: ({ index: 0, value: "", display: qsTrId("searchPage.camoreModelAny") })
   //% "Any"
   property var lensModelData: ({ index: 0, value: "", display: qsTrId("searchPage.lensModelAny") })

   // Store raw suggestion arrays for filtering
   property var stateSuggestions: []
   property var countrySuggestions: []
   property var citySuggestions: []
   property var cameraMakeSuggestions: []
   property var cameraModelSuggestions: []
   property var lensModelSuggestions: []

   function clearFilters() {
       contextSearchField.text = ""
       searchTypeCombo.currentIndex = 0
       sortOrderCombo.currentIndex = 0
       selectedPeople = []
       //% "Any"
       stateData = { index: 0, value: "", display: qsTrId("searchPage.stateAny") }
       //% "Any"
       countryData = { index: 0, value: "", display: qsTrId("searchPage.countryAny") }
       //% "Any"
       cityData = { index: 0, value: "", display: qsTrId("searchPage.cityAny") }
       //% "Any"
       cameraMakeData = { index: 0, value: "", display: qsTrId("searchPage.cameraMakeAny") }
       //% "Any"
       cameraModelData = { index: 0, value: "", display: qsTrId("searchPage.camoreModelAny") }
       //% "Any"
       lensModelData = { index: 0, value: "", display: qsTrId("searchPage.lensModelAny") }
       dateFromPicker.dateText = ""
       dateToPicker.dateText = ""
       mediaTypeCombo.currentIndex = 0
       archivedSwitch.checked = false
       notInAlbumSwitch.checked = false
       favoriteSwitch.checked = false
   }

   function performSearch() {
       var params = {}

       // Search field based on type
       if (contextSearchField.text.length > 0) {
           var searchText = contextSearchField.text
           switch (searchTypeCombo.currentIndex) {
               case 0: // Context (smart search)
                   params.query = searchText
                   break
               case 1: // Filename
                   params.originalFileName = searchText
                   break
               case 2: // Description
                   params.description = searchText
                   break
               case 3: // OCR
                   params.query = searchText
                   params.withExif = true  // OCR results are in EXIF/smart search
                   break
           }
       }

       // Sort order
       params.order = sortOrderCombo.currentIndex === 0 ? "desc" : "asc"

       // People
       if (selectedPeople.length > 0) {
           params.personIds = selectedPeople
       }

       // Place
       if (stateData.index > 0 && stateData.value) {
           params.state = stateData.value
       }
       if (countryData.index > 0 && countryData.value) {
           params.country = countryData.value
       }
       if (cityData.index > 0 && cityData.value) {
           params.city = cityData.value
       }

       // Camera
       if (cameraMakeData.index > 0 && cameraMakeData.value) {
           params.make = cameraMakeData.value
       }
       if (cameraModelData.index > 0 && cameraModelData.value) {
           params.model = cameraModelData.value
       }
       if (lensModelData.index > 0 && lensModelData.value) {
           params.lensModel = lensModelData.value
       }

       // Date range
       if (dateFromPicker.dateText.length > 0) {
           params.takenAfter = dateFromPicker.dateText
       }
       if (dateToPicker.dateText.length > 0) {
           params.takenBefore = dateToPicker.dateText
       }

       // Media type
       if (mediaTypeCombo.currentIndex === 1) {
           params.type = "IMAGE"
       } else if (mediaTypeCombo.currentIndex === 2) {
           params.type = "VIDEO"
       }

       // Display options
       if (notInAlbumSwitch.checked) {
           params.isNotInAlbum = true
       }
       if (archivedSwitch.checked) {
           params.isArchived = true
       }
       if (favoriteSwitch.checked) {
           params.isFavorite = true
       }

       pageStack.push(Qt.resolvedUrl("SearchResultsPage.qml"), {
           searchParams: params
       })
   }

   SilicaFlickable {
       id: searchFlickable
       anchors.fill: parent
       contentHeight: searchContent.height

       PullDownMenu {
           MenuItem {
               //% "Settings"
               text: qsTrId("searchPage.settings")
               onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
           }

           MenuItem {
               //% "Albums"
               text: qsTrId("searchPage.albums")
               onClicked: pageStack.push(Qt.resolvedUrl("AlbumsPage.qml"))
           }

           MenuItem {
               //% "Timeline"
               text: qsTrId("searchPage.timeline")
               onClicked: pageStack.replaceAbove(null, Qt.resolvedUrl("TimelinePage.qml"))
           }

           MenuItem {
               //% "Clear search filters"
               text: qsTrId("searchPage.clearFilters")
               onClicked: searchPage.clearFilters()
           }

           MenuItem {
               //% "Search assets"
               text: qsTrId("searchPage.searchAction")
               onClicked: searchPage.performSearch()
           }
       }

       Column {
           id: searchContent
           width: parent.width
           spacing: 0

           PageHeader {
               //% "Search"
               title: qsTrId("searchPage.search")
           }

           // Search Section
           SectionHeader {
               //% "Search Type"
               text: qsTrId("searchPage.searchType")
           }

           ComboBox {
               id: searchTypeCombo
               //% "Search in"
               label: qsTrId("searchPage.searchInLabel")
               currentIndex: 0
               menu: ContextMenu {
                   //% "Context (smart search)"
                   MenuItem { text: qsTrId("searchPage.searchInContext") }
                   //% "Filename / Extension"
                   MenuItem { text: qsTrId("searchPage.searchInFileName") }
                   //% "Description"
                   MenuItem { text: qsTrId("searchPage.searchInDescription") }
                   //% "OCR (text in images)"
                   MenuItem { text: qsTrId("searchPage.searchInOcr") }
               }
           }

           TextField {
               id: contextSearchField
               width: parent.width
               placeholderText: {
                   switch (searchTypeCombo.currentIndex) {
                       //% "Search by description, objects, etc."
                       case 0: return qsTrId("searchPage.searchInContextPlaceholder")
                       //% "e.g. IMG_1234.jpg or .png"
                       case 1: return qsTrId("searchPage.searchInFileNamePlaceholder")
                       //% "Search in asset descriptions"
                       case 2: return qsTrId("searchPage.searchInDescriptionPlaceholder")
                       //% "Search text visible in assets"
                       case 3: return qsTrId("searchPage.searchInOcrPlaceholder")
                       //% "Enter search query"
                       default: return qsTrId("searchPage.searchInPlaceholder")
                   }
               }
               //% "Search query"
               label: qsTrId("searchPage.query")
               EnterKey.iconSource: "image://theme/icon-m-enter-next"
               EnterKey.onClicked: focus = false
           }

           // Sort Order
           ComboBox {
               id: sortOrderCombo
               //% "Sort order"
               label: qsTrId("searchPage.sortOrderLabel")
               currentIndex: 0
               menu: ContextMenu {
                   //% "Newest first"
                   MenuItem { text: qsTrId("searchPage.sortOrderNewest") }
                   //% "Oldest first"
                   MenuItem { text: qsTrId("searchPage.sortOrderOldest") }
               }
           }

           // People Section
           SectionHeader {
               //% "People"
               text: qsTrId("searchPage.people")
           }

           // Hidden model for storing people data
           ListModel {
               id: peopleModel
           }

           ValueButton {
               //% "People"
               label: qsTrId("searchPage.peopleLabel")
               value: {
                   if (selectedPeople.length === 0) {
                       //% "Any"
                       return qsTrId("searchPage.peopleAny")
                   } else if (selectedPeople.length === 1) {
                       // Find the name of the selected person
                       for (var i = 0; i < peopleData.length; i++) {
                           if (peopleData[i].personId === selectedPeople[0]) {
                               //% "Unknown"
                               return peopleData[i].name || qsTrId("searchPage.peopleUnknown")
                           }
                       }
                       //% "1 selected"
                       return qsTrId("searchPage.peopleOneSelected")
                   } else {
                       //% "%1 selected"
                       return qsTrId("searchPage.peopleSelected").arg(selectedPeople.length)
                   }
               }
               onClicked: {
                   var dialog = pageStack.push(Qt.resolvedUrl("../components/PeoplePickerDialog.qml"), {
                       model: peopleData,
                       selectedPeople: selectedPeople.slice() // pass a copy
                   })
                   dialog.accepted.connect(function() {
                       selectedPeople = dialog.selectedPeople
                   })
               }
           }

           Label {
               x: Theme.horizontalPageMargin
               width: parent.width - 2 * Theme.horizontalPageMargin
               //% "Loading people..."
               text: peopleData.length === 0 ? qsTrId("searchPage.peopleLoading") : ""
               color: Theme.secondaryColor
               font.pixelSize: Theme.fontSizeSmall
               visible: peopleData.length === 0
           }

           // Place Section
           SectionHeader {
               //% "Place"
               text: qsTrId("searchPage.place")
           }

           ValueButton {
               //% "State"
               label: qsTrId("searchPage.stateLabel")
               value: stateData.display
               onClicked: {
                   var dialog = pageStack.push(Qt.resolvedUrl("../components/FilterablePickerDialog.qml"), {
                       //% "Select State"
                       title: qsTrId("searchPage.stateSelect"),
                       model: stateSuggestions,
                       selectedIndex: stateData.index
                   })
                   dialog.accepted.connect(function() {
                       stateData = {
                           index: dialog.selectedIndex,
                           value: dialog.selectedValue,
                           display: dialog.selectedDisplayValue
                       }
                   })
               }
           }

           ValueButton {
               //% "Country"
               label: qsTrId("searchPage.countryLabel")
               value: countryData.display
               onClicked: {
                   var dialog = pageStack.push(Qt.resolvedUrl("../components/FilterablePickerDialog.qml"), {
                       //% "Select Country"
                       title: qsTrId("searchPage.countrySelect"),
                       model: countrySuggestions,
                       selectedIndex: countryData.index
                   })
                   dialog.accepted.connect(function() {
                       countryData = {
                           index: dialog.selectedIndex,
                           value: dialog.selectedValue,
                           display: dialog.selectedDisplayValue
                       }
                   })
               }
           }

           ValueButton {
               //% "City"
               label: qsTrId("searchPage.cityLabel")
               value: cityData.display
               onClicked: {
                   var dialog = pageStack.push(Qt.resolvedUrl("../components/FilterablePickerDialog.qml"), {
                       //% "Select City"
                       title: qsTrId("searchPage.citySelect"),
                       model: citySuggestions,
                       selectedIndex: cityData.index
                   })
                   dialog.accepted.connect(function() {
                       cityData = {
                           index: dialog.selectedIndex,
                           value: dialog.selectedValue,
                           display: dialog.selectedDisplayValue
                       }
                   })
               }
           }

           // Camera Section
           SectionHeader {
               //% "Camera"
               text: qsTrId("searchPage.camera")
           }

           ValueButton {
               //% "Camera Make"
               label: qsTrId("searchPage.cameraMakeLabel")
               value: cameraMakeData.display
               onClicked: {
                   var dialog = pageStack.push(Qt.resolvedUrl("../components/FilterablePickerDialog.qml"), {
                       //% "Select Camera Make"
                       title: qsTrId("searchPage.cameraMakeSelect"),
                       model: cameraMakeSuggestions,
                       selectedIndex: cameraMakeData.index
                   })
                   dialog.accepted.connect(function() {
                       cameraMakeData = {
                           index: dialog.selectedIndex,
                           value: dialog.selectedValue,
                           display: dialog.selectedDisplayValue
                       }
                   })
               }
           }

           ValueButton {
               //% "Camera Model"
               label: qsTrId("searchPage.cameraModelLabel")
               value: cameraModelData.display
               onClicked: {
                   var dialog = pageStack.push(Qt.resolvedUrl("../components/FilterablePickerDialog.qml"), {
                       //% "Select Camera Model"
                       title: qsTrId("searchPage.cameraModelSelect"),
                       model: cameraModelSuggestions,
                       selectedIndex: cameraModelData.index
                   })
                   dialog.accepted.connect(function() {
                       cameraModelData = {
                           index: dialog.selectedIndex,
                           value: dialog.selectedValue,
                           display: dialog.selectedDisplayValue
                       }
                   })
               }
           }

           ValueButton {
               //% "Lens Model"
               label: qsTrId("searchPage.lensModelLabel")
               value: lensModelData.display
               onClicked: {
                   var dialog = pageStack.push(Qt.resolvedUrl("../components/FilterablePickerDialog.qml"), {
                       //% "Select Lens Model"
                       title: qsTrId("searchPage.lendsModelSelect"),
                       model: lensModelSuggestions,
                       selectedIndex: lensModelData.index
                   })
                   dialog.accepted.connect(function() {
                       lensModelData = {
                           index: dialog.selectedIndex,
                           value: dialog.selectedValue,
                           display: dialog.selectedDisplayValue
                       }
                   })
               }
           }

           // Date Range Section
           SectionHeader {
               //% "Date Range"
               text: qsTrId("searchPage.dateRange")
           }

           ValueButton {
               id: dateFromPicker
               //% "From"
               label: qsTrId("searchPage.fromLabel")
               //% "Not set"
               value: dateText || qsTrId("searchPage.fromNotSet")
               property string dateText: ""
               onClicked: {
                   var dialog = pageStack.push("Sailfish.Silica.DatePickerDialog", {
                       date: dateText ? new Date(dateText) : new Date()
                   })
                   dialog.accepted.connect(function() {
                       dateText = Qt.formatDate(dialog.date, "yyyy-MM-dd")
                   })
               }
           }

           ValueButton {
               id: dateToPicker
               //% "To"
               label: qsTrId("searchPage.toLabel")
               //% "Not set"
               value: dateText || qsTrId("searchPage.toNotSet")
               property string dateText: ""
               onClicked: {
                   var dialog = pageStack.push("Sailfish.Silica.DatePickerDialog", {
                       date: dateText ? new Date(dateText) : new Date()
                   })
                   dialog.accepted.connect(function() {
                       dateText = Qt.formatDate(dialog.date, "yyyy-MM-dd")
                   })
               }
           }

           // Media Type Section
           SectionHeader {
               //% "Media Type"
               text: qsTrId("searchPage.mediaType")
           }

           ComboBox {
               id: mediaTypeCombo
               //% "Type"
               label: qsTrId("searchPage.typeLabel")
               currentIndex: 0
               menu: ContextMenu {
                   //% "All"
                   MenuItem { text: qsTrId("searchPage.typeAll") }
                   //% "Photos"
                   MenuItem { text: qsTrId("searchPage.typePhotos") }
                   //% "Videos"
                   MenuItem { text: qsTrId("searchPage.typeVideos") }
               }
           }

           // Display Options Section
           SectionHeader {
               //% "Display Options"
               text: qsTrId("searchPage.display")
           }

           TextSwitch {
               id: notInAlbumSwitch
               //% "Not in album"
               text: qsTrId("searchPage.displayNotInAlbum")
               //% "Show only assets not in any album"
               description: qsTrId("searchPage.displayNotInAlbumInfo")
           }

           TextSwitch {
               id: archivedSwitch
               //% "Include archived"
               text: qsTrId("searchPage.displayIncludeArchived")
               //% "Include archived assets in results"
               description: qsTrId("searchPage.displayIncludeArchivedInfo")
           }

           TextSwitch {
               id: favoriteSwitch
               //% "Favorites only"
               text: qsTrId("searchPage.displayFavoritesOnly")
               //% "Show only favorite assets"
               description: qsTrId("searchPage.displayFavoritesOnlyInfo")
           }

           Item {
               width: parent.width
               height: Theme.paddingLarge
           }
       }

       VerticalScrollDecorator {}
   }

   Component.onCompleted: {
       immichApi.fetchPeople()
       immichApi.fetchSearchSuggestions("state")
       immichApi.fetchSearchSuggestions("country")
       immichApi.fetchSearchSuggestions("city")
       immichApi.fetchSearchSuggestions("camera-make")
       immichApi.fetchSearchSuggestions("camera-model")
       immichApi.fetchSearchSuggestions("camera-lens-model")
   }

   Connections {
       target: immichApi

       onPeopleReceived: {
           peopleModel.clear()
           var newPeopleData = []
           for (var i = 0; i < people.length; i++) {
               var person = people[i]
               // Extract person ID from thumbnailPath if available, otherwise use person.id
               var personId = person.id
               if (person.thumbnailPath) {
                   // thumbnailPath format: "data/thumbs/.../{id}.jpeg"
                   // Extract the filename without extension
                   var pathParts = person.thumbnailPath.split('/')
                   if (pathParts.length > 0) {
                       var filename = pathParts[pathParts.length - 1]
                       var idMatch = filename.replace('.jpeg', '').replace('.jpg', '')
                       if (idMatch) {
                           personId = idMatch
                       }
                   }
               }
               var personData = {
                   personId: person.id,
                   name: person.name || "",
                   thumbnailId: personId
               }
               peopleModel.append(personData)
               newPeopleData.push(personData)
           }
           peopleData = newPeopleData
       }

       onSearchSuggestionsReceived: {
           var result = []
           for (var i = 0; i < suggestions.length; i++) {
               var value = suggestions[i]
               //% "Unknown"
               var displayValue = value === null ? qsTrId("searchPage.unknown") : value
               result.push({
                   displayValue: displayValue,
                   actualValue: value || ""
               })
           }

           if (type === "state") {
               stateSuggestions = result
           } else if (type === "country") {
               countrySuggestions = result
           } else if (type === "city") {
               citySuggestions = result
           } else if (type === "camera-make") {
               cameraMakeSuggestions = result
           } else if (type === "camera-model") {
               cameraModelSuggestions = result
           } else if (type === "camera-lens-model") {
               lensModelSuggestions = result
           }
       }

   }
}
