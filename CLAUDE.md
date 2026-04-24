# CLAUDE.md

## Project overview

SmartMet data ingestion module for weather model data. Converts GRIB files to SmartMet querydata format. RPM-packaged, deployed to `/smartmet/` paths on Rocky Linux systems.

Repository: https://github.com/fmidev/smartmet-data-models

## Repository structure

- `ingest-model.sh` — Main ingestion script
- `grib2cnf` — GRIB to config conversion tool
- `<model>/` — Per-model directories (arpege, ecmwf, gfs, gsm, icon, ukmo, wrf), each containing:
  - `<model>.cnf` — Model configuration
  - `<model>-surface.cnf`, `<model>-pressure.cnf` — Parameter definitions
  - `<model>.cron` — Cron schedule
  - `clean_data_<model>` — Cleanup script
  - `update.sh` / other scripts — Model-specific download/processing
- `smartmet-data-models.spec` — RPM spec file (version is the source of truth for CI releases)
- `.github/workflows/main.yml` — CI workflow: builds RPMs on Rocky 8/9/10, creates GitHub releases

## Build and CI

- RPMs are built inside Rocky Linux containers (8, 9, 10) using `rpmbuild`
- On push to master, a GitHub release is created tagged `v{Version}` from the spec file
- The release step uses `gh` CLI (not a third-party action) to avoid Node.js version issues
- Version bumps require updating `Version:` in the spec file and adding a `%changelog` entry

## Conventions

- Config files use shell variable syntax (sourced by bash scripts)
- Parameter definition files (e.g. `icon-surface.cnf`) use semicolon-delimited fields
- RPM subpackages exist per model (e.g. `smartmet-data-models-ecmwf`)
- Files are installed with `smartmet:smartmet` ownership
