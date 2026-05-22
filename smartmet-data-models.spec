%define smartmetroot /smartmet

Name:           smartmet-data-models
Version:        26.5.22
Release:        1%{?dist}.fmi
Summary:        SmartMet Data Models Common
Group:          System Environment/Base
License:        MIT
URL:            https://github.com/fmidev/smartmet-data-models
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:	noarch

Requires: smartmet-qdtools
Requires: eccodes
Requires: cdo
Requires: curl
Requires: lftp
Requires: pbzip2
Requires: rsync

%description
Common ingestion tooling (ingest-model.sh, grib2cnf) shared by the
per-model SmartMet data subpackages; converts model GRIB files to
SmartMet querydata. Install a model subpackage such as
smartmet-data-models-ecmwf alongside this one.

%package ecmwf
Summary: SmartMet Data ECMWF
Requires: smartmet-data-models

%description ecmwf
SmartMet data ingestion for the ECMWF IFS model (dissemination or AWS open-data GRIB).

%package gsm
Summary: SmartMet Data GSM
Requires: smartmet-data-models

%description gsm
SmartMet data ingestion for the JMA GSM global model.

%package icon
Summary: SmartMet Data ICON
Requires: smartmet-data-models

%description icon
SmartMet data ingestion for the DWD ICON global model (ICON-EU is handled separately).

%package ukmo
Summary: SmartMet Data UKMO
Requires: smartmet-data-models

%description ukmo
SmartMet data ingestion for the UK Met Office global model.

%package wrf
Summary: SmartMet Data WRF
Requires: smartmet-data-models

%description wrf
SmartMet data ingestion for the WRF model (small and large domains).

%package arpege
Summary: SmartMet Data ARPEGE
Requires: smartmet-data-models

%description arpege
SmartMet data ingestion for the Météo-France ARPEGE global model.

%install
rm -rf $RPM_BUILD_ROOT
mkdir $RPM_BUILD_ROOT
cd $RPM_BUILD_ROOT

mkdir -p .%{smartmetroot}/bin
mkdir -p .%{smartmetroot}/cnf/data
mkdir -p .%{smartmetroot}/tmp/data
mkdir -p .%{smartmetroot}/logs/data
mkdir -p .%{smartmetroot}/cnf/cron/{cron.d,cron.hourly}

install -m 755 %_topdir/SOURCES/smartmet-data-models/ingest-model.sh %{buildroot}%{smartmetroot}/bin/
install -m 755 %_topdir/SOURCES/smartmet-data-models/grib2cnf %{buildroot}%{smartmetroot}/bin/

mkdir -p .%{smartmetroot}/run/data/ecmwf/{bin,cnf}
mkdir -p .%{smartmetroot}/run/data/ecmwf/cnf/{st.surface.d,st.pressure.d}
install -m 644 %_topdir/SOURCES/smartmet-data-models/ecmwf/ecmwf.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/ecmwf/ecmwf.cron %{buildroot}%{smartmetroot}/cnf/cron/cron.d/
install -m 755 %_topdir/SOURCES/smartmet-data-models/ecmwf/clean_data_ecmwf %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/
install -m 644 %_topdir/SOURCES/smartmet-data-models/ecmwf/ecmwf-{surface,pressure}.{cnf,st} %{buildroot}%{smartmetroot}/run/data/ecmwf/cnf/

mkdir -p .%{smartmetroot}/run/data/gsm/{bin,cnf}
install -m 644 %_topdir/SOURCES/smartmet-data-models/gsm/gsm.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/gsm/gsm.cron %{buildroot}%{smartmetroot}/cnf/cron/cron.d/
install -m 755 %_topdir/SOURCES/smartmet-data-models/gsm/clean_data_gsm %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/
install -m 644 %_topdir/SOURCES/smartmet-data-models/gsm/gsm-surface.cnf %{buildroot}%{smartmetroot}/run/data/gsm/cnf/
install -m 644 %_topdir/SOURCES/smartmet-data-models/gsm/gsm-pressure.cnf %{buildroot}%{smartmetroot}/run/data/gsm/cnf/

