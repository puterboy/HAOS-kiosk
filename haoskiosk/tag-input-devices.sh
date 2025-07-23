#!/bin/bash
################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: run.sh
# Version: 1.0.0
# Copyright Jeff Kosowsky
# Date: July 2025

# Description: Tags USB input devices (keyboard, mouse, joystick) for libinput and Home Assistant by writing to /run/udev/data.
# Usage: Run as root in HA container: bash tag-input-devices.sh
# Notes: Used in containers without udev rule support. Run on startup or device change.
#
################################################################################

# Create udev data directory
mkdir -p /run/udev/data

# Loop through all input devices
for dev in /dev/input/event*; do
    # Extract device name and number
    devname=$(basename "$dev")
    input_num=${devname#event}

    # Get device path to check if USB
    devpath=$(udevadm info "$dev" | grep -m1 DEVPATH | cut -d= -f2)
    if [[ ! $devpath =~ /usb[0-9]+.*[0-9]{4}:[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4} ]]; then
        echo "$devname: Skipped (non-USB)"
        continue
    fi

    # Extract vendor and product IDs from 0003:vendor:product
    vendor_product=$(echo "$devpath" | grep -oE '0003:[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}' | head -1)
    vendor=$(echo "$vendor_product" | cut -d: -f2)
    vendor=${vendor:-unknown}
    product=$(echo "$vendor_product" | cut -d: -f3)
    product=${product:-unknown}
    group="3/${vendor,,}/${product,,}:usb-xhci-hcd.0-1"

    # Read sysfs capabilities for device type
    syspath="/sys${devpath%/event*}/capabilities"
    ev=$(cat "$syspath/ev" 2>/dev/null || echo none)
    key=$(cat "$syspath/key" 2>/dev/null || echo none)
    rel=$(cat "$syspath/rel" 2>/dev/null || echo none)
    abs=$(cat "$syspath/abs" 2>/dev/null || echo none)
    key_count=$(echo "$key" | tr ' ' '\n' | grep -vc '^0$')

    # Classify device type
    device_type=unknown
    if [[ $ev != none && $key != none && $key_count -gt 2 && $rel = 0 && $abs = 0 ]]; then
        device_type=keyboard
    elif [[ $rel != none && $key_count -le 2 && $abs = 0 ]]; then
        device_type=mouse
    elif [[ $ev = 1b || $abs != none ]]; then
        device_type=joystick
    fi

    # Skip unclassified devices
    if [[ $device_type = unknown ]]; then
        echo "$devname: Skipped (unrecognized: ev=$ev, keys=$key_count, rel=$rel, abs=$abs)"
        continue
    fi

    # Write tags to udev data
    {
        echo "ID_INPUT=1"
        echo "ID_INPUT_${device_type^^}=1"
        echo "LIBINPUT_DEVICE_GROUP=$group"
    } > "/run/udev/data/+input:input$input_num"

    # Trigger udev to process tags
    udevadm test "$devpath" >/dev/null 2>&1

    # Output result
    echo "$devname: $device_type (ID_INPUT=1, Group=$group)"
done

# Show libinput devices with indented output
echo "libinput list-devices found:"
libinput list-devices 2>/dev/null | awk '
  /^Device:/ {devname=substr($0, 9)}
  /^Kernel:/ {
    split($2, a, "/");
    printf "  %s: %s\n", a[length(a)], devname
}'
