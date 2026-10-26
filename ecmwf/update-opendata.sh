#!/bin/bash
#
# ECMWF open data download for SmartMet ingestion (IFS HRES, stream oper).
#
# Downloads only the selected fields from the ECMWF open data service using
# the .index file next to every GRIB file and HTTP byte ranges, so it needs
# nothing but curl and jq (no awscli, no python).
#
# Sources are tried in OPENDATA_SOURCES order. AWS (s3://ecmwf-forecasts) is
# preferred because it is usually faster than data.ecmwf.int from locations
# with a slow connection to the ECMWF data centre. A later source is only
# used when it has had the data for OPENDATA_FALLBACK_DELAY minutes and the
# earlier ones still do not, or when downloading a step from the earlier
# source has kept failing (e.g. S3 throttling) for that long.
#
# Meant to be polled from cron through ingest-model.sh
# (UPDATE_SCRIPT=update-opendata.sh). A run with nothing new to do costs one
# S3 listing request. A run stops starting new steps after
# OPENDATA_MAX_RUNTIME minutes; the next run continues. Step files are staged under $INCOMING/.opendata/<RT>/
# and moved into $INCOMING only when the whole cycle is complete, so
# ingest-model.sh never converts a partial cycle. Area cropping is done by
# ingest-model.sh when converting to querydata (CROP in ecmwf.cnf).
#
# Usage: update-opendata.sh [-c cnf] [-t YYYYMMDDHH] [-n]
#   -c  configuration file (default: $BASE/cnf/data/ecmwf.cnf)
#   -t  process this cycle instead of the newest available one
#   -n  dry run: fetch only .index files and report what would be downloaded
#
# https://www.ecmwf.int/en/forecasts/datasets/open-data
#
set -euo pipefail

START=$(date +%s)

if [ -d /smartmet ]; then
    BASE=/smartmet
else
    BASE=$HOME/smartmet
fi

CNF=$BASE/cnf/data/ecmwf.cnf
FORCE_RT=""
DRYRUN=0

while getopts "c:nt:" flag; do
    case "$flag" in
        c) CNF=$OPTARG ;;
        n) DRYRUN=1 ;;
        t) FORCE_RT=$OPTARG ;;
        *) echo "Usage: $0 [-c cnf] [-t YYYYMMDDHH] [-n]" >&2; exit 1 ;;
    esac
done

log() {
    printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

if [ ! -s "$CNF" ]; then
    log "ERROR: configuration file $CNF not found"
    exit 1
fi
# shellcheck source=/dev/null
. "$CNF"

# ---------------------------------------------------------------------------
# Settings (override in ecmwf.cnf). An empty *_PARAMS disables that level type.
# ---------------------------------------------------------------------------
OPENDATA_SOURCES=${OPENDATA_SOURCES:-"aws ecmwf"}
OPENDATA_RESOL=${OPENDATA_RESOL:-0p25}
OPENDATA_CYCLES=${OPENDATA_CYCLES:-"00 06 12 18"}
OPENDATA_STEPS=${OPENDATA_STEPS:-"0:144:3,150:240:6"}
OPENDATA_SFC_PARAMS=${OPENDATA_SFC_PARAMS-"2t,2d,msl,10u,10v,tp,tcc,mucape,ptype,sd,z"}
OPENDATA_PL_PARAMS=${OPENDATA_PL_PARAMS-"gh,t,r,u,v,w"}
OPENDATA_PL_LEVELS=${OPENDATA_PL_LEVELS:-"1000,925,850,700,600,500,400,300,250,200,150,100,50"}
OPENDATA_JOBS=${OPENDATA_JOBS:-2}
OPENDATA_RETRIES=${OPENDATA_RETRIES:-8}
OPENDATA_FALLBACK_DELAY=${OPENDATA_FALLBACK_DELAY:-60}
OPENDATA_MAX_RUNTIME=${OPENDATA_MAX_RUNTIME:-30}
INCOMING=${OPENDATA_INCOMING:-${MODEL_RAW_ROOT:-$BASE/data/incoming/ecmwf}}

# Last step ECMWF publishes per cycle (same for 0p1 and 0p25)
MAXSTEP_00_12=360
MAXSTEP_06_18=144

case "$OPENDATA_RESOL" in
    0p1|0p25) ;;
    *) log "ERROR: OPENDATA_RESOL must be 0p1 or 0p25, got '$OPENDATA_RESOL'"; exit 1 ;;
