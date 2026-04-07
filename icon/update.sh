#!/bin/bash

################################################################################
# ICON Data Download and Processing Script
################################################################################
# This script downloads ICON global weather model data from DWD OpenData and
# converts it from native icosahedral coordinates to regular lat-lon grid.
#
# The script performs the following steps:
# 1. Load configuration from icon.cnf
# 2. Calculate forecast cycle time
# 3. Create target grid definition for the specified area
# 4. Download ICON data files from DWD OpenData
# 5. Transform coordinates from icosahedral to lat-lon
# 6. Combine variables into consolidated GRIB2 files
# 7. Process surface elevation data
#
# Requirements:
#   - cdo
#
# L.Rontu, FMI, 2024-2026
# M.Hasu, FMI, 2026-02-20
################################################################################

set -euo pipefail


################################################################################
# Configuration Loading
################################################################################

load_config() {
    local possible_configs=(
       "/smartmet/cnf/data/icon-${AREA}.cnf"  "/smartmet/cnf/data/icon.cnf" 
    )
    
    local CONFIG_FILE=""
    for config in "${possible_configs[@]}"; do
        if [ -f "$config" ]; then
            CONFIG_FILE="$config"
            break
        fi
    done
    
    if [ -z "$CONFIG_FILE" ]; then
        echo "ERROR: Could not find icon.cnf configuration file"
        echo "Searched locations:"
        printf '  %s\n' "${possible_configs[@]}"
        exit 1
    fi
    
    echo "Loading configuration from: $CONFIG_FILE"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    echo "Processing ICON data for area: ${AREA}"
}

################################################################################
# Forecast Cycle Time Calculation
################################################################################

calculate_forecast_cycle() {
    # ICON forecasts are issued every 6 hours: 00z, 06z, 12z, 18z
    # Assumed ready times (UTC): 00z@04:00, 06z@10:00, 12z@16:00, 18z@22:00
    local STEP=6
    local RT
    RT=$(date -u +%s -d '-4 hours')
    RT=$(( RT / (STEP * 3600) * (STEP * 3600) ))
    RT_HOUR=$(date -u -d@"$RT" +%H)
    RT_DATE=$(date -u -d@"$RT" +%Y%m%d)
    
    export RT_HOUR RT_DATE
    echo "Forecast cycle: ${RT_DATE}${RT_HOUR}"
}

################################################################################
# Grid Increment Encoding
################################################################################

get_increment_string() {
    # Convert decimal increment (e.g., 0.125) to 4-digit string (e.g., 0125)
    local incr="$1"
    printf '%04d' "$(printf '%s' "$incr" | sed 's/^0\.//; s/\.//')"
}

################################################################################
# Target Grid Definition
################################################################################

build_target_grid() {
    local area="$1"
    local crop="$2"
    local incr="$3"
    local cinc
    cinc=$(get_increment_string "$incr")
    
    local target_dir="${ICOGEO}"
    mkdir -p "$target_dir"
    
    local target_file="${target_dir}/target_grid_${area}_${cinc}.txt"
    
    # Parse CROP: "lon_ll,lat_ll,lon_ur,lat_ur"
    IFS=',' read -r x1 y1 x2 y2 <<< "$crop"
    
    # Calculate grid dimensions using awk for float arithmetic
    awk -v x1="$x1" -v y1="$y1" -v x2="$x2" -v y2="$y2" -v inc="$incr" \
        -v target="$target_file" '
    BEGIN {
        # Ensure proper ordering
        if (x2 < x1) { t=x1; x1=x2; x2=t }
        if (y2 < y1) { t=y1; y1=y2; y2=t }
        
        # Calculate grid dimensions
        dx = (x2 - x1) / inc
        dy = (y2 - y1) / inc
        
        # Round to nearest integer
        nx = int(dx + 0.5)
        ny = int(dy + 0.5)
        
        # Sanity check
        eps = 1e-6
        if (dx - nx > eps || nx - dx > eps) {
            printf("ERROR: Longitude range not integer multiple of increment\n") > "/dev/stderr"
            printf("  Range: %.6f, Increment: %s, Ratio: %.6f\n", x2-x1, inc, dx) > "/dev/stderr"
            exit 2
        }
        if (dy - ny > eps || ny - dy > eps) {
            printf("ERROR: Latitude range not integer multiple of increment\n") > "/dev/stderr"
            printf("  Range: %.6f, Increment: %s, Ratio: %.6f\n", y2-y1, inc, dy) > "/dev/stderr"
            exit 2
        }
        
        xsize = nx + 1
        ysize = ny + 1
        
        # Write grid definition
        printf("# CDO grid description for %s\n", target) > target
        printf("gridtype = lonlat\n") > target
        printf("xsize = %d\n", xsize) > target
        printf("ysize = %d\n", ysize) > target
        printf("xfirst = %.6f\n", x1) > target
        printf("xinc = %s\n", inc) > target
        printf("yfirst = %.6f\n", y1) > target
        printf("yinc = %s\n", inc) > target
        
        printf("Created target grid: %s (xsize=%d, ysize=%d)\n", target, xsize, ysize)
    }'
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create target grid definition"
        return 1
    fi
    
    export TARGET_GRID_DESCRIPTION="$target_file"
    echo "Target grid: $TARGET_GRID_DESCRIPTION"
}

