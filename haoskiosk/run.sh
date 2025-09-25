#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.1.1"
################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: run.sh
# Version: 1.1.1
# Copyright Jeff Kosowsky
# Date: September 2025
#
#  Code does the following:
#     - Import and sanity-check the following variables from HA/config.yaml
#         HA_USERNAME
#         HA_PASSWORD
#         HA_URL
#         HA_DASHBOARD
#         LOGIN_DELAY
#         ZOOM_LEVEL
#         BROWSER_REFRESH
#         SCREEN_TIMEOUT
#         OUTPUT_NUMBER
#         DARK_MODE
#         HA_SIDEBAR
#         ROTATE_DISPLAY
#         MAP_TOUCH_INPUTS
#         CURSOR_TIMEOUT
#         KEYBOARD_LAYOUT
#         ONSCREEN_KEYBOARD
#         SAVE_ONSCREEN_CONFIG
#         XORG_CONF
#         XORG_APPEND_REPLACE
#         REST_PORT
#         REST_BEARER_TOKEN
#         ALLOW_USER_COMMANDS
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
#     - Rotate screen per configuration
#     - Map touch inputs per configuration
#     - Set keyboard layout and language
#     - Set up onscreen keyboard per configuration
#     - Start REST API server
#     - Launch fresh Luakit browser for url: $HA_URL/$HA_DASHBOARD
#       [If not in DEBUG_MODE; Otherwise, just sleep]
#
################################################################################
echo "." #Almost blank line (Note totally blank or white space lines are swallowed)
printf '%*s\n' 80 '' | tr ' ' '#' #Separator
bashio::log.info "######## Starting HAOSKiosk ########"
bashio::log.info "$(date) [Version: $VERSION]"
bashio::log.info "$(uname -a)"
ha_info=$(bashio::info)
bashio::log.info "Core=$(echo "$ha_info" | jq -r '.homeassistant')  HAOS=$(echo "$ha_info" | jq -r '.hassos')  MACHINE=$(echo "$ha_info" | jq -r '.machine')  ARCH=$(echo "$ha_info" | jq -r '.arch')"

#### Clean up on exit:
TTY0_DELETED="" #Need to set to empty string since runs with nounset=on (like set -u)
ONBOARD_CONFIG_FILE="/config/onboard-settings.dconf"
cleanup() {
    local exit_code=$?
    if [ "$SAVE_ONSCREEN_CONFIG" = true ]; then
        dconf dump /org/onboard/ > "$ONBOARD_CONFIG_FILE"
    fi
    jobs -p | xargs -r kill
    [ -n "$TTY0_DELETED" ] && mknod -m 620 /dev/tty0 c 4 0
    exit "$exit_code"
}
trap cleanup HUP INT QUIT ABRT TERM EXIT