esac

for v in OPENDATA_SFC_PARAMS OPENDATA_PL_PARAMS OPENDATA_PL_LEVELS; do
    if [[ ! ${!v} =~ ^[A-Za-z0-9_,\ ]*$ ]]; then
        log "ERROR: $v contains invalid characters: '${!v}'"
        exit 1
    fi
done

if [ -z "$OPENDATA_SFC_PARAMS" ] && [ -z "$OPENDATA_PL_PARAMS" ]; then
    log "ERROR: both OPENDATA_SFC_PARAMS and OPENDATA_PL_PARAMS are empty"
    exit 1
fi

for tool in curl jq flock; do
    command -v $tool >/dev/null || { log "ERROR: $tool not installed"; exit 1; }
done

# Comma-separated list -> JSON array of strings
csv_json() {
    jq -cn --arg s "$1" '$s | split(",") | map(gsub(" "; "")) | map(select(length > 0))'
}

# Steps spec "0:144:3,150:240:6" or "0,6,12" -> sorted unique step list
expand_steps() {
    local tok s
    local -a toks out=()
    IFS=',' read -ra toks <<< "$1"
    for tok in "${toks[@]}"; do
        tok=${tok// /}
        if [[ $tok =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]] && [ "${BASH_REMATCH[3]}" -gt 0 ]; then
            for ((s = BASH_REMATCH[1]; s <= BASH_REMATCH[2]; s += BASH_REMATCH[3])); do
                out+=("$s")
            done
        elif [[ $tok =~ ^[0-9]+$ ]]; then
            out+=("$tok")
        elif [ -n "$tok" ]; then
            log "ERROR: invalid token '$tok' in OPENDATA_STEPS"
            exit 1
        fi
    done
    printf '%s\n' "${out[@]}" | sort -nu
}

source_url() {
    case "$1" in
        aws)    echo "https://ecmwf-forecasts.s3.eu-central-1.amazonaws.com" ;;
        ecmwf)  echo "https://data.ecmwf.int/forecasts" ;;
        http://*|https://*) echo "${1%/}" ;;
        *) log "ERROR: unknown source '$1' in OPENDATA_SOURCES"; exit 1 ;;
    esac
}

# At 0p1 surface and pressure levels are separate files, at 0p25 both are in
# one combined file.
file_suffix() {
    if [ "$OPENDATA_RESOL" = 0p1 ]; then
        echo "-$1"
    fi
}

# Path of a step file without extension, relative to the source root
# Arguments: RT (YYYYMMDDHH), step, level group (sfc|pl)
key_base() {
    local d=${1:0:8} h=${1:8:2}
    echo "$d/${h}z/ifs/$OPENDATA_RESOL/oper/${d}${h}0000-${2}h-oper-fc$(file_suffix "$3")"
}

CURL_OPTS=(-fsS --retry "$OPENDATA_RETRIES" --retry-connrefused --connect-timeout 30
           --speed-limit 1000 --speed-time 60)

LEVGROUPS=()
[ -n "$OPENDATA_SFC_PARAMS" ] && LEVGROUPS+=(sfc)
[ -n "$OPENDATA_PL_PARAMS" ] && LEVGROUPS+=(pl)

SFC_JSON=$(csv_json "$OPENDATA_SFC_PARAMS")
PL_JSON=$(csv_json "$OPENDATA_PL_PARAMS")
LEV_JSON=$(csv_json "$OPENDATA_PL_LEVELS")

read -ra SOURCES <<< "$OPENDATA_SOURCES"
mapfile -t ALL_STEPS < <(expand_steps "$OPENDATA_STEPS")

