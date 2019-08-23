%define smartmetroot /smartmet

Name:           smartmet-data-models
Version:        19.8.20
Release:        2%{?dist}.fmi
Summary:        SmartMet Data Models Common
Group:          System Environment/Base
License:        MIT
URL:            https://github.com/fmidev/smartmet-data-models
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:	noarch

%{?el6:Requires: smartmet-qdconversion}
%{?el7:Requires: smartmet-qdtools}
%{?el6:Requires: grib_api}
%{?el7:Requires: eccodes}
Requires:	curl
Requires:	lbzip2
Requires: rsync

%description
SmartMet data ingest module common

%package ecmwf
Summary: SmartMet Data ECMWF
Requires: smartmet-data-models

%description ecmwf
SmartMet data ingest module for ECMWF model

%package gsm
Summary: SmartMet Data GSM
Requires: smartmet-data-models

%description gsm
SmartMet data ingest module for GSM model

%package ukmo
Summary: SmartMet Data UKMO
Requires: smartmet-data-models

%description ukmo
SmartMet data ingest module for UKMO model

%package wrf
Summary: SmartMet Data WRF
Requires: smartmet-data-models

%description wrf
SmartMet data ingest module for WRF model

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

mkdir -p .%{smartmetroot}/run/data/ukmo/{bin,cnf}
install -m 644 %_topdir/SOURCES/smartmet-data-models/ukmo/ukmo.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/ukmo/ukmo.cron %{buildroot}%{smartmetroot}/cnf/cron/cron.d/
install -m 755 %_topdir/SOURCES/smartmet-data-models/ukmo/clean_data_ukmo %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/
install -m 644 %_topdir/SOURCES/smartmet-data-models/ukmo/ukmo-surface.cnf %{buildroot}%{smartmetroot}/run/data/ukmo/cnf/
install -m 644 %_topdir/SOURCES/smartmet-data-models/ukmo/ukmo-pressure.cnf %{buildroot}%{smartmetroot}/run/data/ukmo/cnf/

mkdir -p .%{smartmetroot}/run/data/wrf/{bin,cnf}
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/wrf-large.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/wrf-small.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/wrf.cron %{buildroot}%{smartmetroot}/cnf/cron/cron.d/
install -m 755 %_topdir/SOURCES/smartmet-data-models/wrf/clean_data_wrf %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/wrf-surface.cnf %{buildroot}%{smartmetroot}/run/data/wrf/cnf/
install -m 644 %_topdir/SOURCES/smartmet-data-models/wrf/wrf-pressure.cnf %{buildroot}%{smartmetroot}/run/data/wrf/cnf/

# COMMON
%files
%defattr(-,smartmet,smartmet,-)
%{smartmetroot}/bin/*
%{smartmetroot}/tmp/data
%{smartmetroot}/logs/data

# ECMWF
%files ecmwf
%defattr(-,smartmet,smartmet,-)
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
%config(noreplace) %{smartmetroot}/cnf/data/gsm.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/gsm.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_gsm
%config(noreplace) %{smartmetroot}/run/data/gsm/cnf/gsm-surface.cnf
%config(noreplace) %{smartmetroot}/run/data/gsm/cnf/gsm-pressure.cnf

# UKMO
%files ukmo
%defattr(-,smartmet,smartmet,-)
%config(noreplace) %{smartmetroot}/cnf/data/ukmo.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/ukmo.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_ukmo
%config(noreplace) %{smartmetroot}/run/data/ukmo/cnf/ukmo-surface.cnf
%config(noreplace) %{smartmetroot}/run/data/ukmo/cnf/ukmo-pressure.cnf

# WRF
%files wrf
%defattr(-,smartmet,smartmet,-)
%config(noreplace) %{smartmetroot}/cnf/data/wrf-small.cnf
%config(noreplace) %{smartmetroot}/cnf/data/wrf-large.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/wrf.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_wrf
%config(noreplace) %{smartmetroot}/run/data/wrf/cnf/wrf-surface.cnf
%config(noreplace) %{smartmetroot}/run/data/wrf/cnf/wrf-pressure.cnf

%clean
rm -rf $RPM_BUILD_ROOT

%changelog
* Tue Aug 20 2019 Mikko Rauhala <mikko.rauhala@fmi.fi> 19.8.20-1%{?dist}.fmi
- Initial version