mkdir -p .%{smartmetroot}/run/data/icon/{bin,cnf}
mkdir -p .%{smartmetroot}/run/data/icon/cnf/st.surface.d
mkdir -p .%{smartmetroot}/data/incoming/icon
install -m 644 %_topdir/SOURCES/smartmet-data-models/icon/icon.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/icon/icon.cron %{buildroot}%{smartmetroot}/cnf/cron/cron.d/
install -m 755 %_topdir/SOURCES/smartmet-data-models/icon/clean_data_icon %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/
install -m 755 %_topdir/SOURCES/smartmet-data-models/icon/update.sh %{buildroot}%{smartmetroot}/run/data/icon/bin/
install -m 644 %_topdir/SOURCES/smartmet-data-models/icon/icon-surface.cnf %{buildroot}%{smartmetroot}/run/data/icon/cnf/
install -m 644 %_topdir/SOURCES/smartmet-data-models/icon/icon-pressure.cnf %{buildroot}%{smartmetroot}/run/data/icon/cnf/
install -m 644 %_topdir/SOURCES/smartmet-data-models/icon/st.surface.d/rr1h-353.st %{buildroot}%{smartmetroot}/run/data/icon/cnf/st.surface.d/

mkdir -p .%{smartmetroot}/run/data/ukmo/{bin,cnf}
install -m 644 %_topdir/SOURCES/smartmet-data-models/ukmo/ukmo.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/ukmo/ukmo.cron %{buildroot}%{smartmetroot}/cnf/cron/cron.d/
install -m 755 %_topdir/SOURCES/smartmet-data-models/ukmo/clean_data_ukmo %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/
install -m 644 %_topdir/SOURCES/smartmet-data-models/ukmo/ukmo-surface.cnf %{buildroot}%{smartmetroot}/run/data/ukmo/cnf/
install -m 644 %_topdir/SOURCES/smartmet-data-models/ukmo/ukmo-pressure.cnf %{buildroot}%{smartmetroot}/run/data/ukmo/cnf/

mkdir -p .%{smartmetroot}/run/data/wrf/{bin,cnf}
mkdir -p .%{smartmetroot}/run/data/wrf/cnf/st.surface.d
mkdir -p .%{smartmetroot}/data/wrf/{small,large}/{surface,pressure}/querydata
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/wrf-large.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/wrf-small.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/wrf.cron %{buildroot}%{smartmetroot}/cnf/cron/cron.d/
install -m 755 %_topdir/SOURCES/smartmet-data-models/wrf/clean_data_wrf %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/wrf-surface.cnf %{buildroot}%{smartmetroot}/run/data/wrf/cnf/
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/wrf-pressure.cnf %{buildroot}%{smartmetroot}/run/data/wrf/cnf/
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/st.surface.d/rr1h-353.st %{buildroot}%{smartmetroot}/run/data/wrf/cnf/st.surface.d/

mkdir -p .%{smartmetroot}/run/data/arpege/{bin,cnf}
install -m 644 %_topdir/SOURCES/smartmet-data-models/arpege/arpege.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/arpege/arpege.cron %{buildroot}%{smartmetroot}/cnf/cron/cron.d/
install -m 755 %_topdir/SOURCES/smartmet-data-models/arpege/clean_data_arpege %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/
install -m 755 %_topdir/SOURCES/smartmet-data-models/arpege/update.sh %{buildroot}%{smartmetroot}/run/data/arpege/bin/
install -m 644 %_topdir/SOURCES/smartmet-data-models/arpege/arpege-surface.cnf %{buildroot}%{smartmetroot}/run/data/arpege/cnf/
install -m 644 %_topdir/SOURCES/smartmet-data-models/arpege/arpege-pressure.cnf %{buildroot}%{smartmetroot}/run/data/arpege/cnf/

