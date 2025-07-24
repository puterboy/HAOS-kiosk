#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Clean up on exit:
TTY0_DELETED="" #Need to set to empty string since runs with nounset=on (like set -u)
trap '[ -n "$(jobs -p)" ] && kill $(jobs -p); [ -n "$TTY0_DELETED" ] && mknod -m 620 /dev/tty0 c 4 0; exit' INT TERM EXIT
################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: run.sh
# Version: 1.0.0
# Copyright Jeff Kosowsky
# Date: July 2025
#
#  Code does the following:
#     - Import and sanity-check the following variables from HA/config.yaml
#         HA_USERNAME
#         HA_PASSWORD
#         HA_URL
#         HA_DASHBOARD
#         HA_THEME
#         HA_SIDEBAR
#         LOGIN_DELAY
#         ZOOM_LEVEL
#         BROWSER_REFRESH
#         SCREEN_TIMEOUT
#         HDMI_PORT
#         ROTATE_DISPLAY
#         ROTATE_TOUCH
#         XORG_CONF
#         XORG_APPEND_REPLACE
#         DEBUG_MODE
#
#     - Hack to delete (and later restore) /dev/tty0 (needed for X to start
#       and to prevent udev permission errors))
#     - Start udev
#     - Hack to manually tag USB input devices (in /dev/input) for libinput
#     - Start X window system
#     - Stop console cursor blinking
#     - Start Openbox window manager
#     - Set up (enable/disable) screen timeouts
#     - Rotate screen as appropriate
#     - Poll to check if monitor wakes up and if so, reload luakit browser
#     - Launch fresh Luakit browser for url: $HA_URL/$HA_DASHBOARD
#       [If not in DEBUG_MODE; Otherwise, just sleep]
#
################################################################################
echo "." #Note totally blank or white space lines are swallowed
bashio::log.info "######## Starting HAOSKiosk ########"
### Get config variables from HA add-on & set environment variables
function get_config() {
    # First, use existing variable if already set (for debugging purposes)
    # If not set, lookup configuration value
    # If null, use optional second parameter or else ""
    local VAR_NAME="$1"
    local DEFAULT="${2:-}"
    local MASK="${3:-}"

    local VALUE
    #Check if $VAR_NAME exists before getting its value since 'set +x' mode
    if declare -p "$VAR_NAME" >/dev/null 2>&1; then #Variable exist, get its value
        VALUE="${!VAR_NAME}"
    else # Try to get it from HA config using lowercase of key name
        VALUE="$(bashio::config "${VAR_NAME,,}")"
    fi

    if [ "$VALUE" = "null" ] || [ -z "$VALUE" ]; then
        VALUE="$DEFAULT"
    fi

    # Assign and export safely using 'printf -v' and 'declare -x'
    printf -v "$VAR_NAME" '%s' "$VALUE"
    eval "export $VAR_NAME"

    if [ -z "$MASK" ]; then
        bashio::log.info "$VAR_NAME=$VALUE"
    else
        bashio::log.info "$VAR_NAME=XXXXXX"
    fi
}

get_config HA_USERNAME
get_config HA_PASSWORD "" 1 #Mask password in log
get_config HA_URL
get_config HA_DASHBOARD
get_config HA_THEME
get_config HA_SIDEBAR
get_config LOGIN_DELAY
get_config ZOOM_LEVEL
get_config BROWSER_REFRESH
get_config SCREEN_TIMEOUT 600 # Default to 600 seconds
get_config HDMI_PORT 1 # Default to 1 (Can be 1 or 2, corresponding to HDMI-1 and HDMI-2)
#NOTE: For now, both HDMI ports are mirrored so no difference between HDMI-1 and HDMI-2
#      Not sure how to get them unmirrored short of editing /boot/config.txt for the
#      underlying HAOS which is not accessible
#      As a result, setting HDMI=1 vs. 2 has no effect for now
get_config ROTATE_DISPLAY normal
get_config ROTATE_TOUCH false
get_config XORG_CONF
get_config XORG_APPEND_REPLACE append
get_config DEBUG_MODE false

#Validate environment variables set by config.yaml
if [ -z "$HA_USERNAME" ] || [ -z "$HA_PASSWORD" ]; then
    bashio::log.error "Error: HA_USERNAME and HA_PASSWORD must be set"
    exit 1
fi

################################################################################
### Start Dbus
# Avoids waiting for DBUS timeouts (e.g., luakit)
# Allows luakit to enfoce unique instance by default
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
export DBUS_SESSION_BUS_ADDRESS

#Note first need to delete /dev/tty0 since X won't start if it is there,
#because X doesn't have permissions to access it in the container
#Also, prevents udev permission error warnings & issues
#First, remount /dev as read-write since X absolutely, must have /dev/tty access
#Note: need to use the version in util-linux, not busybox
#Note: Do *not* later remount as 'ro' since that affect the root fs and
#      in particular will block HAOS updates
if [ -e "/dev/tty0" ]; then
    bashio::log.info "Attempting to remount /dev as 'ro' and (temporarily) delete /dev/tty0..."
    mount -o remount,rw /dev
    if ! mount -o remount,rw /dev ; then
        bashio::log.error "Failed to remount /dev as read-write..."
        exit 1
    fi
    if  ! rm -f /dev/tty0 ; then
        bashio::log.error "Failed to delete /dev/tty0..."
        exit 1
    fi
    TTY0_DELETED=1
    bashio::log.info "Deleted /dev/tty0 successfully..."
