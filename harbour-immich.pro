TARGET = harbour-immich

CONFIG += sailfishapp link_pkgconfig
QT += network multimedia sql
PKGCONFIG += sailfishsecrets sailfishapp
INCLUDEPATH += /usr/include/Sailfish

CONFIG(release, debug|release): DEFINES += QT_NO_DEBUG_OUTPUT

SOURCES += src/harbour-immich.cpp \
    src/backupdatabase.cpp \
    src/backupmanager.cpp \
    src/immichapi.cpp \
    src/authmanager.cpp \
    src/logmanager.cpp \
    src/oauthmanager.cpp \
    src/securestorage.cpp \
    src/albummodel.cpp \
    src/settingsmanager.cpp \
    src/imageprovider.cpp \
    src/thumbhashprovider.cpp \
    src/timelinemodel.cpp

HEADERS += \
    src/backupdatabase.h \
    src/backupmanager.h \
    src/immichapi.h \
    src/authmanager.h \
    src/logmanager.h \
    src/oauthmanager.h \
    src/securestorage.h \
    src/albummodel.h \
    src/settingsmanager.h \
    src/imageprovider.h \
    src/thumbhashprovider.h \
    src/timelinemodel.h

icons.files = icons/cover-icon.png
icons.path = $$PREFIX/share/$${TARGET}/icons
INSTALLS += icons

DISTFILES += qml/harbour-immich.qml \
    qml/components/AssetGridItem.qml \
    qml/components/DismissDragBackdrop.qml \
    qml/components/DownloadFolderDialog.qml \
    qml/components/FilterablePickerDialog.qml \
    qml/components/MemoriesBar.qml \
    qml/components/NotificationBanner.qml \
    qml/components/PeoplePickerDialog.qml \
    qml/components/QRCode.qml \
    qml/components/ScrollToTopButton.qml \
    qml/components/SelectionActionBar.qml \
    qml/components/TimelineBucketDelegate.qml \
    qml/components/TimelineFilterBar.qml \
    qml/components/ZoomSwipeArea.qml \
    qml/cover/CoverPage.qml \
    qml/pages/AlbumInfoPage.qml \
    qml/pages/AlbumPickerPage.qml \
    qml/pages/AssetDetailPage.qml \
    qml/pages/AssetInfoPage.qml \
    qml/pages/EditAlbumDialog.qml \
    qml/pages/EditAssetDialog.qml \
    qml/pages/FolderPickerPage.qml \
    qml/pages/LogViewerPage.qml \
    qml/pages/MemoryDetailPage.qml \
    qml/pages/OAuthPage.qml \
    qml/pages/SearchResultsPage.qml \
    qml/pages/ServerPage.qml \
    qml/pages/LoginPage.qml \
    qml/pages/AlbumsPage.qml \
    qml/pages/AlbumDetailPage.qml \
    qml/pages/SearchPage.qml \
    qml/pages/SettingsPage.qml \
    qml/pages/SharePage.qml \
    qml/pages/ShareResultPage.qml \
    qml/pages/StackDetailPage.qml \
    qml/pages/TimelinePage.qml \
    qml/pages/UploadPage.qml \
    qml/pages/VideoPlayerPage.qml \
    icons/cover-icon.png \
    rpm/harbour-immich.changes.in \
    rpm/harbour-immich.changes.run.in \
    rpm/harbour-immich.spec \
    translations/*.ts \
    harbour-immich.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

CONFIG += sailfishapp_i18n sailfishapp_i18n_idbased

TRANSLATIONS += translations/harbour-immich-cs.ts \
                translations/harbour-immich-en.ts \
                translations/harbour-immich-it.ts \
                translations/harbour-immich-nb_NO.ts

lupdate_only {
    SOURCES += qml/*.qml \
               qml/pages/*.qml \
               qml/cover/*.qml \
               qml/components/*.qml
}
