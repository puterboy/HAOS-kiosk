#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
VERSION="1.0.1"
################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: run.sh
# Version: 1.0.1
# Copyright Jeff Kosowsky
# Date: August 2025
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
#         XORG_CONF
#         XORG_APPEND_REPLACE
#         DEBUG_MODE
#         ONSCREEN_KEYBOARD
#         PERSIST_ONSCREEN_KEYBOARD_CONFIG
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
#     - Map Touch inputa as appropriate
#     - Set keyboard layout
#     - Start a virtual keyboard if USE_VIRTUAL_KEYBOARD is True
#     - Poll to check if monitor wakes up and if so, reload luakit browser
#     - Launch fresh Luakit browser for url: $HA_URL/$HA_DASHBOARD
#       [If not in DEBUG_MODE; Otherwise, just sleep]
#
################################################################################
echo "." #Almost blank line (Note totally blank or white space lines are swallowed)
printf '%*s\n' 80 '' | tr ' ' '#' #Separator
bashio::log.info "######## Starting HAOSKiosk ########"
bashio::log.info "$(date) [Version: $VERSION]"

#### Clean up on exit:
TTY0_DELETED="" #Need to set to empty string since runs with nounset=on (like set -u)
ONSCREEN_KEYBOARD=false
PERSIST_ONSCREEN_KEYBOARD_CONFIG=false
KBD_PERSIST_FILE="/config/usr_custom_keyboad.ini"
cleanup() {
    local exit_code=$?
	[ ONSCREEN_KEYBOARD ] && [ PERSIST_ONSCREEN_KEYBOARD_CONFIG ] && [ ! rm -f "$KBD_PERSIST_FILE" ] && dconf dump / > "$KBD_PERSIST_FILE"
	[ -n "$(jobs -p)" ] && kill "$(jobs -p)"
	[ -n "$TTY0_DELETED" ] && mknod -m 620 /dev/tty0 c 4 0
    exit "$exit_code"
}
trap cleanup INT EXIT
unset ONSCREEN_KEYBOARD
unset PERSIST_ONSCREEN_KEYBOARD_CONFIG

