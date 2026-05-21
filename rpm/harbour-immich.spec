%bcond_with harbour

Name:       harbour-immich

Summary:    Immich client for Sailfish OS
Version:    0.3.2
Release:    1
Group:      Applications/Multimedia
License:    GPLv3
URL:        https://github.com/mezmerize/harbour-immich
Source0:    %{name}-%{version}.tar.bz2

Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   qt5-qtmultimedia

BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Network)
BuildRequires:  pkgconfig(Qt5Multimedia)
BuildRequires:  pkgconfig(sailfishsecrets)
BuildRequires:  desktop-file-utils

%description
A native Immich client for Sailfish OS that allows you to browse, view, and manage your photos stored on an Immich server.

%if 0%{?_chum}
Title: Immich
Type: desktop-application
DeveloperName: Zdeněk Vaník (mezmerize)
Categories:
 - AudioVideo
Custom:
  Repo: https://github.com/mezmerize/harbour-immich
PackageIcon: https://raw.githubusercontent.com/mezmerize/harbour-immich/main/icons/172x172/harbour-immich.png
Links:
  Homepage: https://github.com/mezmerize/harbour-immich
  Bugtracker: https://github.com/mezmerize/harbour-immich/issues
  Help: https://github.com/mezmerize/harbour-immich/discussions
%endif

%prep
%setup -q -n %{name}-%{version}

%build

%if %{with harbour}
%qmake5 CONFIG+=harbour
%else
%qmake5
%endif

%make_build

%install
%qmake5_install

%if %{with harbour}
sed -i 's|Exec=harbour-immich %%u|Exec=harbour-immich|' %{buildroot}%{_datadir}/applications/%{name}.desktop
sed -i '/^MimeType=/d' %{buildroot}%{_datadir}/applications/%{name}.desktop
%endif

desktop-file-install --delete-original       \
  --dir %{buildroot}%{_datadir}/applications             \
   %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
