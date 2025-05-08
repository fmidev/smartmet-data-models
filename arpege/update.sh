#!/bin/bash
# Elmeri Nurmi FMI 202505
# Download arpege model data files from https://meteo.data.gouv.fr/datasets
# Paquets Arpège - Résolution 0,25°

set -ex

# Set variables
STEP=6
RT=$(date -u -d '-3 hours' +%s)
RT=$(( RT / (STEP * 3600) * (STEP * 3600) ))
RT_HOUR=$(date -u -d@$RT +%H):00:00
MODELDATE=$(date -u +%Y-%m-%d)
INCOMING=/smartmet/data/incoming/arpege

# Go to incoming
mkdir -p $INCOMING
cd $INCOMING
# Remove older downloaded files 
find $INCOMING/ -name "arpege_025*grib2" -mmin +300 -delete

# Define your timestamp and URL prefix
TS=${MODELDATE}T${RT_HOUR}Z
PREFIX="https://object.data.gouv.fr/meteofrance-pnt/pnt/${TS}/arpege/025"

# Define the two arrays these are packages and lead times of the model different parameters are in different packages
array1=(SP1 SP2 IP1)
array2=(000H024H 025H048H 049H072H 073H102H)
MAX_RETRIES=4
SLEEP_BETWEEN=300

# Loop over and download every combination for Surface and Pressure packages

for pkg in "${array1[@]}"; do
  for grd in "${array2[@]}"; do
    # Build URL and output filename
    url="${PREFIX}/${pkg}/arpege__025__${pkg}__${grd}__${TS}.grib2"
    out="arpege_025_${pkg}_${grd}_${TS}.grib2"

    # Skip if already downloaded
    if [[ -f "$out" ]]; then
      echo "✔ Skipping $out (already exists)"
      continue
    fi

    # Try downloading with retries
    attempt=1
    while (( attempt <= MAX_RETRIES )); do
      echo "↓ Attempt $attempt/$MAX_RETRIES: fetching $url → $out"
      if wget -q "$url" -O "$out"; then
        echo "  ✅ Download succeeded on attempt $attempt"
        break
      else
        echo "  ❌ Download failed on attempt $attempt"
        # Clean up incomplete file
        rm -f "$out"
        if (( attempt < MAX_RETRIES )); then
          echo "    ↻ Retrying in $(( SLEEP_BETWEEN/60 )) minute(s)..."
          sleep $SLEEP_BETWEEN
        fi
      fi
      (( attempt++ ))
    done

    # After loop, if still not present, report final failure
    if [[ ! -f "$out" ]]; then
      echo "‼️ Giving up on $url after $MAX_RETRIES attempts"
    fi
  done
done