################################################################################
#### Get config variables from HA add-on & set environment variables
function load_config_var() {
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
load_config_var XORG_CONF ""
load_config_var XORG_APPEND_REPLACE append
load_config_var DEBUG_MODE false
load_config_var ONSCREEN_KEYBOARD false
load_config_var PERSIST_ONSCREEN_KEYBOARD_CONFIG false

# Validate environment variables set by config.yaml
if [ -z "$HA_USERNAME" ] || [ -z "$HA_PASSWORD" ]; then
    bashio::log.error "Error: HA_USERNAME and HA_PASSWORD must be set"
    exit 1
fi

################################################################################
#### Start Dbus
# Avoids waiting for DBUS timeouts (e.g., luakit)
# Allows luakit to enfoce unique instance by default
DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    bashio::log.warning "WARNING: Failed to start dbus-daemon"
fi
bashio::log.info "DBus started with: DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
export DBUS_SESSION_BUS_ADDRESS

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

#### Start Xorg in the background
rm -rf /tmp/.X*-lock #Cleanup old versions

# Modify 'xorg.conf' as appropriate
if [[ -n "$XORG_CONF" && "${XORG_APPEND_REPLACE}" = "replace" ]]; then
    bashio::log.info "Replacing default 'xorg.conf'..."
    echo "${XORG_CONF}" >| /etc/X11/xorg.conf
else
    cp -a /etc/X11/xorg.conf{.default,}
    if [ "$(uname -m)" = "aarch64" ]; then # Add "kmsdev" line to Device Section for Rpi
        sed -i '/Section "Device"/,/EndSection/ s#^\( *Option *"DRI" *"3"\)#\1\n    Option "kmsdev" "/dev/dri/card1"#' /etc/X11/xorg.conf
    fi

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

#### Start Openbox in the background
openbox &
O_PID=$!
sleep 0.5  #Ensure Openbox starts
if ! kill -0 "$O_PID" 2>/dev/null; then #Checks if process alive
    bashio::log.error "Failed to start Openbox window manager"
    exit 1
fi
bashio::log.info "Openbox started successfully..."

#### Configure screen timeout (Note: DPMS needs to be enabled/disabled *after* starting Openbox)
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

#### Launch virtual keyboard if needed - note virtual keyboard should automatically inherit $KEYBOARD_LAYOUT
if [ "$ONSCREEN_KEYBOARD" = true ]; then
	bashio::log.info "Configuring onscreen keyboard"

	if [ "$PERSIST_ONSCREEN_KEYBOARD_CONFIG" = true ] && [ -f "$KBD_PERSIST_FILE" ]; then
  		bashio::log.info "Restoring onscreen keyboard setup"

 		### Load all non-default settings from file and apply them
   		dconf load / < "$KBD_PERSIST_FILE"	
 	else
  		bashio::log.info "Using default onscreen keyboard setup"

  		### Delete settings file if it exists 
 		rm -f "$KBD_PERSIST_FILE"

 		### Set default layout, theme and colors
		dbus-run-session -- dconf write /org/onboard/layout \''/usr/share/onboard/layouts/Small.onboard'\'
  		dbus-run-session -- dconf write /org/onboard/theme \''/usr/share/onboard/themes/Blackboard.theme'\'
		dbus-run-session -- dconf write /org/onboard/theme-settings/color-scheme \''/usr/share/onboard/themes/Charcoal.colors'\'
  
		### Determine screen geometry as reported by X
     	if [ "$ROTATE_DISPLAY" = normal ] || [ "$ROTATE_DISPLAY" = inverted ] ; then
	  		SCRN_WIDTH=$(xrandr --query --verbose | awk '/ width/ {print $3}')
	  		SCRN_HEIGHT=$(xrandr --query --verbose | awk '/ height/ {print $3}')
	    else
	  		SCRN_WIDTH=$(xrandr --query --verbose | awk '/ height/ {print $3}')
	  		SCRN_HEIGHT=$(xrandr --query --verbose | awk '/ width/ {print $3}')
	    fi

  		### Set default keyboard height (1/2 or 1/4 of screen), width (full width) and position (centered, flush with bottom)
	 	if [ $SCRN_WIDTH -ge $SCRN_HEIGHT ] ; then
			dbus-run-session -- dconf write /org/onboard/window/landscape/height $(("$SCRN_HEIGHT"/2))
			dbus-run-session -- dconf write /org/onboard/window/landscape/width "$SCRN_WIDTH"
			dbus-run-session -- dconf write /org/onboard/window/landscape/x 0
			dbus-run-session -- dconf write /org/onboard/window/landscape/y $(("$SCRN_HEIGHT"/2-1))
	  	else
			dbus-run-session -- dconf write /org/onboard/window/portrait/height $(("$SCRN_HEIGHT"/4))
			dbus-run-session -- dconf write /org/onboard/window/portrait/width "$SCRN_WIDTH"
			dbus-run-session -- dconf write /org/onboard/window/portrait/x 0
			dbus-run-session -- dconf write /org/onboard/window/portrait/y $(("$SCRN_HEIGHT"*3/4-1))
	    fi

	  	### Enable keyboard to auto appear when inputting text
		dbus-run-session -- dconf write /org/onboard/xembed-onboard false # do not start in XEmbed mode 
		dbus-run-session -- dconf write /org/onboard/auto-show/enabled true # enable auto show
		dbus-run-session -- dconf write /org/onboard/auto-show/tablet-mode-detection-enabled false # shows keyboard only in tablet mode. I had to disable it to make it work
		dbus-run-session -- dconf write /org/onboard/window/force-to-top true # always show in front
	 	dbus-run-session -- gsettings set org.gnome.desktop.interface toolkit-accessibility true # disable gnome assessibility popup
	fi

	### Launch keyboard
 	bashio::log.info "Starting onscreen keyboard"
	dbus-run-session onboard &
fi

#### Poll to send <Control-r> when screen unblanks to force reload of luakit page if BROWSWER_REFRESH set
if [ "$BROWSER_REFRESH" -ne 0 ]; then
    (
        PREV=""
        while true; do
            if pgrep luakit > /dev/null; then
                STATE=$(xset -q | awk '/Monitor is/ {print $3}')
                [[ "$PREV" == "Off" && "$STATE" == "On" ]] && xdotool key --clearmodifiers ctrl+r
                PREV=$STATE
            fi
            sleep 5; #Wait between polling attempts
        done
    )&
    bashio::log.info "Polling to refresh Luakit browser after wakeup..."
fi

if [ "$DEBUG_MODE" != true ]; then
    ### Run Luakit in the foreground
    bashio::log.info "Launching Luakit browser: $HA_URL/$HA_DASHBOARD"
    exec luakit -U "$HA_URL/$HA_DASHBOARD"
	

	##### Persist virtual keyboard settings if needed
	#if [ "$ONSCREEN_KEYBOARD" = true ]; then
	#	if [ "$PERSIST_ONSCREEN_KEYBOARD_CONFIG" = true ]; then
	# 		bashio::log.info "Backing up onscreen keyboard setup"
	#   
	# 		# Save only non-default settings
	#   		rm -f "$KBD_PERSIST_FILE"
	#   		dconf dump / > "$KBD_PERSIST_FILE"
	#	fi
	#fi
else ### Debug mode
    bashio::log.info "Entering debug mode (X & Openbox but no luakit browser)..."
    exec sleep infinite
fi
