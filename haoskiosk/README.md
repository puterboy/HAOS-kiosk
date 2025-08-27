# HAOS-kiosk

Display HA dashboards in kiosk mode directly on your HAOS server.

## Author: Jeff Kosowsky

## Description

Launches X-Windows on local HAOS server followed by OpenBox window manager
and Luakit browser.\
Standard mouse and keyboard interactions should work automatically.

**NOTE:** You must enter your HA username and password in the
*Configuration* tab for add-on to start.

**NOTE:** If display does not show up, reboot with display attached (via
HDMI cable)

**Note:** Luakit is launched in kiosk-like (*passthrough*) mode.\
To enter *normal* mode (similar to command mode in `vi`), press
`ctl-alt-esc`.\
You can then return to *passthrough* mode by pressing `ctl-Z` or enter
*insert* mode by pressing `i`.\
See luakit documentation for available commands.\
In general, you want to stay in `passthrough` mode.

**NOTE:** Should support any standard mouse, touchscreen, keypad and
touchpad so long as their /dev/input/eventN number is less than 25.

## Configuration Options

### HA Username [required]

Enter your Home Assistant login name.

### HA Password [required]

Enter your Home Assistant password.

### HA URL

Default: `http://localhost:8123`\
In general, you shouldn't need to change this since this is running on the
local server.

### HA Dashboard

Name of starting dashboard.\
(Default: "" - loads the default `Lovelace` dashboard)

### Login Delay

Delay in seconds to allow login page to load.\
(Default: 1 second)

### Zoom Level

Level of zoom with `100` being 100%.\
(Default: 100%)

### Browser Refresh

Time between browser refreshes. Set to `0` to disable.\
Recommended because with the default RPi config, console errors *may*
overwrite the dashboard.\
(Default: 600 seconds)

### Screen Timeout

Time before screen blanks in seconds. Set to `0` to never timeout.
(Default: 0 seconds - never timeout)

### Output Number

Choose which of the *connected* video output ports to use. Set to `1` to
use the first connected port. If selected number exceeds number of
connected ports, then use last valid connected port. (Default: 1)

NOTE: This should always be set to `1` unless you have more than one video
output device connected. If so, use the logs to see how they are numbered.

### Dark Mode

Prefer dark mode where supported if `true` (Default: true)

### HA Sidebar

Presentation of left sidebar menu (device-specific).\
Options include: (Default: None)

- Full (icons + names)
- Narrow (icons only)
- None (hidden)

### ROTATE SCREEN

Rotate the display relative to standard view.\
Options include: (Default: Normal)

- Normal (No rotation)
- Left (Rotate 90 degrees clockwise)
- Right (Rotate 90 degrees counter-clockwise)
- Inverted (Rotate 180 degrees)

### MAP TOUCH INPUTS

Map touch inputs to the selected video output, so that the touch devices
get rotated consistently with the video output. (Default: True)

### CURSOR TIMEOUT

Time in seconds for cursor to be hidden after last mouse movement or touch.
Cursor will reappear when mouse moved or screen touched again. Set to `0`
to *always* show cursor. Set to `-1` to *never* show cursor. (Default: 5
seconds)

### KEYBOARD LAYOUT

Set the keyboard layout and language. (Default: us)

### XORG.CONF

Append to or replace existing, default xorg.conf file.\
Select 'Append' or 'Replace options.\
To restore default, set to empty and select 'Append' option.

### DEBUG

For debugging purposes, launches `Xorg` and `openbox` and then sleeps
without launching `luakit`.\
Manually, launch `luakit` (e.g.,
`luakit -U localhost:8123/<your-dashboard>`) from Docker container.\
E.g., `sudo docker exec -it addon_haoskiosk bash`

### USE VIRTUAL KEYBOARD

Launch a Onboard onscreen keyboard (Typically used for stand-alone touch screens).<br/>
Supported keyboard language should be inherited from regional settings, which are any of:
- bg_BG
- da_DK
- de_AT
- de_CH
- de_DE
- el_GR
- en_AU
- en_CA
- en_GB
- en_US
- eo_XX
- es_ES
- fr_FR
- ga_IE
- gd_GB
- it_IT
- lb_LU
- nl_AN
- nl_AW
- nl_BE
- nl_NL
- nl_SR
- pl_PL
- pt_BR
- pt_PT
- ro_RO
- ru_RU
- sv_SE
- tr_TR

(Default: False)

### VIRTUAL KEYBOARD LAYOUT
Configure onscreen keyboard layout to be any of:
- Compact.onboard
- Full Keyboard.onboard
- Grid.onboard
- Phone.onboard
- Small.onboard
- Whiteboard.onboard
- Whiteboard_wide.onboard

(Default: Small.onboard)

### VIRTUAL KEYBOARD THEME
Configure onscreen keyboard theme to be any of (be sure to preserve spaces in names):
- Ambiance.theme
- Blackboard.theme
- Classic Onboard.theme
- DarkRoom.theme
- Droid.theme
- HighContrast.theme
- HighContrastInverse.theme
- LowContrast.theme
- ModelM.theme
- Nightshade.theme
- Typist.theme

(Default: Blackboard.theme)

### VIRTUAL KEYBOARD_COLORS
Configure onscreen keyboard colors to be any of (be sure to preserve spaces in names):
- Aubergine.colors
- Black.colors
- Charcoal.colors
- Classic Onboard.colors
- DarkRoom.colors
- Granite.colors
- HighContrast.colors
- HighContrastInverseBlack.colors
- HighContrastInverseBlue.colors
- LowContrast.colors
- ModelM.colors
- Typist.colors

(Default: Charcoal.colors)