################################################################################
# Installation of ICON Grid Conversion Tools
################################################################################

install_icon_geoconv() {
    local cinc
    cinc=$(get_increment_string "$INCR")
    
    echo "=== Installing ICON grid conversion tools ==="
    
    mkdir -p "${ICOGEO}"

    # Download global weights
    local ICON_GLOB_WEIG="weights_icogl2world_${cinc}.nc"
    if [ ! -f "$ICOGEO/$ICON_GLOB_WEIG" ]; then
        cd ${ICOGEO}/..
        echo "Downloading global weights for increment ${cinc}..."
        local weights_archive="ICON_GLOBAL2WORLD_${cinc}_EASY.tar.bz2"
        if ! wget "https://opendata.dwd.de/weather/lib/cdo/${weights_archive}"; then
            echo "ERROR: Failed to download weights archive"
            return 1
        fi
        bunzip2 "${weights_archive}"
        tar xvf "ICON_GLOBAL2WORLD_${cinc}_EASY.tar"
        rm -f "ICON_GLOBAL2WORLD_${cinc}_EASY.tar"
    else
        echo "Global weights already exist: $ICON_GLOB_WEIG"
    fi

    cd $ICOGEO

    # Download ICON grid definition file
    local ICON_GRID_FILE="icon_grid_0026_R03B07_G.nc"
    if [ ! -f "$ICOGEO/$ICON_GRID_FILE" ]; then
        echo "Downloading ICON grid file..."
        if ! wget -O "$ICOGEO/${ICON_GRID_FILE}.bz2" \
            "https://opendata.dwd.de/weather/lib/cdo/${ICON_GRID_FILE}.bz2"; then
            echo "ERROR: Failed to download ICON grid file"
            return 1
        fi
        bunzip2 "${ICON_GRID_FILE}.bz2"
    else
        echo "ICON grid file already exists: $ICON_GRID_FILE"
    fi
        
    # Verify target grid description exists
    if [ ! -f "${TARGET_GRID_DESCRIPTION}" ]; then
        echo "ERROR: Target grid description not found: ${TARGET_GRID_DESCRIPTION}"
        return 1
    fi
    
    # Generate area-specific weights
    if [ ! -f "${WEIGHTS_FILE}" ]; then
        echo "Generating weights for ${AREA}..."
        if ! cdo gennn,"${TARGET_GRID_DESCRIPTION}" "${ICON_GRID_FILE}" "${WEIGHTS_FILE}"; then
            echo "ERROR: Failed to generate weights"
            return 1
        fi
        echo "Weights created: ${WEIGHTS_FILE}"
    else
        echo "Weights already exist: ${WEIGHTS_FILE}"
    fi
    
    echo "=== Grid conversion tools ready ==="
}

################################################################################
# Coordinate Transformation
################################################################################

transform_coordinates() {
    local in_file="$1"
    local out_file="$2"
    
    if [ ! -f "$in_file" ]; then
        echo "ERROR: Input file not found: $in_file"
        return 1
    fi
    
    echo "Transforming: $(basename "$in_file") -> $(basename "$out_file")"
    
    if ! cdo -f grb2 remap,"${TARGET_GRID_DESCRIPTION}","${WEIGHTS_FILE}" \
        "$in_file" "$out_file"; then
        echo "ERROR: Coordinate transformation failed"
        return 1
    fi
    
    return 0
}

