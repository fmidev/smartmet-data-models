#!/bin/sh
# Finnish Meteorological Institute / Mikko Rauhala (2019-2023)
# SmartMet Data Ingestion Module
#
# Usage: ./ingest-model.sh -m modelname
#

log() {
    local level=$1
    local message=$2
    local timestamp=$(date -u +%H:%M:%S)
    
    case $level in
        INFO)
            printf '\033[0;32m[%s] INFO: %s\033[0m\n' "$timestamp" "$message"
            ;;
        ERROR)
            printf '\033[0;31m[%s] ERROR: %s\033[0m\n' "$timestamp" "$message"
            ;;
        *)
            printf '[%s] %s\n' "$timestamp" "$message"
            ;;
    esac
}


logold() {
    printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$1"
}

# Set base directory
if [ -d /smartmet ]; then
    BASE=/smartmet
else
    BASE=$HOME/smartmet
fi

if [ $# -eq 0 ]; then
    echo "OPTIONS"
    printf "\t%s\t%s\n" "-m model" ""
    printf "\t%s\t%s\n" "-a area" ""
    printf "\t%s\t%s\n" "-t yyyymmddThh" "reference time"
    printf "\t%s\t%s\n" "-i input" "input grib file (over rides reference time)"
    printf "\t%s\t\t%s\n" "-d" "debug, do not distribute"
    printf "\t%s\t\t%s\n" "-f" "force"
    exit 1
fi

# Parse options
while getopts  "a:dfi:m:p:t:" flag
do
    case "$flag" in
	a) AREA=$OPTARG;;
	m) MODEL=$OPTARG;;
	p) PROJECTION=$OPTARG;;
	t) RT=$(date +%s -d "$OPTARG");;
    i) IN=$OPTARG;;
	d) DEBUG=1;;
	f) FORCE=1;;
    esac
done

# Defaults
if [ -z "$MODEL" ]; then
    MODEL=model
fi

if [ -z "$AREA" ]; then
    AREA=world
fi

# Load configuration file
# User area configuration if available model-area.cnf
# Default to model.cnf
if [ -s $BASE/cnf/data/${MODEL}-${AREA}.cnf ]; then
    . $BASE/cnf/data/${MODEL}-${AREA}.cnf
elif [ -s $BASE/cnf/data/${MODEL}.cnf ]; then
    . $BASE/cnf/data/${MODEL}.cnf
else
    log ERROR "Neither ${MODEL}-${AREA}.cnf nor ${MODEL}.cnf found in directory $BASE/cnf/data/"
    exit 1
fi

LOGFILE=$BASE/logs/data/${MODEL}_${AREA}_$(date -u +%H).log

# Use log file if not run interactively
if [ $TERM = "dumb" ]; then
    exec &> $LOGFILE
fi

CONVERT_OPTIONS="$CONVERT_OPTIONS ${CROP:+"-G $CROP"} ${PROJECTION:+"-P $PROJECTION"}"

if [ -s $BASE/run/data/${MODEL}/bin/update.sh ]; then
    log INFO "Running $BASE/run/data/${MODEL}/bin/update.sh"
    $BASE/run/data/${MODEL}/bin/update.sh
fi

latest() {
    DIR=$1
    NAME=$2
    FILE=$(find $DIR -name "$NAME" -type f -printf '%T@ %P\n' | sort -n | awk '{print $2}'|tail -1)
    date -u +%s -d "$(grib_get -F %04d -p dataDate:i,dataTime:i $DIR/$FILE | sort -nu | tail -1 )"
}



# Model Reference Time
if [ -z "$RT" ]; then
    RT=$(eval latest $MODEL_RAW_ROOT $MODEL_RAW_MASK)
    if [ -z "$RT" ]; then
        log ERROR "No data available in $MODEL_RAW_ROOT"
        exit 1
    fi
fi

RT_HOUR=`date -u -d@$RT +%H`
RT_DATE_MMDD=`date -u -d@$RT +%Y%m%d`
RT_DATE_MMDDHH=`date -u -d@$RT +%m%d%H`
RT_DATE_DDHH=`date -u -d@$RT +%d%H00`
RT_DATE_DDHHMM=`date -u -d@$RT +%d%H00`
RT_DATE_HH=`date -u -d@$RT +%Y%m%d%H`
RT_DATE_HHMM=`date -u -d@$RT +%Y%m%d%H%M`
RT_YYMMDD_HHMM=`date -u -d@$RT +%y%m%d%H%M`
RT_DATE_HHMMSS=`date -u -d@$RT +%Y%m%d%H%M%S`
RT_ISO=`date -u -d@$RT +%Y-%m-%dT%H:%M:%SZ`