# COMMON
%files
%defattr(-,smartmet,smartmet,-)
%{smartmetroot}/bin/*
%{smartmetroot}/tmp/data
%{smartmetroot}/logs/data

# ECMWF
%files ecmwf
%defattr(-,smartmet,smartmet,-)
%dir %{smartmetroot}/run/data/ecmwf
%dir %{smartmetroot}/run/data/ecmwf/bin
%dir %{smartmetroot}/run/data/ecmwf/cnf
%dir %{smartmetroot}/run/data/ecmwf/cnf/st.surface.d
%dir %{smartmetroot}/run/data/ecmwf/cnf/st.pressure.d
%config(noreplace) %{smartmetroot}/cnf/data/ecmwf.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/ecmwf.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_ecmwf
%config(noreplace) %{smartmetroot}/run/data/ecmwf/cnf/ecmwf-surface.cnf
%config(noreplace) %{smartmetroot}/run/data/ecmwf/cnf/ecmwf-pressure.cnf
%config(noreplace) %{smartmetroot}/run/data/ecmwf/cnf/ecmwf-surface.st
%config(noreplace) %{smartmetroot}/run/data/ecmwf/cnf/ecmwf-pressure.st

# GSM
%files gsm
%defattr(-,smartmet,smartmet,-)
%dir %{smartmetroot}/run/data/gsm
%dir %{smartmetroot}/run/data/gsm/bin
%dir %{smartmetroot}/run/data/gsm/cnf
%config(noreplace) %{smartmetroot}/cnf/data/gsm.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/gsm.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_gsm
%config(noreplace) %{smartmetroot}/run/data/gsm/cnf/gsm-surface.cnf
%config(noreplace) %{smartmetroot}/run/data/gsm/cnf/gsm-pressure.cnf

# ICON
%files icon
%defattr(-,smartmet,smartmet,-)
%dir %{smartmetroot}/data/incoming/icon
%dir %{smartmetroot}/run/data/icon
%dir %{smartmetroot}/run/data/icon/bin
%dir %{smartmetroot}/run/data/icon/cnf
%dir %{smartmetroot}/run/data/icon/cnf/st.surface.d
%config(noreplace) %{smartmetroot}/cnf/data/icon.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/icon.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_icon
%attr(0755,smartmet,smartmet) %{smartmetroot}/run/data/icon/bin/update.sh
%config(noreplace) %{smartmetroot}/run/data/icon/cnf/icon-surface.cnf
%config(noreplace) %{smartmetroot}/run/data/icon/cnf/icon-pressure.cnf
%config(noreplace) %{smartmetroot}/run/data/icon/cnf/st.surface.d/rr1h-353.st

# UKMO
%files ukmo
%defattr(-,smartmet,smartmet,-)
%dir %{smartmetroot}/run/data/ukmo
%dir %{smartmetroot}/run/data/ukmo/bin
%dir %{smartmetroot}/run/data/ukmo/cnf
%config(noreplace) %{smartmetroot}/cnf/data/ukmo.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/ukmo.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_ukmo
%config(noreplace) %{smartmetroot}/run/data/ukmo/cnf/ukmo-surface.cnf
%config(noreplace) %{smartmetroot}/run/data/ukmo/cnf/ukmo-pressure.cnf

# WRF
%files wrf
%defattr(-,smartmet,smartmet,-)
%dir %{smartmetroot}/data/wrf
%dir %{smartmetroot}/data/wrf/small
%dir %{smartmetroot}/data/wrf/small/surface
%dir %{smartmetroot}/data/wrf/small/surface/querydata
%dir %{smartmetroot}/data/wrf/small/pressure
%dir %{smartmetroot}/data/wrf/small/pressure/querydata
%dir %{smartmetroot}/data/wrf/large
%dir %{smartmetroot}/data/wrf/large/surface
%dir %{smartmetroot}/data/wrf/large/surface/querydata
%dir %{smartmetroot}/data/wrf/large/pressure
%dir %{smartmetroot}/data/wrf/large/pressure/querydata
%dir %{smartmetroot}/run/data/wrf
%dir %{smartmetroot}/run/data/wrf/bin
%dir %{smartmetroot}/run/data/wrf/cnf
%dir %{smartmetroot}/run/data/wrf/cnf/st.surface.d
%config(noreplace) %{smartmetroot}/cnf/data/wrf-small.cnf
%config(noreplace) %{smartmetroot}/cnf/data/wrf-large.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/wrf.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_wrf
%config(noreplace) %{smartmetroot}/run/data/wrf/cnf/wrf-surface.cnf
%config(noreplace) %{smartmetroot}/run/data/wrf/cnf/wrf-pressure.cnf
%config(noreplace) %{smartmetroot}/run/data/wrf/cnf/st.surface.d/rr1h-353.st

# ARPEGE
%files arpege
%defattr(-,smartmet,smartmet,-)
%dir %{smartmetroot}/run/data/arpege
%dir %{smartmetroot}/run/data/arpege/bin
%dir %{smartmetroot}/run/data/arpege/cnf
%config(noreplace) %{smartmetroot}/cnf/data/arpege.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/arpege.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_arpege
%attr(0755,smartmet,smartmet) %{smartmetroot}/run/data/arpege/bin/update.sh
%config(noreplace) %{smartmetroot}/run/data/arpege/cnf/arpege-surface.cnf
%config(noreplace) %{smartmetroot}/run/data/arpege/cnf/arpege-pressure.cnf

%clean
rm -rf $RPM_BUILD_ROOT

%changelog
* Fri May 22 2026 Mikko Rauhala <mikko.rauhala@fmi.fi> 26.5.22-1%{?dist}.fmi
- Fix completeness check to count endStep instead of startStep, so model
  runs with accumulated fields are no longer re-converted every cycle
- Add hybrid (model) level conversion block to ingest-model.sh
- Add -l (level select) and -n (skip update.sh) options to ingest-model.sh
- ingest-model.sh: create output dir up front, skip empty st.<level>.d
  globs, return 0 from qdstepcount on a missing sqd, move the EXIT trap
  before the work, quote TERM, drop leftover debug prints
- Fix broken ARPEGE download URL (URL-encoded curly braces in PREFIX)
- Package owns the WRF output querydata directories (fixed area names)
* Fri Apr 14 2026 Mikael Hasu <mikael.hasu@fmi.fi> 26.4.14-1%{?dist}.fmi
- Add st.surface.d and rr1h for icon and wrf
* Fri Apr 10 2026 Mikael Hasu <mikael.hasu@fmi.fi> 26.4.10-1%{?dist}.fmi
- Add update.sh to ICON global, added cdo/lftp and incoming directory
* Thu Apr 9 2026 Elmeri Nurmi <elmeri.nurmi@fmi.fi> 26.4.9-1%{?dist}.fmi
- Add update.sh to arpege
* Wed Feb 4 2026 Elmeri Nurmi <elmeri.nurmi@fmi.fi> 26.2.4-1%{?dist}.fmi
- Fix directory ownership for EL9 (RPM 4.18)
* Thu May 8 2025 Elmeri Nurmi <elmeri.nurmi@fmi.fi> 25.5.8-1%{?dist}.fmi
- add ARPEGE model
* Thu Mar 13 2025 Mikko Rauhala <mikko.rauhala@fmi.fi> 25.3.13-1%{?dist}.fmi
- add ICON model
* Thu Oct 19 2023 Mikko Rauhala <mikko.rauhala@fmi.fi> 23.10.19-1%{?dist}.fmi
- change lbizp2 to pbzip2
* Tue Aug 20 2019 Mikko Rauhala <mikko.rauhala@fmi.fi> 19.8.20-1%{?dist}.fmi
- Initial version
