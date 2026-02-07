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

Example of ECMWF opendata cnf, to be used with ecmwf-opendata.py
```
MODEL=ecmwf
MODEL_ID=240
MODEL_RAW_ROOT='/smartmet/data/incoming/ecmwf'
MODEL_RAW_DIR=''
MODEL_RAW_SFC='\*ifs_sfc\*${RT_DATE_MMDD}${RT_HOUR}\*.grib2'
MODEL_RAW_PL='\*ifs_pl\*${RT_DATE_MMDD}${RT_HOUR}\*.grib2'

MODEL_RAW_MASK='\*.grib2'

AREA=bhutan

#CROP=LEFT,BOTTOM,RIGHT,TOP
CROP=61,7,103,40
```

## Dependencies

- smartmet-qdtools / smartmet-qdconversion
- eccodes / grib_api
- curl, pbzip2, rsync
- python 3.9 