################################################################################
# Data Download
################################################################################

download_icon_data() {
    local andate="${RT_DATE}${RT_HOUR}"
    local opendir="${OPENDATA_BASE_URL}/${RT_HOUR}"
    local dwdftp="${DWDFTP_URL}"
    local dwddir="${DWDFTP_DIR}/${RT_HOUR}"
    local work_dir="${ICOINC}/${RT_DATE}/${RT_HOUR}"

    mkdir -p "$work_dir"
    cd "$work_dir"

    echo "=== Downloading ICON data from DWD OpenData ==="
    echo "Source: $opendir for https, $dwdftp for ftp, the same data in both" 

    # Use fetch for curl via http
    fetch() {
        local url="$1"
        local out="$2"
        local part="${out}.part"

        [ -s "$out" ] && return 0

        local tries=6 delay=10
        for ((i=1; i<=tries; i++)); do
            echo "  -> (Try $i/$tries) $out"
            if curl -sS --ipv4 -L -f \
                     --connect-timeout 30 \
                     --max-time 480 \
                     --retry 0 --retry-all-errors \
                     --speed-limit 2000 --speed-time 30 \
                     -C - -o "$part" "$url"; then
                mv -f "$part" "$out"
                return 0
            fi
            sleep "$delay"
            delay=$(( delay < 60 ? delay*2 : 60 ))
        done

        echo "  [FAIL] $url"
        return 1
    }

    # When using ftp, use create_lists and ftpmanyfiles
    create_lists () {

    rm -f sfcfilelst isofilelst

    # ---- Surface variables ----
    echo "Surface variables…"
    iconamegen="icon_global_icosahedral_single-level"
    for lead in $FCLEAD; do
        for var in $VARSFC; do
             fname="${iconamegen}_${andate}_${lead}_${var}.grib2.bz2"
             dir=$(echo "$var" | tr '[:upper:]' '[:lower:]')
	    echo "${dir}/${fname}"  >> sfcfilelst
        done
    done

    # ---- Pressure level variables ----
    echo "Pressure level variables…"
    iconamegen="icon_global_icosahedral_pressure-level"
    for lev in $ISOLEV; do
        for lead in $FCLEAD; do
            for var in $VARISO; do
                 fname="${iconamegen}_${andate}_${lead}_${lev}_${var}.grib2.bz2"
                 dir=$(echo "$var" | tr '[:upper:]' '[:lower:]')
		echo "${dir}/${fname}"  >> isofilelst 
            done
        done
    done
    }
    
    ftpmanyfiles() {
	HOST="$1"
	BASE="$2"
	LIST="$3"

	(
	    echo "set cmd:parallel 6"
	    echo "set net:max-retries 5"
	    echo "set net:reconnect-interval-base 10"
	    echo "set net:timeout 20"
	    echo "open $HOST"
	    echo "cd $BASE"

	    while read -r f; do
		b=$(basename "$f")
		echo "get -c $f -o $b"
	    done < "$LIST"

	    echo "bye"
	) | lftp
    }
    
    local method="${DOWNLOAD_METHOD:-lftp}"
    echo "Download method: $method"

    if [ "$method" = "curl" ]; then
        # ---- Surface variables via HTTPS/curl ----
        echo "Surface variables…"
        local iconamegen="icon_global_icosahedral_single-level"
        for lead in $FCLEAD; do
            for var in $VARSFC; do
                local fname="${iconamegen}_${andate}_${lead}_${var}.grib2.bz2"
                local dir
                dir=$(echo "$var" | tr '[:upper:]' '[:lower:]')
                fetch "${opendir}/${dir}/${fname}" "$fname"
            done
        done

        # ---- Pressure level variables via HTTPS/curl ----
        echo "Pressure level variables…"
        iconamegen="icon_global_icosahedral_pressure-level"
        for lev in $ISOLEV; do
            for lead in $FCLEAD; do
                for var in $VARISO; do
                    local fname="${iconamegen}_${andate}_${lead}_${lev}_${var}.grib2.bz2"
                    local dir
                    dir=$(echo "$var" | tr '[:upper:]' '[:lower:]')
                    fetch "${opendir}/${dir}/${fname}" "$fname"
                done
            done
        done

        echo "=== Download complete ==="
    else
        # ---- Surface and pressure level variables via FTP ----
        create_lists

        ftpmanyfiles "${dwdftp}" "${dwddir}" sfcfilelst
        echo "=== READY FTP sfcfiles $(date '+%F %T') ==="

        ftpmanyfiles "${dwdftp}" "${dwddir}" isofilelst
        echo "=== READY FTP isofiles $(date '+%F %T') ==="
    fi

} #downloads

