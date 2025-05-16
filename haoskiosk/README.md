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
Default:"" (loads the default `Lovelace` dashboard)

### Login Delay

Delay in seconds to allow login page to load.\
Default: 1 second

### Zoom Level

Level of zoom with `100` being 100%.\
Default: 100%

### Browser Refresh

Time between browser refreshes. Set to `0` to disable.\
Recommended because with the default RPi config, console errors *may*
overwrite the dashboard.\
Default: 600 seconds

### Screen Timeout

Time before screen blanks in seconds. Set to `0` to never timeout.

Default: 0 seconds (never timeout)

### HDMI Port

HDMI output port. Technically can be `0` or `1` (Default: 0).\
BUT currently has no effect on stock HAOS on RPi since configured to mirror
HDMI0 onto HDMI1.

### HA Theme

Theme used by HA frontend (device-specific).\
Options include: (Default: Dark)

- Auto
- Dark
- Light
- None

### HA Sidebar

Presentation of left sidebar menu (device-specific).\
Options include: (Default: None)

- Full (icons + names)
- Narrow (icons only)
- None (hidden)
