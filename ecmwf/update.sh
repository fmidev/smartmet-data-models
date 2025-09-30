#!/bin/bash
# Script to download EMWCF opendata products from AWS
# Use this update.sh if there is no local ECMWF dissemination source available
# Needs AWS CLI to be installed
# E.Nurmi 202404
# https://www.ecmwf.int/en/forecasts/datasets/open-data
# Ready times(UTC) for ECMWF IFS oper/scda model; 00z 07:55, 06z 13:15, 12z 19:55, 18z 01:15. These are indicative times check valid times during install and set cronjob accordingly.
set -ex

# Set forecast cycle
STEP=6
RT=`date -u +%s -d '-6 hours'`
RT="$(( $RT / ($STEP * 3600) * ($STEP * 3600) ))"
RT_HOUR=`date -u -d@$RT +%H`
RT_DATE=`date -u -d@$RT +%Y%m%d`

# Set variables
MODEL_PRODUCER=ifs
MODEL_VERSION=0p25
MODEL_TYPE=oper
INCOMING_TMP=/smartmet/data/incoming/ecmwf/$RT_DATE/$RT_HOUR


# Different MODEL_TYPE for 06/18z
if [ $RT_HOUR -eq 06 ] || [ $RT_HOUR -eq 18 ]
 then
  MODEL_TYPE=scda
 else
  MODEL_TYPE=oper
fi

# Use sync command to download data from s3 bucket
time aws s3 sync --exclude "*" --include "*grib2" --no-sign-request s3://ecmwf-forecasts/${RT_DATE}/${RT_HOUR}z/${MODEL_PRODUCER}/${MODEL_VERSION}/${MODEL_TYPE}/ ${INCOMING_TMP}/