# Steps requested for a cycle, capped to what ECMWF publishes for that hour
cycle_steps() {
    local h=${1:8:2} max=$MAXSTEP_00_12 s
    case "$h" in 06|18) max=$MAXSTEP_06_18 ;; esac
    for s in "${ALL_STEPS[@]}"; do
        [ "$s" -le "$max" ] && echo "$s"
    done
    return 0
}

# Steps of a cycle available on AWS: one S3 listing, a step counts when the
# .index of every needed level group is present.
# Arguments: RT, needed steps...
aws_available() {
    local rt=$1; shift
    local base prefix xml s g ok
    base=$(source_url aws)
    prefix=$(dirname "$(key_base "$rt" 0 sfc)")/
    xml=$(curl "${CURL_OPTS[@]}" "$base/?list-type=2&prefix=$prefix") || return 0
    if [[ $xml == *"<IsTruncated>true</IsTruncated>"* ]]; then
        log "WARNING: S3 listing of $prefix truncated, some steps may be missed"
    fi
    for s in "$@"; do
        ok=1
        for g in "${LEVGROUPS[@]}"; do
            [[ $xml == *"<Key>$(key_base "$rt" "$s" "$g").index</Key>"* ]] || { ok=0; break; }
        done
        [ $ok = 1 ] && echo "$s"
    done
    return 0
}

# Sources without a listing: the cycle counts as available when the .index of
# the last needed step exists (ECMWF publishes a cycle all at once).
# Arguments: source, RT, needed steps...
http_available() {
    local src=$1 rt=$2; shift 2
    local base last g
    base=$(source_url "$src")
    last=${*: -1}
    for g in "${LEVGROUPS[@]}"; do
        curl -fsS -I --connect-timeout 30 -o /dev/null \
            "$base/$(key_base "$rt" "$last" "$g").index" 2>/dev/null || return 0
    done
    printf '%s\n' "$@"
}

source_available() {
    if [ "$1" = aws ]; then
        shift 1
        aws_available "$@"
    else
        http_available "$@"
    fi
}

