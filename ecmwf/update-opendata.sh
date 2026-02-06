#!/usr/bin/env bash
set -euo pipefail

INCOMING=/smartmet/data/incoming/ecmwf
export INCOMING

PYTHON=/usr/bin/python3
DL=/smartmet/bin/ecmwf-opendata.py

STEPS="0:144:3,150:240:6"
JOBS=4

# Determine model run time (analysis time)
# ECMWF IFS runs at 00, 06, 12, 18 UTC; data available ~7-8h after analysis
UTC_HOUR=$(date -u +%H)
UTC_HOUR=${UTC_HOUR#0}  # Remove leading zero for arithmetic
if   (( UTC_HOUR >= 7  && UTC_HOUR < 13 )); then
    RUN_HOUR=00
    RUN_DATE=$(date -u +%y%m%d)
elif (( UTC_HOUR >= 13 && UTC_HOUR < 19 )); then
    RUN_HOUR=06
    RUN_DATE=$(date -u +%y%m%d)
elif (( UTC_HOUR >= 19 )); then
    RUN_HOUR=12
    RUN_DATE=$(date -u +%y%m%d)
else
    # UTC 00-06: use previous day's 18Z run
    RUN_HOUR=18
    RUN_DATE=$(date -u -d "yesterday" +%y%m%d)
fi
TIMESTAMP="${RUN_DATE}${RUN_HOUR}"

# Retry settings (handled by the Python script)
RETRIES=5
TIMEOUT=60
RETRY_WAIT=5
RETRY_BACKOFF=2
RETRY_MAX_WAIT=120
CLEANUP="--cleanup-partial"

parallel --halt now,fail=1 -j "$JOBS" ::: \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype sfc --steps \"$STEPS\" --param 2t,msl,tcc            --target $INCOMING/ifs_sfc_a_${TIMESTAMP}.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype sfc --steps \"$STEPS\" --param 10u,10v,mucape,ptype  --target $INCOMING/ifs_sfc_b_${TIMESTAMP}.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype sfc --steps \"$STEPS\" --param tp,sd,2d,z            --target $INCOMING/ifs_sfc_c_${TIMESTAMP}.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype pl --levelist 1000,925,850,700,600,500 --steps \"$STEPS\" --param u,v   --target $INCOMING/ifs_pl_a_${TIMESTAMP}.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype pl --levelist 1000,925,850,700,600,500 --steps \"$STEPS\" --param t,rh  --target $INCOMING/ifs_pl_b_${TIMESTAMP}.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype pl --levelist 400,300,250,200,150,100,50 --steps \"$STEPS\" --param u,v  --target $INCOMING/ifs_pl_c_${TIMESTAMP}.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype pl --levelist 400,300,250,200,150,100,50 --steps \"$STEPS\" --param t,rh --target $INCOMING/ifs_pl_d_${TIMESTAMP}.grib2"