################################################################################
# Data Transformation and Combination
################################################################################

process_surface_data() {
    local andate="${RT_DATE}${RT_HOUR}"
    local work_dir="${ICOINC}/${RT_DATE}/${RT_HOUR}"
    cd "$work_dir"
    
    echo "=== Processing surface data ==="
    
    local iconamegen="icon_global_icosahedral_single-level"
    local iconamell="icon_global_latlon_single-level"
    local combined_file="icosfc_${andate}_allfc_${AREA}.grib2"
    
    # Remove old combined file if exists
    [ -f "$combined_file" ] && rm "$combined_file"
    
    for lead in $FCLEAD; do
        local lead_file="icosfc_${andate}+${lead}_${AREA}.grib2"
        [ -f "$lead_file" ] && rm "$lead_file"
        
        for var in $VARSFC; do
            local iconamevar="${iconamegen}_${andate}_${lead}_${var}"
            local iconamevarll="${iconamell}_${andate}_${lead}_${var}"
            local infile="${iconamevar}.grib2"
            local outgrib="${iconamevarll}_${AREA}.grib2"
            
            if [ -f "${infile}.bz2" ]; then
                bunzip2 -f "${infile}.bz2"
                
                if transform_coordinates "$infile" "$outgrib"; then
                    cat "$outgrib" >> "$lead_file"
                    cat "$outgrib" >> "$combined_file"
                fi
                
                bzip2 "$infile"
#                rm -f "$infile"
            fi
        done
        
        if [ -f "$lead_file" ]; then
            echo "Created: $lead_file"
        fi
    done
    
    if [ -f "$combined_file" ]; then
        echo "Created combined surface file: $combined_file"
    fi
}

process_pressure_data() {
    local andate="${RT_DATE}${RT_HOUR}"
    local work_dir="${ICOINC}/${RT_DATE}/${RT_HOUR}"
    cd "$work_dir"
    
    echo "=== Processing pressure level data ==="
    
    local iconamegen="icon_global_icosahedral_pressure-level"
    local iconamell="icon_global_latlon_pressure-level"
    
    for lev in $ISOLEV; do
        local level_combined="icoiso_${andate}_${lev}_allfc_${AREA}.grib2"
        [ -f "$level_combined" ] && rm "$level_combined"
        
        for lead in $FCLEAD; do
            local lead_level_file="icoiso_${andate}+${lead}_${lev}_${AREA}.grib2"
            [ -f "$lead_level_file" ] && rm "$lead_level_file"
            
            for var in $VARISO; do
                local iconamevar="${iconamegen}_${andate}_${lead}_${lev}_${var}"
                local iconamevarll="${iconamell}_${andate}_${lead}_${lev}_${var}"
                local infile="${iconamevar}.grib2"
                local outgrib="${iconamevarll}_${AREA}.grib2"
                
                if [ -f "${infile}.bz2" ]; then
                    bunzip2 -f "${infile}.bz2"
                    
                    if transform_coordinates "$infile" "$outgrib"; then
                        cat "$outgrib" >> "$lead_level_file"
                        cat "$outgrib" >> "$level_combined"
                    fi
                    
                    bzip2 "$infile"
                    #rm -f "$infile"
                fi
            done
        done
        
        if [ -f "$level_combined" ]; then
            echo "Created combined pressure level file: $level_combined"
        fi
    done
}

################################################################################
# Surface Elevation Processing
################################################################################

