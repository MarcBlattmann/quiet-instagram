#!/bin/bash

################################################################################
# Description: Replaces Instagram feed endpoints
# Author: breakthescroll.com
################################################################################

# Get the script name
script_name=$(basename "$0")

# Directory of the decompiled app
target_directory="."

# Define the replacements
declare -A replacements

###############################################################################
########### Uncomment / Comment to Add / Remove resources endpoints ###########
###############################################################################

replacements["\"discover/topical_explore/\""]="\"\""

### Feed main screen
### DISABLED: leaving feed/timeline intact so the normal following feed loads.
### Re-enable the line below to block the home feed again.
# replacements["feed/timeline/\""]="\""

### Feed stories (CAN still upload stories)
# replacements["\"feed/reels_tray/\""]="\"\""

### Reels
replacements["\"clips/discover/\""]="\"\""
# clips/discover/social removes reels liked by friends
replacements["\"clips/discover/social/\""]="\"\"" 
replacements["\"discover/explore_clips/\""]="\"\""
replacements["\"clips/discover/stream/\""]="\"\""
#replacements["\"clips/\""]="\"\""
replacements["\"clips/suggested_template\""]="\"\""
replacements["\"clips/trend/\""]="\"\""
#replacements["\"clips/items/\""]="\"\""
replacements["\"discover/discover_similar_clips/\""]="\"\""
replacements["\"/suggested_content/\""]="\"\""
#replacements["\"clips/item/\""]="\"\""
replacements["\"clips/home/\""]="\"\""
replacements["\"clips/chaining/\""]="\"\""
replacements["\"clips/recommended_label/\""]="\"\""
#replacements["\"clips/stream_clips_pivot_page/\""]="\"\""
#replacements["\"clips/risu_medias/\""]="\"\""
#replacements["\"clips_media_ids\""]="\"\""
#replacements["\"/clips\""]="\"\""
replacements["\"/clips_media_feed/\""]="\"\""

###############################################################################
###############################################################################
###############################################################################

echo "Breaking endpoints... This can take a few minutes"

# Collect files (excluding this script and .apk files)
mapfile -t files < <(find "$target_directory" -type f ! -name "$script_name" ! -name "*.apk")
file_count=${#files[@]}

# Create a temporary sed script file to store all replacements (batch processing)
sed_script=$(mktemp)
for old in "${!replacements[@]}"; do
    new="${replacements[$old]}"
    echo "s|$old|$new|g" >> "$sed_script"
done

# Draw a progress bar. Redraws in place on a terminal; falls back to periodic
# lines when the output is a log file, so auto_update.log doesn't fill up with
# carriage returns.
draw_progress() {
    local cur=$1 tot=$2 width=40 pct filled bar
    [ "$tot" -gt 0 ] || return 0
    [ "$cur" -gt "$tot" ] && cur=$tot
    pct=$(( cur * 100 / tot ))
    filled=$(( cur * width / tot ))
    bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
    printf '\r  [%-*s] %3d%%  %d/%d files' "$width" "$bar" "$pct" "$cur" "$tot"
}

echo "Replacing endpoints in $file_count files..."

# One sed per batch rather than one per file. On a decompiled Instagram that is
# a few hundred processes instead of ~180,000, which is most of the runtime.
batch=500
i=0
last_decile=-1

while [ "$i" -lt "$file_count" ]; do
    sed -i -f "$sed_script" "${files[@]:i:batch}"
    i=$(( i + batch ))

    if [ -t 1 ]; then
        draw_progress "$i" "$file_count"
    else
        # Non-interactive: one line per 10% instead of a redrawing bar.
        cur=$i; [ "$cur" -gt "$file_count" ] && cur=$file_count
        pct=$(( cur * 100 / file_count ))
        if [ $(( pct / 10 )) -ne "$last_decile" ]; then
            last_decile=$(( pct / 10 ))
            echo "  ${pct}%  (${cur}/${file_count} files)"
        fi
    fi
done

[ -t 1 ] && echo

# Clean up temporary sed script
rm "$sed_script"

echo "Success: Endpoints broken!"