OUT=$BASE/data/$MODEL/$AREA
CNF=$BASE/run/data/$MODEL/cnf
EDITOR=$BASE/editor/in
TMP=$BASE/tmp/data/${MODEL}_${AREA}_${RT_DATE_HHMM}
mkdir -p $TMP

if [ -z "$IN" ]; then
    eval INFILE_SFC="$MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_SFC"
    eval INFILE_PL="$MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_PL"
    eval INFILE_ML="$MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_ML"
else
    INFILE_SFC="$IN"
    INFILE_PL="$IN"
    INFILE_ML="$IN"
    RT=$(date -u +%s -d "$(grib_get -F %04d -p dataDate:i,dataTime:i $IN | sort -nu | tail -1 )")
    echo "foo: $RT"
fi

OUTNAME=${RT_DATE_HHMM}_${MODEL}_${AREA}
OUTFILE_SFC=$OUT/surface/querydata/${OUTNAME}_surface.sqd
OUTFILE_PL=$OUT/pressure/querydata/${OUTNAME}_pressure.sqd
OUTFILE_ML=$OUT/hybrid/querydata/${OUTNAME}_hybrid.sqd


gribstepcount() {
    local FILES=$1
    grib_get -p startStep $FILES|sort -nu|wc -l
}

qdstepcount() {
    local FILE=$1
    qdinfo -t -q $FILE | grep Timesteps | cut -d= -f2| tr -d ' '
}

hasParameter() {
    local -r FILE=$1
    local -r LEVEL=$2
    local -r NAME=$3

    if [ $(grib_get -p shortName -w typeOfLevel=$LEVEL,shortName=$NAME $FILE | wc -l) -gt 0 ]; then
        return
    fi
    false
}

#
# Distribute files if valid
# Globals: $TMP
# Arguments: outputfile with path
#
distribute() {
    local -r TMPFILE=$1
    local -r OUTFILE=$(basename $2)
    local -r OUTDIR=$(dirname $2)
    local -r TIMESTAMP=$(date -u +%Y%m%d%H%M)
    local -r EDITORFILE="$EDITOR/${TIMESTAMP}_${OUTFILE}.bz2"

    if [ -s $TMPFILE ]; then
	    log INFO "Testing: $(basename $TMPFILE)"
	    if qdstat $TMPFILE; then
            log INFO "Creating directory: $OUTDIR"
            mkdir -p $OUTDIR
            log  INFO "Compressing: $(basename $TMPFILE)"
            pbzip2 -k $TMPFILE
            log INFO "Moving: $TMPFILE to $OUTDIR"
            mv -f $TMPFILE $OUTDIR
            log INFO "Moving: ${OUTFILE}.bz2 to $EDITORFILE"
            mv -f $TMPFILE.bz2 $EDITORFILE
	    else
            log ERROR "File $TMPFILE is not valid qd file."
    	fi
    fi
}

convert() {
    local MODEL=$1
    local MODEL_ID=$2
    local GRB=$3
    local SQD=$4

    local OPTIONS="$CONVERT_OPTIONS"

    if [[ $SQD == *"surface"* ]]; then
        LEVEL=surface
        LEVEL_ID=1
#       	if [ $(grib_get  -p shortName -w  typeOfLevel=heightAboveGround -w shortName=q $GRB | wc -l) -gt 0 ]; then
      	if hasParameter "$GRB" heightAboveGround q ; then
            OPTIONS="$OPTIONS -r 12";
            log INFO "Enabling RH calculations from Q for surface data."
        fi
    elif [[ $SQD == *"pressure"* ]]; then
        LEVEL=pressure
        LEVEL_ID=100

       	if hasParameter "$GRB" isobaricInhPa q ; then
            OPTIONS="$OPTIONS -r 12";
            log INFO "Enabling RH calculations from Q for pressure data."
        fi
    elif [[ $SQD == *"hybrid"* ]]; then
        LEVEL=hybrid
        LEVEL_ID=109

       	if hasParameter "$GRB" hybrid q; then
            OPTIONS="$OPTIONS -r 12";
            log INFO "Enabling RH calculations from Q for hybrid data."
        fi
    fi

    PRODUCER="${MODEL_ID},${MODEL^^} ${LEVEL^}"
    CNF_FILE="$CNF/${MODEL}-${LEVEL}.cnf"

    # Check if config file exists 
    if [ ! -s "$CNF_FILE" ]; then
        log ERROR "Config file '$CNF_FILE' does not exist or is empty"
        return 1
    fi

    log INFO "Creating directory: $(dirname $SQD)"
    mkdir -p $(dirname $SQD)
    log INFO "Converting ${MODEL^^} $LEVEL ($LEVEL_ID) grib files to $(basename $SQD)"
    gribtoqd -d -t -L $LEVEL_ID \
    -c $CNF_FILE \
    -p "$PRODUCER" \
    $OPTIONS -o $SQD $GRB
    log INFO "Converted surface grib files to $(basename $SQD)"
    qdinfo -P -T -x -z -r -q $SQD
}