################################################################################
#### Get config variables from HA add-on & set environment variables
load_config_var() {
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
    elif bashio::config.exists "${VAR_NAME,,}"; then
        VALUE="$(bashio::config "${VAR_NAME,,}")"
    else
        bashio::log.warning "Unknown config key: ${VAR_NAME,,}"
    fi

    if [ "$VALUE" = "null" ] || [ -z "$VALUE" ]; then
        bashio::log.warning "Config key '${VAR_NAME,,}' unset, setting to default: '$DEFAULT'"
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

load_config_var HA_USERNAME
load_config_var HA_PASSWORD "" 1 #Mask password in log
load_config_var HA_URL "http://localhost:8123"
load_config_var HA_DASHBOARD ""
load_config_var LOGIN_DELAY 1.0
load_config_var ZOOM_LEVEL 100
load_config_var BROWSER_REFRESH 600
load_config_var SCREEN_TIMEOUT 600 # Default to 600 seconds
load_config_var OUTPUT_NUMBER 1 # Which *CONNECTED* Physical video output to use (Defaults to 1)
#NOTE: By only considering *CONNECTED* output, this maximizes the chance of finding an output
#      without any need to change configs. Set to 1, unless you have multiple video outputs connected.
load_config_var DARK_MODE true
load_config_var HA_SIDEBAR "none"
load_config_var ROTATE_DISPLAY normal
load_config_var MAP_TOUCH_INPUTS true
load_config_var CURSOR_TIMEOUT 5 #Default to 5 seconds
load_config_var KEYBOARD_LAYOUT us
load_config_var ONSCREEN_KEYBOARD false
load_config_var SAVE_ONSCREEN_CONFIG true
load_config_var XORG_CONF ""
load_config_var XORG_APPEND_REPLACE append
load_config_var REST_PORT 8080
load_config_var REST_BEARER_TOKEN "" 1 #Mask token in log
load_config_var ALLOW_USER_COMMANDS false
[ "$ALLOW_USER_COMMANDS" = "true" ] && bashio::log.warning "WARNING: 'allow_user_commands' set to 'true'"
load_config_var DEBUG_MODE false

# Validate environment variables set by config.yaml
if [ -z "$HA_USERNAME" ] || [ -z "$HA_PASSWORD" ]; then
    bashio::log.error "Error: HA_USERNAME and HA_PASSWORD must be set"
    exit 1
fi

################################################################################
#### Start Dbus
# Avoids waiting for DBUS timeouts (e.g., luakit)
# Allows luakit to enforce unique instance by default
# Note do *not* use '-U' flag when calling luakit
# Subsequent calls to 'luakit' exit post launch, leaving just the original process
# Not 'userconf.lua' includes code to turn off session restore.
# Note if entering through a separate shell, need to export the original
# DBUS_SESSION_BUS_ADDRESS variable so that processes can communicate.

DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    bashio::log.warning "WARNING: Failed to start dbus-daemon"
fi
bashio::log.info "DBus started with: DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
export DBUS_SESSION_BUS_ADDRESS
#Make available to subsequent shells
echo "export DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS'" >> "$HOME/.profile"

#### Hack to get writable /dev/tty0 for X
# Note first need to delete /dev/tty0 since X won't start if it is there,
# because X doesn't have permissions to access it in the container
# Also, prevents udev permission error warnings & issues
# Note that remounting rw is not sufficient

# First, remount /dev as read-write since X absolutely, must have /dev/tty access
# Note: need to use the version of 'mount' in util-linux, not busybox
# Note: Do *not* later remount as 'ro' since that affect the root fs and
#       in particular will block HAOS updates
if [ -e "/dev/tty0" ]; then
    bashio::log.info "Attempting to remount /dev as 'rw' so we can (temporarily) delete /dev/tty0..."
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

#### Start udev (used by X)
bashio::log.info "Starting 'udevd' and (re-)triggering..."
if ! udevd --daemon || ! udevadm trigger; then
    bashio::log.warning "WARNING: Failed to start udevd or trigger udev, input devices may not work"
fi

# Force tagging of event input devices (in /dev/input) to enable recognition by
# libinput since 'udev' doesn't necessarily trigger their tagging when run from a container.
echo "/dev/input event devices:"
for dev in $(find /dev/input/event* | sort -V); do # Loop through all input devices
    devpath_output=$(udevadm info --query=path --name="$dev" 2>/dev/null; echo -n $?)
    return_status=${devpath_output##*$'\n'}
    [ "$return_status" -eq 0 ] || { echo "  $dev: Failed to get device path"; continue; }
    devpath=${devpath_output%$'\n'*}
    echo "  $dev: $devpath"

    # Simulate a udev event to trigger (re)load of all properties
    udevadm test "$devpath" >/dev/null 2>&1 || echo "$dev: No valid udev rule found..."
done

udevadm settle --timeout=10 #Wait for udev event processing to complete

# Show discovered libinput devices
echo "libinput list-devices found:"
libinput list-devices 2>/dev/null | awk '
  /^Device:/ {devname=substr($0, 9)}
  /^Kernel:/ {
    split($2, a, "/");
    printf "  %s: %s\n", a[length(a)], devname
}' | sort -V

## Determine main display card
bashio::log.info "DRM video cards:"
find /dev/dri/ -maxdepth 1 -type c -name 'card[0-9]*' 2>/dev/null | sed 's/^/  /'
bashio::log.info "DRM video card driver and connection status:"
selected_card=""
for status_path in /sys/class/drm/card[0-9]*-*/status; do
    [ -e "$status_path" ] || continue  # Skip if status file doesn't exist

    status=$(cat "$status_path")
    card_port=$(basename "$(dirname "$status_path")")
    card=${card_port%%-*}
    driver=$(basename "$(readlink "/sys/class/drm/$card/device/driver")")
    if [ -z "$selected_card" ]  && [ "$status" = "connected" ]; then
        selected_card="$card" # Select first connected card
        printf "  *"
    else
        printf "   "
    fi
    printf "%-25s%-20s%s\n" "$card_port" "$driver" "$status"
done
if [ -z "$selected_card" ]; then
    bashio::log.info "ERROR: No connected video card detected. Exiting.."
    exit 1
fi

#### Start Xorg in the background
rm -rf /tmp/.X*-lock #Cleanup old versions

# Modify 'xorg.conf' as appropriate
if [[ -n "$XORG_CONF" && "${XORG_APPEND_REPLACE}" = "replace" ]]; then
    bashio::log.info "Replacing default 'xorg.conf'..."
    echo "${XORG_CONF}" >| /etc/X11/xorg.conf
else
    cp -a /etc/X11/xorg.conf{.default,}
    #Add "kmsdev" line to Device Section based on 'selected_card'
    sed -i "/Option[[:space:]]\+\"DRI\"[[:space:]]\+\"3\"/a\    Option     \t\t\"kmsdev\" \"/dev/dri/$selected_card\"" /etc/X11/xorg.conf

    if [ -z "$XORG_CONF" ]; then
        bashio::log.info "No user 'xorg.conf' data provided, using default..."
    elif [ "${XORG_APPEND_REPLACE}" = "append" ]; then
        bashio::log.info "Appending onto default 'xorg.conf'..."
        echo -e "\n#\n${XORG_CONF}" >> /etc/X11/xorg.conf
    fi
fi

# Print out current 'xorg.conf'
echo "." #Almost blank line (Note totally blank or white space lines are swallowed)
printf '%*s xorg.conf %*s\n' 35 '' 34 '' | tr ' ' '#' #Header
cat /etc/X11/xorg.conf
printf '%*s\n' 80 '' | tr ' ' '#' #Trailer
echo "."

bashio::log.info "Starting X on DISPLAY=$DISPLAY..."
NOCURSOR=""
[ "$CURSOR_TIMEOUT" -lt 0 ] && NOCURSOR="-nocursor" #No cursor if <0
Xorg $NOCURSOR </dev/null &

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
bashio::log.info "X server started successfully after $i seconds..."

# List xinput devices
echo "xinput list:"
xinput list | sed 's/^/  /'

#Stop console blinking cursor (this projects through the X-screen)
echo -e "\033[?25l" > /dev/console

#Hide cursor dynamically after CURSOR_TIMEOUT seconds if positive
if [ "$CURSOR_TIMEOUT" -gt 0 ]; then
    unclutter-xfixes --start-hidden --hide-on-touch --fork --timeout "$CURSOR_TIMEOUT"
fi

#### Start Window manager in the background
WINMGR=Openbox #Openbox window manager
openbox &

#WINMGR=xfwm4  #Alternately using xfwm4
#xfsettingsd &
#startxfce4 &

O_PID=$!
sleep 0.5  #Ensure window manager starts
if ! kill -0 "$O_PID" 2>/dev/null; then #Checks if process alive
    bashio::log.error "Failed to start $WINMGR window  manager"
    exit 1
fi
bashio::log.info "$WINMGR window manager started successfully..."

#### Configure screen timeout (Note: DPMS needs to be enabled/disabled *after* starting window manager)
xset +dpms #Turn on DPMS
xset s "$SCREEN_TIMEOUT"
xset dpms "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"
if [ "$SCREEN_TIMEOUT" -eq 0 ]; then
    bashio::log.info "Screen timeout disabled..."
else
    bashio::log.info "Screen timeout after $SCREEN_TIMEOUT seconds..."
fi

#### Activate (+/- rotate) desired physical output number
# Detect connected physical outputs

readarray -t ALL_OUTPUTS < <(xrandr --query | awk '/^[[:space:]]*[A-Za-z0-9-]+/ {print $1}')
bashio::log.info "All video outputs: ${ALL_OUTPUTS[*]}"

readarray -t OUTPUTS < <(xrandr --query | awk '/ connected/ {print $1}') # Read in array of outputs
if [ ${#OUTPUTS[@]} -eq 0 ]; then
    bashio::log.info "ERROR: No connected outputs detected. Exiting.."
    exit 1
fi

# Select the N'th connected output (fallback to last output if N exceeds actual number of outputs)
if [ "$OUTPUT_NUMBER" -gt "${#OUTPUTS[@]}" ]; then
    OUTPUT_NUMBER=${#OUTPUTS[@]}  # Use last output
fi
bashio::log.info "Connected video outputs: (Selected output marked with '*')"
for i in "${!OUTPUTS[@]}"; do
    marker=" "
    [ "$i" -eq "$((OUTPUT_NUMBER - 1))" ] && marker="*"
    bashio::log.info "  ${marker}[$((i + 1))] ${OUTPUTS[$i]}"
done
OUTPUT_NAME="${OUTPUTS[$((OUTPUT_NUMBER - 1))]}" #Subtract 1 since zero-based

# Configure the selected output and disable others
for OUTPUT in "${OUTPUTS[@]}"; do
    if [ "$OUTPUT" = "$OUTPUT_NAME" ]; then #Activate
        if [ "$ROTATE_DISPLAY" = normal ]; then
            xrandr --output "$OUTPUT_NAME" --primary --auto
        else
            xrandr --output "$OUTPUT_NAME" --primary --rotate "${ROTATE_DISPLAY}"
            bashio::log.info "Rotating $OUTPUT_NAME: ${ROTATE_DISPLAY}"
        fi
    else # Set as inactive output
        xrandr --output "$OUTPUT" --off
    fi
done

if [ "$MAP_TOUCH_INPUTS" = true ]; then #Map touch devices to physical output
    while IFS= read -r id; do #Loop through all xinput devices
        name=$(xinput list --name-only "$id" 2>/dev/null)
        [[ "${name,,}" =~ (^|[^[:alnum:]_])(touch|touchscreen|stylus)([^[:alnum:]_]|$) ]] || continue #Not touch-like input
        xinput_line=$(xinput list "$id" 2>/dev/null)
        [[ "$xinput_line" =~ \[(slave|master)[[:space:]]+keyboard[[:space:]]+\([0-9]+\)\] ]] && continue
        props="$(xinput list-props "$id" 2>/dev/null)"
        [[ "$props" = *"Coordinate Transformation Matrix"* ]] ||  continue #No transformation matrix
        xinput map-to-output "$id" "$OUTPUT_NAME" && RESULT="SUCCESS" || RESULT="FAILED"
        bashio::log.info "Mapping: input device [$id|$name] -->  $OUTPUT_NAME [$RESULT]"

    done < <(xinput list --id-only | sort -n)
fi

#### Set keyboard layout
setxkbmap "$KEYBOARD_LAYOUT"
export LANG=$KEYBOARD_LAYOUT
bashio::log.info "Setting keyboard layout and language to: $KEYBOARD_LAYOUT"
setxkbmap -query  | sed 's/^/  /' #Log layout

### Get screen width & height for selected output
read -r SCREEN_WIDTH SCREEN_HEIGHT < <(
    xrandr --query --current | grep "^$OUTPUT_NAME " |
    sed -n "s/^$OUTPUT_NAME connected.* \([0-9]\+\)x\([0-9]\+\)+.*$/\1 \2/p"
)

if [[ -n "$SCREEN_WIDTH" && -n "$SCREEN_HEIGHT" ]]; then
    bashio::log.info "Screen: Width=$SCREEN_WIDTH  Height=$SCREEN_HEIGHT"
else
    bashio::log.error "Could not determine screen size for output $OUTPUT_NAME"
fi

#### Launch Onboard onscreen keyboard per configuration
if [[ "$ONSCREEN_KEYBOARD" = true && -n "$SCREEN_WIDTH" && -n "$SCREEN_HEIGHT" ]]; then
    ### Define min/max dimensions for orientation-agnostic calculation
    if (( SCREEN_WIDTH >= SCREEN_HEIGHT )); then #Landscape
        MAX_DIM=$SCREEN_WIDTH
        MIN_DIM=$SCREEN_HEIGHT
        ORIENTATION="landscape"
    else #Portrait
        MAX_DIM=$SCREEN_HEIGHT
        MIN_DIM=$SCREEN_WIDTH
        ORIENTATION="portrait"
    fi

    KBD_ASPECT_RATIO_X10=30  # Ratio of keyboard width to keyboard height times 10 (must be integer)
    # So that 30 is 3:1 (Note use times 10 since want to use integer arithmetic)

    ### Default keyboard geometry for landscape (full-width, bottom half of screen)
    LAND_HEIGHT=$(( MIN_DIM / 3 ))
    LAND_WIDTH=$(( (LAND_HEIGHT * KBD_ASPECT_RATIO_X10) / 10 ))
    [ $LAND_WIDTH -gt "$MAX_DIM" ] && LAND_WIDTH=$MAX_DIM
    LAND_Y_OFFSET=$(( MIN_DIM - LAND_HEIGHT ))
    LAND_X_OFFSET=$(( (MAX_DIM - LAND_WIDTH) / 2 ))  # Centered

    ### Default keyboard geometry for portrait (full-width, bottom 1/4 of screen)
    PORT_HEIGHT=$(( MAX_DIM / 4 ))
    PORT_WIDTH=$(( (PORT_HEIGHT * KBD_ASPECT_RATIO_X10) / 10 ))
    [ $PORT_WIDTH -gt "$MIN_DIM" ] && PORT_WIDTH=$MIN_DIM
    PORT_Y_OFFSET=$(( MAX_DIM - PORT_HEIGHT ))
    PORT_X_OFFSET=$(( (MIN_DIM - PORT_WIDTH) / 2 ))  # Centered

    ### Apply default settings and geometry
    # Global appearance settings
    dconf write /org/onboard/layout "'/usr/share/onboard/layouts/Small.onboard'"
    dconf write /org/onboard/theme "'/usr/share/onboard/themes/Blackboard.theme'"
    dconf write /org/onboard/theme-settings/color-scheme "'/usr/share/onboard/themes/Charcoal.colors'"

    # Behavior settings
    dconf write /org/onboard/auto-show/enabled true  # Auto-show
    dconf write /org/onboard/auto-show/tablet-mode-detection-enabled false  # Show keyboard only in tablet mode
    dconf write /org/onboard/window/force-to-top true  # Always on top
    gsettings set org.gnome.desktop.interface toolkit-accessibility true  # Disable gnome accessibility popup

    # Default landscape geometry
    dconf write /org/onboard/window/landscape/height "$LAND_HEIGHT"
    dconf write /org/onboard/window/landscape/width "$LAND_WIDTH"
    dconf write /org/onboard/window/landscape/x "$LAND_X_OFFSET"
    dconf write /org/onboard/window/landscape/y "$LAND_Y_OFFSET"

    # Default portrait geometry
    dconf write /org/onboard/window/portrait/height "$PORT_HEIGHT"
    dconf write /org/onboard/window/portrait/width "$PORT_WIDTH"
    dconf write /org/onboard/window/portrait/x "$PORT_X_OFFSET"
    dconf write /org/onboard/window/portrait/y "$PORT_Y_OFFSET"

    ### Restore or delete saved  user configuration
    if [ -f "$ONBOARD_CONFIG_FILE" ]; then
        if [ "$SAVE_ONSCREEN_CONFIG" = true ]; then
            bashio::log.info "Restoring Onboard configuration from '$ONBOARD_CONFIG_FILE'"
            dconf load /org/onboard/ < "$ONBOARD_CONFIG_FILE"
        else #Otherwise delete config file (if it exists)
            rm -f "$ONBOARD_CONFIG_FILE"
        fi
    fi

    LOG_MSG=$(
        echo "Onboard keyboard initialized for: $OUTPUT_NAME (${SCREEN_WIDTH}x${SCREEN_HEIGHT}) [$ORIENTATION]"
        echo "  Appearance: Layout=$(dconf read /org/onboard/layout)  Theme=$(dconf read /org/onboard/theme)  Color-Scheme=$(dconf read /org/onboard/theme-settings/color-scheme)"
        echo "  Behavior: Auto-Show=$(dconf read /org/onboard/auto-show/enabled)  Tablet-Mode=$(dconf read /org/onboard/auto-show/tablet-mode-detection-enabled)  Force-to-Top=$(dconf read /org/onboard/window/force-to-top)"
        echo "  Geometry: Height=$(dconf read /org/onboard/window/${ORIENTATION}/height)  Width=$(dconf read /org/onboard/window/${ORIENTATION}/width)  X-Offset=$(dconf read /org/onboard/window/${ORIENTATION}/x)  Y-Offset=$(dconf read /org/onboard/window/${ORIENTATION}/y)"
    )
    bashio::log.info "$LOG_MSG"

    ### Launch 'Onboard' keyboard
    bashio::log.info "Starting Onboard onscreen keyboard"
    onboard &
    python3 /toggle_keyboard.py "$DARK_MODE" & #Creates 1x1 pixel at extreme top-right of screen to toggle keyboard visibility
fi

#### Start  HAOSKiosk REST server
bashio::log.info "Starting HAOSKiosk REST server..."
python3 /rest_server.py &

#### Start browser (or debug mode)  and wait/sleep
if [ "$DEBUG_MODE" != true ]; then
    ### Run Luakit in the background and wait for process to exit
    bashio::log.info "Launching Luakit browser: $HA_URL/$HA_DASHBOARD"
    luakit "$HA_URL/$HA_DASHBOARD" &
    LUAKIT_PID=$!
    wait "$LUAKIT_PID" #Wait for luakit to exit to allow for clean-up on termination
else ### Debug mode
    bashio::log.info "Entering debug mode (X & $WINMGR window manager but no luakit browser)..."
    exec sleep infinite
fi