process_surface_elevation() {
    local andate="${RT_DATE}${RT_HOUR}"
    local work_dir="${ICOINC}/${RT_DATE}/${RT_HOUR}"
    local opendir="${OPENDATA_BASE_URL}/${RT_HOUR}"
    
    cd "$work_dir"
    
    echo "=== Processing surface elevation ==="
    
    local sfcelev="${ICOGEO}/icon_time-invariant_HSURF_${AREA}.grib2"
    rm -f "$sfcelev"
    
    # Use 0.125 degree resolution for surface elevation
    local orig_target="$TARGET_GRID_DESCRIPTION"
    local orig_weights="$WEIGHTS_FILE"
    
    local cinc_hsurf="0125"
    export TARGET_GRID_DESCRIPTION="${ICOGEO}/target_grid_${AREA}_${cinc_hsurf}.txt"
    export WEIGHTS_FILE="${ICOGEO}/weights_icogl2${AREA}_${cinc_hsurf}.nc"
    
    # Build target grid for HSURF if it doesn't exist
    if [ ! -f "$TARGET_GRID_DESCRIPTION" ]; then
        build_target_grid "$AREA" "$CROP" "0.125"
    fi
    
    # Ensure weights exist for HSURF
    if [ ! -f "$WEIGHTS_FILE" ]; then
        local ICON_GRID_FILE="${ICOGEO}/icon_grid_0026_R03B07_G.nc"
        if [ -f "$ICON_GRID_FILE" ]; then
            cdo gennn,"${TARGET_GRID_DESCRIPTION}" "${ICON_GRID_FILE}" "${WEIGHTS_FILE}"
        fi
    fi
    
    local infile="icon_global_icosahedral_time-invariant_${andate}_HSURF.grib2"
    rm -f "${infile}"*
    
    if wget -q -O "${infile}.bz2" "${opendir}/hsurf/${infile}.bz2"; then
        bunzip2 "${infile}.bz2"
        
        if transform_coordinates "$infile" "$sfcelev"; then
            echo "Created surface elevation file: $sfcelev"
            
            # Append to combined surface file
            local combined_file="icosfc_${andate}_allfc_${AREA}.grib2"
            if [ -f "$combined_file" ]; then
                cat "$sfcelev" >> "$combined_file"
            fi
        fi
        
        #rm -f "$infile"
	bzip2 "$infile"
    else
        echo "WARNING: Failed to download surface elevation data"
    fi
    
    # Restore original target and weights
    export TARGET_GRID_DESCRIPTION="$orig_target"
    export WEIGHTS_FILE="$orig_weights"
}

################################################################################
# Main Execution
################################################################################

main() {
    echo "=========================================="
    echo "ICON Data Download and Processing"
    echo "=========================================="
    
    # Load configuration
    load_config
    
    # Calculate forecast cycle
    calculate_forecast_cycle
    
    # Set up grid increment string
    local cinc
    cinc=$(get_increment_string "$INCR")
    
    # Set up paths

    export TARGET_GRID_DESCRIPTION="${ICOGEO}/target_grid_${AREA}_${cinc}.txt"
    export WEIGHTS_FILE="${ICOGEO}/weights_icogl2${AREA}_${cinc}.nc"
    
    # Build target grid definition
    if [ ! -f "${TARGET_GRID_DESCRIPTION}" ]; then
        echo "Building target grid definition..."
        build_target_grid "$AREA" "$CROP" "$INCR"
    else
        echo "Using existing target grid: ${TARGET_GRID_DESCRIPTION}"
    fi
    
    # Install/verify grid conversion tools
    if [ ! -f "${WEIGHTS_FILE}" ]; then
        install_icon_geoconv
    else
        echo "Grid conversion tools already installed"
        echo "Weights file: ${WEIGHTS_FILE}"
    fi
    
    # Download data
    if [ "${FETCH:-yes}" = "yes" ]; then
        download_icon_data
    else
        echo "Skipping download FETCH=$FETCH"
    fi
    
    # Transform and combine data
    if [ "${TRANS:-yes}" = "yes" ]; then
        process_surface_data
        process_pressure_data
    else
        echo "Skipping transformation TRANS=$TRANS"
    fi
    
    # Process surface elevation
    if [ "${HSURF:-yes}" = "yes" ]; then
        process_surface_elevation
    else
        echo "Skipping surface elevation HSURF=$HSURF"
    fi
    
    echo "=========================================="
    echo "Processing complete!"
    echo "=========================================="
}

# Execute main function
main "$@"