process() {
    local SQD="$1"
    local LEVEL="$2"

    # Check if input file exists and script directory exists
    if [ ! -s "$SQD" ]; then
        log ERROR "Input file '$SQD' does not exist or is empty"
        return 2
    fi

    if [ -s $SQD ] && [ -d $CNF/st.$LEVEL.d ]; then
        for SCRIPT in $CNF/st.$LEVEL.d/*-*.st; do
            PAR=$(basename ${SCRIPT%.*}|cut -d- -f2)
            PARNAME=$(basename ${SCRIPT%.*}|cut -d- -f1)
            log INFO "Post process: $(basename $SQD) parameter $PAR"
            log INFO "Run: qdscript -A $PAR,$PARNAME -i $SQD $SCRIPT"
            qdscript -A $PAR,$PARNAME -i $SQD $SCRIPT > ${SQD}.tmp
            mv -f "${SQD}.tmp" "$SQD"
        done
        log INFO "Testing processed output: $SQD"
        qdstat "$SQD"
    fi
}

#
# Print Information
#
log INFO "Model: $MODEL"
log INFO "Area: $AREA"
log INFO "Reference Time: $RT_ISO"
log INFO "Projection: $PROJECTION"
log INFO "Temporary directory: $TMP"
echo ""

log INFO "INPUT"
log INFO "Input surface level file(s): $INFILE_SFC"
log INFO "Input pressure level file(s): $INFILE_PL"
log INFO "Input hybrid level file(s): $INFILE_ML"
echo ""

log INFO "OUTPUT"
log INFO "Output directory: $OUT"
log INFO "Output surface level file: $(basename $OUTFILE_SFC)"
log INFO "Output pressure level file: $(basename $OUTFILE_PL)"
log INFO "Output hybrid level file: $(basename $OUTFILE_ML)"
echo ""

if [ -z $FORCE ]; then
    if [ -s "$OUTFILE_SFC" ] && [ $(gribstepcount "$INFILE_SFC") -eq $(qdstepcount "$OUTFILE_SFC") ]; then
	    log INFO "$(basename "$OUTFILE_SFC") is complete"
	    SFCDONE=1
    else
	    log INFO "$(basename $OUTFILE_SFC) is incomplete"
    fi

    if [ -s "$OUTFILE_PL" ] && [ $(eval gribstepcount "$INFILE_PL") -eq $(qdstepcount "$OUTFILE_PL") ]; then
	    log INFO "$(basename "$OUTFILE_PL") is complete"
	    PLDONE=1
    else
	    log INFO "$(basename "$OUTFILE_PL") is incomplete"
    fi
else
    log INFO "Conversion forced from command line."
fi

#
# Surface Data
#
if [ -z $SFCDONE ]; then
    TMPFILE_SFC=$TMP/$(basename $OUTFILE_SFC)

    eval convert $MODEL $MODEL_ID "$MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_SFC" $TMPFILE_SFC
    process $TMPFILE_SFC surface

    if [ -s $TMPFILE_SFC ]; then
        log INFO "Creating Wind and Weather objects: $(basename $OUTFILE_SFC)"
        qdversionchange -a -t 1 -w 1 -i $TMPFILE_SFC 7 > ${TMPFILE_SFC}.tmp
        mv -f ${TMPFILE_SFC}.tmp $TMPFILE_SFC
        qdinfo -P -q $TMPFILE_SFC
    fi

    if [ -z $DEBUG ]; then
        distribute $TMPFILE_SFC $OUTFILE_SFC
    fi

fi # surface

#
# Pressure Levels
#
if [ -z $PLDONE ]; then
    TMPFILE_PL=$TMP/$(basename $OUTFILE_PL)
    eval echo convert $MODEL $MODEL_ID "$MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_PL" $TMPFILE_PL
    eval convert $MODEL $MODEL_ID "$MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_PL" $TMPFILE_PL
    if [ -z $DEBUG ]; then
        distribute $TMPFILE_PL $OUTFILE_PL
    fi # debug
fi # pressure

#
# Clean
#
trap 'rm -rf "$TMP"; log INFO "Cleanup complete"' EXIT

