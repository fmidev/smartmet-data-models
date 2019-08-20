%define smartmetroot /smartmet

Name:           smartmet-data-models
Version:        19.8.20
Release:        1%{?dist}.fmi
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

%description ecmwf
SmartMet data ingest module for ECMWF model

%package gsm
Summary: SmartMet Data GSM

%description gsm
SmartMet data ingest module for GSM model

%install
rm -rf $RPM_BUILD_ROOT
mkdir $RPM_BUILD_ROOT
cd $RPM_BUILD_ROOT

mkdir -p .%{smartmetroot}/cnf/cron/{cron.d,cron.hourly}
mkdir -p .%{smartmetroot}/cnf/data
mkdir -p .%{smartmetroot}/tmp/data/gfs
mkdir -p .%{smartmetroot}/logs/data
mkdir -p .%{smartmetroot}/run/data/gfs/{bin,cnf}

install -m 755 %_topdir/SOURCES/smartmet-data-models/ingest-model.sh %{buildroot}%{smartmetroot}/bin/

%files
%defattr(-,smartmet,smartmet,-)
%{smartmetroot}/*

%install ecmwf
mkdir -p .%{smartmetroot}/run/data/ecmwf/{bin,cnf}
install -m 644 %_topdir/SOURCES/smartmet-data-models/ecmwf/ecmwf.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/ecmwf/ecmwf.cron %{buildroot}%{smartmetroot}/cnf/cron/cron.d/
install -m 755 %_topdir/SOURCES/smartmet-data-models/ecmwf/clean_data_ecmwf %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/

%files ecmwf
%defattr(-,smartmet,smartmet,-)
%config(noreplace) %{smartmetroot}/cnf/data/ecmwf.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/ecmwf.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_ecmwf

%install gsm
mkdir -p .%{smartmetroot}/run/data/gsm/{bin,cnf}
install -m 644 %_topdir/SOURCES/smartmet-data-models/gsm/gsm.cnf %{buildroot}%{smartmetroot}/cnf/data/
install -m 644 %_topdir/SOURCES/smartmet-data-models/ecmwf/ecmwf.cron %{buildroot}%{smartmetroot}/cnf/cron/cron.d/
install -m 755 %_topdir/SOURCES/smartmet-data-models/gsm/clean_data_gsm %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/

%files gsm
%defattr(-,smartmet,smartmet,-)
%config(noreplace) %{smartmetroot}/cnf/data/gsm.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/gsm.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_gsm

%clean
rm -rf $RPM_BUILD_ROOT

%changelog
* Tue Aug 20 2019 Mikko Rauhala <mikko.rauhala@fmi.fi> 19.8.20-1%{?dist}.fmi
- Initial version
