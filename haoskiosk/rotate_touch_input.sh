#!/bin/bash
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: rotate_touch_input.sh
# Version: 1.0.0
# Copyright Jeff Kosowsky
# Date: July 2025
#
# Description: Rotate input of any available touchscreen input event device
# Options: normal, left, right, inverted
#
# Uses 'xinput' to identify valid input event devices that contain the word
# touch, touchscreen, or stylus and have a valid 'Calibration' property.
#
################################################################################

#set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 {normal|left|right|inverted}"
    exit 1
fi

ROTATION=$1
declare -A MATRICES=(
    ["normal"]="1 0 0 0 1 0 0 0 1"
    ["left"]="0 -1 1 1 0 0 0 0 1"
    ["right"]="0 1 0 -1 0 1 0 0 1"
    ["inverted"]="-1 0 1 0 -1 1 0 0 1"
)
MATRIX="${MATRICES[$ROTATION]:-}"
if [[ -z "$MATRIX" ]]; then
    echo "Invalid rotation: '$ROTATION'"
    exit 1
fi

echo "Applying rotation $ROTATION ($MATRIX) to:"

# Apply 'xinput' to inputs matching touch, touchscreen or stylus
while IFS= read -r id; do
    name=$(xinput list --name-only "$id" 2>/dev/null)
    lc_name="${name,,}"
    [[ "$lc_name" =~ (^|[^[:alnum:]_])(touch|touchscreen|stylus)([^[:alnum:]_]|$) ]] || continue
    props="$(xinput list-props "$id" 2>/dev/null)"
    [[ "$props" = *"Coordinate Transformation Matrix"* ]] ||  continue #No transformation matrix

    if xinput set-prop "$id" "Coordinate Transformation Matrix" "$MATRIX" 2>/dev/null; then
        echo -n "  SUCCESS: "
    else
        echo -n "  FAILURE: "
    fi
    echo "$id|$name"
done < <(xinput list --id-only | sort -n)
