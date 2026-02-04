# smartmet-data-models

SmartMet data ingestion module for weather model data. Converts GRIB files to SmartMet querydata format.

## Supported Models

| Model | Description |
|-------|-------------|
| ECMWF | European Centre for Medium-Range Weather Forecasts |
| ICON | DWD ICON global (no support for Euro as of yet) |
| GFS | NCEP Global Forecast System |
| GSM | JMA Global Spectral Model |
| UKMO | UK Met Office |
| ARPEGE | Météo-France global model |
| WRF | Weather Research and Forecasting |

## Usage

```bash
./ingest-model.sh -m <model> [-a <area>] [-t <yyyymmddThh>] [-i <input>] [-d] [-f]
```

**Options:**
- `-m model` — Model name (required)
- `-a area` — Geographic area (default: world)
- `-t time` — Reference time
- `-i input` — Input GRIB file
- `-d` — Debug mode
- `-f` — Force processing

## Installation

```bash
# Install base + model package
dnf install smartmet-data-models smartmet-data-models-ecmwf
```

## Configuration

Model configs located in `/smartmet/cnf/data/`:
- `<model>.cnf` — Default configuration
- `<model>-<area>.cnf` — Area-specific configuration

## Dependencies

- smartmet-qdtools / smartmet-qdconversion
- eccodes / grib_api
- curl, pbzip2, rsync