# Download the selected fields of one step into $WORK as
# ifs_<group>_<RT>_<SSS>.grib2.pending and mark the step done.
# Arguments: step, source
fetch_step() {
    local step=$1 src=$2
    local base sss g suffix idx url sel nfields nranges bytes tmp cfg i s e part pending
    base=$(source_url "$src")
    sss=$(printf '%03d' "$step")
    tmp=$WORK/tmp_$sss
    rm -rf "$tmp"
    mkdir -p "$tmp"

    for g in "${LEVGROUPS[@]}"; do
        suffix=$(file_suffix "$g")
        url="$base/$(key_base "$RT" "$step" "$g")"
        idx=$tmp/index$suffix
        if [ ! -s "$idx" ]; then
            if ! curl "${CURL_OPTS[@]}" -o "$idx" "$url.index" || [ "$(head -c1 "$idx")" != "{" ]; then
                log "ERROR: step $sss: cannot fetch $url.index"
                return 1
            fi
        fi

        # R <offset> <length> for wanted fields, M <param[/level]> for
        # requested fields missing from the index
        sel=$(jq -r -s --arg grp "$g" --argjson params "$( [ "$g" = sfc ] && echo "$SFC_JSON" || echo "$PL_JSON")" \
                --argjson levels "$LEV_JSON" '
            (if $grp == "sfc" then ["sfc", "sol"] else ["pl"] end) as $lts
            | [ .[] | select(.levtype as $x | any($lts[]; . == $x))
                    | select(.param as $x | any($params[]; . == $x))
                    | select($grp == "sfc" or (.levelist as $x | any($levels[]; . == $x))) ] as $hit
            | ($hit | sort_by(._offset)[] | "R \(._offset) \(._length)"),
              (if $grp == "sfc" then
                   $params[] | select(. as $p | any($hit[]; .param == $p) | not) | "M \(.)"
               else
                   $params[] as $p | $levels[] as $l
                   | select(any($hit[]; .param == $p and .levelist == $l) | not) | "M \($p)/\($l)"
               end)' "$idx")

        grep '^M ' <<< "$sel" | sed "s/^M /$g /" >> "$WORK/missing" || true
        nfields=$(grep -c '^R ' <<< "$sel" || true)
        if [ "$nfields" -eq 0 ]; then
            log "WARNING: step $sss: none of the requested $g fields found"
            continue
        fi

        # Merge adjacent fields into one range: fewer requests
        grep '^R ' <<< "$sel" | awk '
            { if (n && $2 == end) end = $2 + $3
              else { if (n) print start, end - 1; start = $2; end = $2 + $3; n = 1 } }
            END { if (n) print start, end - 1 }' > "$tmp/ranges_$g"
        nranges=$(wc -l < "$tmp/ranges_$g")
        bytes=$(awk '{ b += $2 - $1 + 1 } END { print b }' "$tmp/ranges_$g")

        if [ "$DRYRUN" = 1 ]; then
            echo "DRYRUN $sss $g $nfields $nranges $bytes"
            continue
        fi

        # One curl run per file reuses the connection for all ranges
        cfg=$tmp/curl_$g.cfg
        # Give up the step at the first failed range, the rest would fail too
        echo "fail-early" > "$cfg"
        i=0
        while read -r s e; do
            [ $i -gt 0 ] && echo "next" >> "$cfg"
            printf 'url = "%s.grib2"\noutput = "%s/part_%s_%05d"\nrange = "%s-%s"\n' \
                "$url" "$tmp" "$g" "$i" "$s" "$e" >> "$cfg"
            printf 'fail\nsilent\nshow-error\nretry = %s\nretry-connrefused\nconnect-timeout = 30\nspeed-limit = 1000\nspeed-time = 60\n' \
                "$OPENDATA_RETRIES" >> "$cfg"
            i=$((i + 1))
        done < "$tmp/ranges_$g"

        if ! curl -K "$cfg"; then
            log "ERROR: step $sss: download of $g fields from $src failed"
            return 1
        fi

        # Servers that ignore Range return the whole file: check every size
        i=0
        while read -r s e; do
            part=$(printf '%s/part_%s_%05d' "$tmp" "$g" "$i")
            if [ "$(stat -c %s "$part" 2>/dev/null || echo 0)" -ne $((e - s + 1)) ]; then
                log "ERROR: step $sss: $(basename "$part") has wrong size"
                return 1
            fi
            i=$((i + 1))
        done < "$tmp/ranges_$g"

        pending=$WORK/ifs_${g}_${RT}_${sss}.grib2.pending
        cat "$tmp"/part_"${g}"_* > "$pending.part"
        if command -v grib_count >/dev/null && [ "$(grib_count "$pending.part")" -ne "$nfields" ]; then
            log "ERROR: step $sss: expected $nfields $g GRIB messages, got $(grib_count "$pending.part")"
            rm -f "$pending.part"
            return 1
        fi
        mv -f "$pending.part" "$pending"
        log "Step $sss $g: $nfields fields, $nranges requests, $((bytes / 1024 / 1024)) MB from $src"
    done

    rm -rf "$tmp"
    [ "$DRYRUN" = 1 ] || touch "$WORK/done_$sss"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
STATE=$INCOMING/.opendata
mkdir -p "$STATE"
exec 9> "$STATE/lock"
if ! flock -n 9; then
    log "Another update-opendata.sh is still running, nothing to do"
    exit 0
fi

# State of cycles older than the given one is no longer needed: either
# complete (only the newest marker matters) or replaced by a newer cycle
# before completing (staged files, partial downloads)
cleanup_older() {
    local d c
    [ "$DRYRUN" = 0 ] || return 0
    for d in "$STATE"/20*/; do
        d=${d%/}
        c=$(basename "$d")
        [[ $c =~ ^[0-9]{10}$ ]] && [ "$c" -lt "$1" ] || continue
        log "Removing state of older cycle $c ($(du -sh "$d" | cut -f1))"
        rm -rf "$d"
    done
}

# Candidate cycles, newest first
CANDIDATES=()
if [ -n "$FORCE_RT" ]; then
    [[ $FORCE_RT =~ ^[0-9]{8}(00|06|12|18)$ ]] || { log "ERROR: -t must be YYYYMMDDHH (HH 00/06/12/18)"; exit 1; }
    CANDIDATES=("$FORCE_RT")
else
    slot=$(( $(date -u +%s) / 21600 * 21600 ))
    for i in 0 1 2 3 4; do
        rt=$(date -u -d@$((slot - i * 21600)) +%Y%m%d%H)
        [[ " $OPENDATA_CYCLES " == *" ${rt:8:2} "* ]] && CANDIDATES+=("$rt")
    done
fi

RT=""
declare -A AVAIL=()
for rt in "${CANDIDATES[@]}"; do
    if [ -e "$STATE/$rt/complete" ]; then
        log "Cycle $rt ($OPENDATA_RESOL) already complete, nothing to do"
        cleanup_older "$rt"
        exit 0
    fi
    mapfile -t steps < <(cycle_steps "$rt")
    [ ${#steps[@]} -gt 0 ] || continue
    found=0
    for src in "${SOURCES[@]}"; do
        AVAIL[$src]=$(source_available "$src" "$rt" "${steps[@]}" | tr '\n' ' ')
        [ -n "${AVAIL[$src]// /}" ] && found=1
    done
    if [ $found = 1 ]; then
        RT=$rt
        break
    fi
    log "Cycle $rt ($OPENDATA_RESOL) not available yet"
done

if [ -z "$RT" ]; then
    log "No new cycle available"
    exit 0
fi

WORK=$STATE/$RT
mkdir -p "$WORK"
cleanup_older "$RT"
mapfile -t STEPS < <(cycle_steps "$RT")
log "Cycle $RT, resolution $OPENDATA_RESOL, ${#STEPS[@]} steps, sources: $OPENDATA_SOURCES"

# Later sources are used only after they have had the cycle for
# OPENDATA_FALLBACK_DELAY minutes, giving AWS time to catch up.
source_ready() {
    local idx=$1 seen=$WORK/seen_$1 age
    [ "$idx" -eq 0 ] && return 0
    [ -e "$seen" ] || touch "$seen"
    age=$(( ($(date +%s) - $(stat -c %Y "$seen")) / 60 ))
    if [ "$age" -lt "$OPENDATA_FALLBACK_DELAY" ]; then
        log "Waiting for ${SOURCES[0]}: ${SOURCES[$idx]} usable in $((OPENDATA_FALLBACK_DELAY - age)) min"
        return 1
    fi
}

# True when downloading the step from source idx has kept failing for
# OPENDATA_FALLBACK_DELAY minutes (fail_<SSS>_<idx> is touched on the first
# failure)
failing_long() {
    local fail=$WORK/fail_$1_$2
    [ -e "$fail" ] && [ $(( ($(date +%s) - $(stat -c %Y "$fail")) / 60 )) -ge "$OPENDATA_FALLBACK_DELAY" ]
}

JOBS=()
declare -A READY=()
todo=0
for s in "${STEPS[@]}"; do
    sss=$(printf '%03d' "$s")
    [ -e "$WORK/done_$sss" ] && continue
    todo=$((todo + 1))
    pick="" retry_pick="" skipped=0
    for i in "${!SOURCES[@]}"; do
        src=${SOURCES[$i]}
        [[ " ${AVAIL[$src]} " == *" $s "* ]] || continue
        # An earlier source has failed long enough: no catch-up wait
        if [ $skipped = 0 ]; then
            if [ -z "${READY[$i]:-}" ]; then
                if source_ready "$i"; then READY[$i]=1; else READY[$i]=0; fi
            fi
            [ "${READY[$i]}" = 1 ] || continue
        fi
        if failing_long "$sss" "$i"; then
            [ -n "$retry_pick" ] || retry_pick=$i
            skipped=1
            continue
        fi
        pick=$i
        break
    done
    # Every usable source keeps failing: keep retrying the preferred one
    pick=${pick:-$retry_pick}
    [ -n "$pick" ] || continue
    if [ "$skipped" = 1 ] && [ "$pick" != "$retry_pick" ]; then
        log "Step $sss: ${SOURCES[$retry_pick]} failing for over $OPENDATA_FALLBACK_DELAY min, using ${SOURCES[$pick]}"
    fi
    JOBS+=("$s ${SOURCES[$pick]} $pick")
done
log "$((${#STEPS[@]} - todo))/${#STEPS[@]} steps done, ${#JOBS[@]} to download now"

if [ ${#JOBS[@]} -gt 0 ]; then
    export -f fetch_step source_url file_suffix key_base log
    export RT WORK DRYRUN OPENDATA_RESOL OPENDATA_RETRIES SFC_JSON PL_JSON LEV_JSON
    export DEADLINE=$((START + OPENDATA_MAX_RUNTIME * 60))
    export LEVGROUPS_STR="${LEVGROUPS[*]}" CURL_OPTS_STR="${CURL_OPTS[*]}"
    rm -f "$WORK/missing"
    printf '%s\n' "${JOBS[@]}" | xargs -P "$OPENDATA_JOBS" -L 1 bash -c '
        set -uo pipefail
        read -ra LEVGROUPS <<< "$LEVGROUPS_STR"
        read -ra CURL_OPTS <<< "$CURL_OPTS_STR"
        if [ "$(date +%s)" -ge "$DEADLINE" ]; then
            echo "SKIP $1"
            exit 0
        fi
        if ! fetch_step "$1" "$2"; then
            fail=$WORK/fail_$(printf "%03d" "$1")_$3
            [ "$DRYRUN" = 1 ] || [ -e "$fail" ] || touch "$fail"
            # The next attempt starts the step from scratch
            rm -rf "$WORK/tmp_$(printf "%03d" "$1")"
            echo "FAIL $1"
        fi' _ > "$WORK/jobs.out" || true
    grep -v '^DRYRUN \|^SKIP \|^FAIL ' "$WORK/jobs.out" || true

    nfail=$(grep -c '^FAIL ' "$WORK/jobs.out" || true)
    nskip=$(grep -c '^SKIP ' "$WORK/jobs.out" || true)
    [ "$nfail" -eq 0 ] || log "WARNING: $nfail steps failed, retrying on next run"
    [ "$nskip" -eq 0 ] || log "WARNING: OPENDATA_MAX_RUNTIME $OPENDATA_MAX_RUNTIME min reached, $nskip steps left for next run"

    if [ "$DRYRUN" = 1 ]; then
        awk '/^DRYRUN/ { f += $4; r += $5; b += $6 }
             END { printf "Dry run: %d fields, %d requests, %.1f MB in total\n", f, r, b / 1048576 }' "$WORK/jobs.out"
    fi
    if [ -s "$WORK/missing" ]; then
        sort "$WORK/missing" | uniq -c | while read -r n g f; do
            log "WARNING: $g $f not in open data index for $n of ${#JOBS[@]} steps"
        done
    fi
    rm -f "$WORK/jobs.out"
fi

[ "$DRYRUN" = 1 ] && exit 0

# Publish the cycle only when every step is done
for s in "${STEPS[@]}"; do
    if [ ! -e "$WORK/done_$(printf '%03d' "$s")" ]; then
        log "Cycle $RT incomplete, continuing on next run"
        exit 0
    fi
done

for f in "$WORK"/*.grib2.pending; do
    [ -e "$f" ] || continue
    mv -f "$f" "$INCOMING/$(basename "${f%.pending}")"
done
rm -rf "$WORK"/tmp_* "$WORK"/done_* "$WORK"/fail_* "$WORK"/seen_* "$WORK/missing"
touch "$WORK/complete"
log "Cycle $RT complete, files in $INCOMING"