fi

### Start udev (used by X)
bashio::log.info "Starting 'udevd' and (re-)triggering..."
udevd --daemon
udevadm trigger

# Manually tag USB input devices (in /dev/input) for libinput since
# 'udev' doesn't necessarily trigger their tagging when run in a container.
if [ -x "/tag-input-devices.sh" ]; then
    bashio::log.info "Tagging USB input devices for use by 'libinput'..."
    /tag-input-devices.sh
fi

### Start Xorg in the background
rm -rf /tmp/.X*-lock #Cleanup old versions

if [ -z "$XORG_CONF" ]; then
    bashio::log.info "No user 'xorg.conf' data provided, using default..."
else
    if [ "${XORG_APPEND_REPLACE}" = "append" ]; then
        bashio::log.info "Appending onto default 'xorg.conf'..."
        echo -e "\n#\n${XORG_CONF}" >> /etc/X11/xorg.conf

    else
        bashio::log.info "Starting X on '$DISPLAY'..."
        echo "${XORG_CONF}" >| /etc/X11/xorg.conf
    fi
fi

# Print out current 'xorg.conf'
echo "." #Note totally blank or white space lines are swallowed
printf '%*s xorg.conf %*s\n' 35 '' 34 '' | tr ' ' '#' #Header
cat /etc/X11/xorg.conf
printf '%*s\n' 80 '' | tr ' ' '#' #Trailer
echo "."

Xorg "$DISPLAY" -layout "Layout$((HDMI_PORT - 1))" </dev/null &

XSTARTUP=30
for ((i=0; i<=XSTARTUP; i++)); do
    if xset q >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Restore /dev/tty0
if [ -n "$TTY0_DELETED" ]; then
    if mknod -m 620 /dev/tty0 c 4 0; then
        bashio::log.info "Restored /dev/tty0 successfully..."
    else
        bashio::log.error "Failed to restore /dev/tty0..."
    fi
fi

if ! xset q >/dev/null 2>&1; then
    bashio::log.error "Error: X server failed to start within $XSTARTUP seconds."
    exit 1
fi
bashio::log.info "X started successfully..."

#Stop console blinking cursor (this projects through the X-screen)
echo -e "\033[?25l" > /dev/console

### Start Openbox in the background
openbox &
O_PID=$!
sleep 0.5  #Ensure Openbox starts
if ! kill -0 "$O_PID" 2>/dev/null; then #Checks if process alive
    bashio::log.error "Failed to start Openbox window manager"
    exit 1
fi
bashio::log.info "Openbox started successfully..."

### Configure screen timeout (Note: DPMS needs to be enabled/disabled *after* starting Openbox)
if [ "$SCREEN_TIMEOUT" -eq 0 ]; then #Disable screen saver and DPMS for no timeout
    xset s 0
    xset dpms 0 0 0
    xset -dpms
    bashio::log.info "Screen timeout disabled..."
else
    xset s "$SCREEN_TIMEOUT"
    xset dpms "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"  #DPMS standby, suspend, off
    xset +dpms
    bashio::log.info "Screen timeout after $SCREEN_TIMEOUT seconds..."
fi

#Rotate display && touchscreen inputs
if [ "$ROTATE_DISPLAY" != normal ]; then
    xrandr --output HDMI-"${HDMI_PORT}" --rotate "${ROTATE_DISPLAY}"
    bashio::log.info "Rotating HDMI-${HDMI_PORT}: ${ROTATE_DISPLAY}"
    if [ "$ROTATE_TOUCH" = true ]; then
        ./rotate_touch_input.sh "${ROTATE_DISPLAY}"
        bashio::log.info "Rotating touch input devices: ${ROTATE_DISPLAY}"
    fi
fi

# Poll to send <Control-r> when screen unblanks to force reload of luakit page
(
    PREV=""
    while true; do
        if pgrep luakit > /dev/null; then
            STATE=$(xset -q | awk '/Monitor is/ {print $3}')
            [[ "$PREV" == "Off" && "$STATE" == "On" ]] && xdotool key --clearmodifiers ctrl+r
            PREV=$STATE
        fi
        sleep 1
    done
)&

if [ "$DEBUG_MODE" != true ]; then
    ### Run Luakit in the foreground
    bashio::log.info "Launching Luakit browser: $HA_URL/$HA_DASHBOARD"
    exec luakit -U "$HA_URL/$HA_DASHBOARD"
else ### Debug mode
    bashio::log.info "Entering debug mode (X & Openbox but no luakit browser)..."
    exec sleep infinite
fi
