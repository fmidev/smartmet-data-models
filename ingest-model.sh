#!/bin/sh 
#
# Finnish Meteorological Institute / Mikko Rauhala (2019)
#
# SmartMet Data Ingestion Module
#
# Usage: ./ingest-model.sh -m modelname
#

log() {
    echo "$(date -u +%H:%M:%S) $1"
}

# Set base directory
if [ -d /smartmet ]; then
    BASE=/smartmet
else
    BASE=$HOME/smartmet
fi

if [ $# -eq 0 ]; then
    echo "OPTIONS\n  -m arg\tmodel\n  -a arg\tarea\n  -t arg\treference time (yyyymmddThh)"
    exit 1
fi

# Parse options
while getopts  "a:dm:p:t:" flag
do
    case "$flag" in
	a) AREA=$OPTARG;;
	m) MODEL=$OPTARG;;
    p) PROJECTION=$OPTARG;;
    t) RT=$OPTARG;;
    d) DEBUG=1
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
    log "Neither ${MODEL}-${AREA}.cnf nor ${MODEL}.cnf found in directory $BASE/cnf/data/"   
    exit 1
fi

LOGFILE=$BASE/logs/data/${MODEL}_${AREA}_$(date -u +%H).log

# Use log file if not run interactively
if [ $TERM = "dumb" ]; then
    exec &> $LOGFILE
fi

if [ -z "$PROJECTION" ]; then
    PROJECTION=""
else
    PROJECTION="-P $PROJECTION"
fi

if [ -z "$CROP" ]; then
    CROP=""
else
    CROP="-G $CROP"
fi


CONVERT_OPTIONS="$CROP $PROJECTION -C"

if [ -s $BASE/run/data/${MODEL}/bin/update.sh ]; then
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
else
    RT=$(date +%s -d "$RT")
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


#
# Distribute files if valid
# Globals: $TMP
# Arguments: outputfile with path
#
distribute() {
    local TMPFILE=$1
    local OUTFILE=$2
    
    if [ -s $TMPFILE ]; then
	    log "Testing: $(basename $OUTFILE)"
	    if qdstat $TMPFILE; then
            log "Creating directory: $(dirname $OUTFILE)"
            mkdir -p $(dirname $OUTFILE)
            log  "Compressing: $(basename $OUTFILE)"
            lbzip2 -k $TMPFILE
            log "Moving: $(basename $OUTFILE) to $OUTFILE"
            mv -f $TMPFILE $OUTFILE
            log "Moving: $(basename $OUTFILE).bz2 to $EDITOR/"
            mv -f $TMPFILE.bz2 $EDITOR/
	    else
            log "File $TMPFILE is not valid qd file."
    	fi
    fi
}

convert() {
    local MODEL=$1
    local MODEL_ID=$2
#    local OPTIONS=$3
    local GRB=$3
    local SQD=$4

    local OPTIONS=""
    
    if [[ $SQD == *"surface"* ]]; then
        LEVEL=surface
        LEVEL_ID=1
    elif [[ $SQD == *"pressure"* ]]; then
        LEVEL=pressure
        LEVEL_ID=100

       	if [ $(grib_get  -p shortName -w  typeOfLevel=isobaricInhPa -w shortName=q $GRB | wc -l) -gt 0 ]; then
            OPTIONS="$OPTIONS -r 12";
            log "Enabling RH calculations from Q"
	    fi
    fi

    PRODUCER="${MODEL_ID},${MODEL^^} ${LEVEL^}"

    log "Creating directory: $(dirname $SQD)"
    mkdir -p $(dirname $SQD)
    log "Converting $LEVEL grib files to $(basename $SQD)"
    gribtoqd -d -t -L $LEVEL_ID \
    -c $CNF/${MODEL}-${LEVEL}.cnf \
    -p "$PRODUCER" \
    $OPTIONS -o $SQD $GRB 
    log "Converted surface grib files to $(basename $SQD)"
    qdinfo -P -T -x -z -r -q $SQD
#\$PROJECTION $CROP\

    # Post Process
    if [ -s $SQD ] && [ -s $CNF/${MODEL}-${LEVEL}.st ]; then
        log "Post processing: $(basename $SQD)"
	    qdscript -a 355 -i $SQD $CNF/${MODEL}-${LEVEL}.st > ${SQD}.tmp
	    mv -f  ${SQD}.tmp $SQD
	    qdinfo -P -q $SQD
    fi

}

#
# Print Information
# 
echo "Model Reference Time: $RT_ISO"
echo "Projection: $PROJECTION"
echo "Temporary directory: $TMP"
eval echo "Input data: $MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_SFC"
echo "Output directory: $OUT"
echo "Output surface level file: $(basename $OUTFILE_SFC)"
echo "Output pressure level file: $(basename $OUTFILE_PL)"


if [ -s $OUTFILE_SFC ] && [ $(eval gribstepcount "$MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_SFC") -eq $(qdstepcount $OUTFILE_SFC) ]; then
    log "$(basename $OUTFILE_SFC) is complete"
    SFCDONE=1
else
    log "$(basename $OUTFILE_SFC) is incomplete"
fi

if [ -s $OUTFILE_PL ] && [ $(eval gribstepcount "$MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_PL") -eq $(qdstepcount $OUTFILE_PL) ]; then
    log "$(basename $OUTFILE_PL) is complete"
    PLDONE=1
else
    log "$(basename $OUTFILE_PL) is incomplete"
fi


#
# Surface Data
#
if [ -z $SFCDONE ]; then
    TMPFILE_SFC=$TMP/$(basename $OUTFILE_SFC)

    eval convert $MODEL $MODEL_ID "$MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_SFC" $TMPFILE_SFC

    if [ -s $TMPFILE_SFC ]; then
	log "Creating Wind and Weather objects: $(basename $OUTFILE_SFC)"
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
    eval convert $MODEL $MODEL_ID "$MODEL_RAW_ROOT$MODEL_RAW_DIR/$MODEL_RAW_PL" $TMPFILE_PL
    if [ -z $DEBUG ]; then
        distribute $TMPFILE_PL $OUTFILE_PL
    fi # debug
fi # pressure

#
# Clean
#
rmdir $TMP
