#!/usr/bin/env bash
set -euo pipefail

INCOMING=/smartmet/data/incoming/ecmwf
export INCOMING

PYTHON=/usr/bin/python3
DL=/smartmet/bin/ecmwf-opendata.py

STEPS="0:144:3,150:240:6"
JOBS=4

# Retry settings (handled by the Python script)
RETRIES=5
TIMEOUT=60
RETRY_WAIT=5
RETRY_BACKOFF=2
RETRY_MAX_WAIT=120
CLEANUP="--cleanup-partial"

parallel --halt now,fail=1 -j "$JOBS" ::: \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype sfc --steps \"$STEPS\" --param 2t,msl,tcc            --target $INCOMING/ifs_sfc_a.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype sfc --steps \"$STEPS\" --param 10u,10v,mucape,ptype  --target $INCOMING/ifs_sfc_b.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype sfc --steps \"$STEPS\" --param tp,sd,2d,z            --target $INCOMING/ifs_sfc_c.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype pl --levelist 1000,925,850,700,600,500 --steps \"$STEPS\" --param u,v   --target $INCOMING/ifs_pl_a.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype pl --levelist 1000,925,850,700,600,500 --steps \"$STEPS\" --param t,rh  --target $INCOMING/ifs_pl_b.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype pl --levelist 400,300,250,200,150,100,50 --steps \"$STEPS\" --param u,v  --target $INCOMING/ifs_pl_c.grib2" \
"$PYTHON $DL --source aws --timeout $TIMEOUT --retries $RETRIES --retry-wait $RETRY_WAIT --retry-backoff $RETRY_BACKOFF --retry-max-wait $RETRY_MAX_WAIT $CLEANUP --levtype pl --levelist 400,300,250,200,150,100,50 --steps \"$STEPS\" --param t,rh --target $INCOMING/ifs_pl_d.grib2"