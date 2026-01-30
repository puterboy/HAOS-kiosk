# HAOS-kiosk

Display HA dashboards in kiosk mode directly on your HAOS server.

## Author: Jeff Kosowsky (version: 1.3.0, February 2026)

## Description

Launches X-Windows on local HAOS server followed by OpenBox window manager
and Luakit browser starting with your configured default Home Assistant
dashboard.

- Standard mouse, touchscreen, and keyboard interactions should work
  automatically as well as audio
- Supports touchscreens gestures, screen rotation, and onscreen keyboard
- Includes REST API that can be used to control the display state and to
  send new URLs (e.g., dashboards) to the kiosk browser.

You can press `ctl-R` at any time to refresh ( reload) the browser. \
Alternatively, you can right click (or long press touchscreen) to access
browser menu that includes options for page `Back`, `Forward`, `Stop`, and
`Reload`.

**NOTE:** You must enter your HA username and password in the
*Configuration* tab for the Add-on to start.

**NOTE:** The Add-on requires a valid, connected display in order to
start.\
If your display does not show up, try rebooting and restarting the Add-on
with the display attached

**NOTE:** Should support any standard mouse, touchscreen, keypad and
touchpad so long as its `/dev/input/eventN` number is less than 25.

**NOTE:** If you encounter issues with the Add-on, please first check the
HAOSKiosk github
[issues page](https://github.com/puterboy/HAOS-kiosk/issues) (open and
closed), then try the testing branch (add the following url to the
repository: https://github.com/puterboy/HAOS-kiosk#testing). If still
please file an
[issue on github](https://github.com/puterboy/HAOS-kiosk/issues) and
\*\*include full details of your setup (including computer hardware and
display type details)and what you did along with a complete log.

You can also use the `screenshot` REST API or keybinding (`Ctl+Alt+k`) or
touch gesture (Quadruple 3 finger tap) to save a screenshot to
`/media/screenshots`

### If you appreciate my efforts:

[![Buy Me a Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/puterboy)

______________________________________________________________________

## Installation

1. Click the **ADD ADD-ON REPOSITORY** button below.

   [![Open your Home Assistant instance and show the add Add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fputerboy%2FHAOS-kiosk)

   - Click **Add → Close** (You might need to enter the **internal IP
     address** of your Home Assistant instance first) *or* go to the
     **Add-on store**.
   - Click **⋮ → Repositories**
   - Fill in `https://github.com/puterboy/HAOS-kiosk`
   - Click **Add → Close**

2. Click on the Add-on, press **Install** and wait until the Add-on is
   installed.

3. You must enter your HA username and password in the **Configuration**
   tab.

4. Press **Start** to run the Add-on.

**If you are having trouble installing the add-on or getting displays and
touchscreens working, please see the github issues page
(https://github.com/puterboy/HAOS-kiosk/issues)as many common issues have
already been addressed and resolved**

### Notes

- If screen is not working on an RPi3, try adding the following lines to
  the `[pi3]` section of your `config.txt` on the boot partition:
  ```
  dtoverlay=vc4-fkms-v3d
  max_framebuffers=2
  ```

______________________________________________________________________

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

Prefer dark mode where supported if `True`, otherwise prefer light mode.
(Default: True)

NOTE: This applies to *all* url's.

### HA Theme

Set HA theme to given string. This setting applies only to HA dashboards
and may override the value of DARK_MODE unless the theme support both dark
and light variants. See HACS for downloadable themes to use. (Default:
True)

NOTE: You can force the dark or light default theme specifically for HA
dashboards by setting the theme to `{"dark":true}` or `{"dark":false}`
respectively. Similarly, leaving the theme blank (or setting it to `{}` or
`Home Assistant`) is equivalent to "auto", in which case the default light
or dark scheme is governed by the value of DARK_MODE.

### HA Sidebar

Presentation of left sidebar menu (device-specific).\
Options include: (Default: None)

- Full (icons + names)
- Narrow (icons only)
- None (hidden)

### Rotate Display

Rotate the display relative to standard view.\
Options include: (Default: Normal)

- Normal (No rotation)
- Left (Rotate 90 degrees clockwise)
- Right (Rotate 90 degrees counter-clockwise)
- Inverted (Rotate 180 degrees)

### Map Touch Inputs

Map touch inputs to the selected video output, so that the touch devices
get rotated consistently with the video output. (Default: True)

### Cursor Timeout

Time in seconds for cursor to be hidden after last mouse movement or touch.
Cursor will reappear when mouse moved or screen touched again. Set to `0`
to *always* show cursor. Set to `-1` to *never* show cursor. (Default: 5
seconds)

### Keyboard Layout

Set the keyboard layout and language. (Default: us)

### Onscreen Keyboard

Display an on-screen keyboard when keyboard input expected if set to
`true`. (Default: True)

To move, resize, or configure keyboard options, long press on the `...`
within the `Return` key. You can also resize the keyboard by pressing and
dragging along the keyboard edges.

You can manually toggle keyboard visibility on/off by tapping extreme top
right of screen or triple-clicing.

See https://github.com/dr-ni/onboard for more details

### Save Onscreen Config

Save and restore changes to onscreen keyboard settings made during each
session if set to `True`. Overwrites default settings. (Default: True)

### Xorg.conf

Append to or replace existing, default xorg.conf file.\
Select 'Append' or 'Replace options.\
To restore default, set to empty and select 'Append' option.

### Audio Sink

Set the audio output sink. (Default: Auto)\
Options include: 'Auto', 'HDMI', 'USB', 'NONE', picking the first
respective audio output, HDMI audio output, and USB/Aux audio output.

### REST IP address

IP address where the REST Server listens. (Default: 127.0.0.1) By default,
for security it only accepts request from localhost -- meaning that REST
commands must originate from the homeassistant localhost.

If you want to accept requests from anywhere, then set to \`\`0.0.0.0\` BUT
BE FOREWARNED that unless you set up and use a REST Bearker Token, this is
a security vulnerability.

### REST Port

Port used for the REST API. Must be between 1024 and 49151. (Default: 8080)

Note for security REST server only listens on localhost (127.0.0.1)

### REST Bearer Token

Optional authorization token for REST API. (Default: "") If set, then you
must add line `-H "Authorization: Bearer <REST_BEARER_TOKEN>"` to REST API
calls.

### Gestures

Editable list of JSON-like key-value pairs where the key represents a
(valid) *gesture string* and the value is a structured set of one or more
*action* commands. See section "GESTURE COMMANDS" below for more details,
examples, and default gestures.

### Command Whitelist Regex

Regex (Python) of shell command that can be used in creating gesture action
commands or when running the `run_command` and `run_commands` REST APIs.

If left blank, then all commands are allowed except for those blacklisted
as dangerous (otherwise, whitelist overrides internal blacklist).

The pre-defined command blacklist includes commands like:

```
   python
   ash, bash, sh, su
   env, exec
   kill, killall, pkill
   cp, chmod, chown, dd, ln, mv, rm, tar
   mount, umount
   curl, nc, wget
   find, xargs"
```

Note that if you want to truly allow *all* commands, then use the wildcard
`.*` but beware that it is DANGEROUS. If you want to disallow all commands
set the regex to `^$`.

Note that regardless of setting only commands found in `/bin`, `/usr/bin`,
and `/usr/local/bin` of the HAOSKiosk Add-on container are allowed.

### VNC SERVER

Launch VNC Server on port 5900 if password non-blank. If password set to
'-', then don't require any password. This can be used to view or debug the
kiosk remotely.

To view launch a vnc server (e.g., RealVNC) and point it to port 5900 on
your homeassistant instance (e.g., `homeassistant:5900`)

*Use with caution* as it runs unencrypted and is accessible anywhere on
your network.

### Debug

For debugging purposes, launches `Xorg` and `openbox` and then sleeps
without launching `luakit`.\
Manually, launch `luakit` (e.g.,
`luakit -U localhost:8123/<your-dashboard>`) from Docker container.\
E.g., `sudo docker exec -it addon_haoskiosk bash`

______________________________________________________________________

## REST APIs

### launch_url {"url": "\<url>"}

Launch the specified 'url' in the kiosk display. Overwrites current active
tab. If no url supplied, use HA_URL/HA_DASHBOARD as default url.

Usage:

```
curl -X POST http://localhost:<REST_PORT>/launch_url
curl -X POST http://localhost:<REST_PORT>/launch_url -H "Content-Type: application/json" -d '{"url": "<URL>"}'
```

### refresh_browser

Refresh browser

Usage:

`curl -X POST http://localhost:<REST_PORT>/refresh_browser`

### is_display_on

Returns boolean depending on whether display is on or off.

Usage:

`curl -X GET http://localhost:8080/is_display_on`

### display_on {"timeout": "\<timeout>"}

Turn on display. If optional payload given, then set screen timeout to
`<timeout>` which if 0 means *never* turn off screen and if positive
integer then turn off screen after `<timeout>` seconds

Usage:

```
curl -X POST http://localhost:<REST_PORT>/display_on
curl -X POST http://localhost:8080/display_on -H "Content-Type: application/json" -d '{"timeout": <timeout>}'
```

### display_off

Turn off display

Usage:

`curl -X POST http://localhost:<REST_PORT>/display_off`

### xset

Run `xset <args>` to get/set display information. In particular, use `-q`
to get display information. Can only be run from localhost unless
REST_BEARER_TOKEN set and used.

Usage:

`curl -X POST http://localhost:<REST_PORT>/xset -H "Content-Type: application/json" -d '{"args": "<arg-string>"}'`

### run_command {"cmd": "\<command>"}

Run `command` in the HAOSKiosk Docker container where `cmd_timeout` is an
optional timeout in seconds.

Commands are subject to blacklist/whitelist rules detailed above. Can only
be run from localhost unless REST_BEARER_TOKEN set and used.

Usage:

`curl -X POST http://localhost:<REST_PORT>/run_command -H "Content-Type: application/json" -d '{"cmd": "<command>", "cmd_timeout": <seconds>}'`

### run_commands {"cmds": ["\<command1>", "\<command2>",...], "cmd_timeout": \<seconds>}}

Run multiple commands in the HAOSKiosk Docker container where `cmd_timeout`
is an optional timeout in seconds.

Commands are subject to blacklist/whitelist rules detailed above. Can only
be run from localhost unless REST_BEARER_TOKEN set and used.

Usage:

`curl -X POST http://localhost:<REST_PORT>/run_commands -H "Content-Type: application/json" -d '{"cmds": ["<command1>", "<command2>",...], "cmd_timeout": <seconds>}'`

**NOTE:** The API commands logs results to the HAOSkiosk log and return:

```
{
  "success": bool,
  "result": {
    "success": bool,
    "stdout": str,
    "stderr": str,
    "error": str (optional)
  }
}
```

Note that `run_commands` returns an array of `"results"` of form:
`"results": [{"success": bool, "stdout": str, "stderr": str, "error": str (optional)},...]`

You can format the stdout (and similarly stderr) by piping the output to:
`jq -r .result.stdout`

In the case of `run_commands`, pipe the output to:
`jq -r '.results[]?.stdout'`

### screenshot

Take screen screenshot with optional filename, quality, and delay before
screenshot. Quality only affects jpeg images

Output format is jpeg unless optional filename ends in .bmp, .png, .pnm, or
.tiff

Screenshots are saved to `/media/screenshots`.

Usage:

```
curl -X POST http://localhost:8080/screenshot
curl -X POST http://localhost:8080/screenshot -H "Content-Type: application/json"
     -d '{"filename": "<filename>", "quality": <1-100>, "delay: <seconds>}'
```

### current_processes

Return number of currently running concurrent processes out of max allowed.

Usage: `curl -X GET http://localhost:8080/current_processes`

### disable_inputs

Disable keyboard and pointer (e.g., mouse, touch) inputs. Can only be run
from localhost unless REST_BEARER_TOKEN set and used.

Usage:

`curl -X POST http://localhost:<REST_PORT>/disable_inputs`

### enable_inputs

(Re)enable keyboard and pointer (e.g., mouse, touch) inputs. Can only be
run from localhost unless REST_BEARER_TOKEN set and used.

Usage:

`curl -X POST http://localhost:<REST_PORT>/enable_inputs`

### mute_audio

Mute audio output for default audio sink. Returns final mute state.

Usage:

`curl -X POST http://localhost:<REST_PORT>/mute_audio`

### unmute_audio {"volume": "\<volume>"}

Unmute audio output for default audio sink. Optionally, set volume (integer
between 0 and 150). Returns final volume and mute state

Usage:

```
curl -X POST http://localhost:<REST_PORT>/unmute_audio
curl -X POST http://localhost:8080/unmute_audio -H "Content-Type: application/json" -d '{"volume": <volume>}'
```

### toggle_audio

Toggle mute for default audio sink. Returns final mute state.

Usage:

`curl -X POST http://localhost:<REST_PORT>/toggle_audio`

#### HA REST Command Syntax

You can also configure all the above REST commands in your
`configuration.yaml` as follows (assuming REST_PORT=8080)

```
rest_command:
  haoskiosk_launch_url:
    url: "http://localhost:8080/launch_url"
    method: POST
    content_type: "application/json"
    payload: '{"url": "{{ url }}"}'

  haoskiosk_refresh_browser:
    url: "http://localhost:8080/refresh_browser"
    method: POST
    content_type: "application/json"
    payload: "{}"

  haoskiosk_is_display_on:
    url: "http://localhost:8080/is_display_on"
    method: GET
    content_type: "application/json"

  haoskiosk_display_on:
    url: "http://localhost:8080/display_on"
    method: POST
    content_type: "application/json"
    payload: >-
      {{
        {
          'timeout': timeout | int if timeout is defined and timeout is number and timeout >= 0 else none
        }
        | to_json
      }}

  haoskiosk_display_off:
    url: "http://localhost:8080/display_off"
    method: POST
    content_type: "application/json"
    payload: "{}"

  haoskiosk_xset:
    url: "http://localhost:8080/xset"
    method: POST
    content_type: "application/json"
    payload: '{"args": "{{ args }}"}'

  haoskiosk_run_command:
    url: "http://localhost:8080/run_command"
    method: POST
    content_type: "application/json"
    payload: >-
      {{
        {
          'cmd': cmd,
          'cmd_timeout': cmd_timeout | int if cmd_timeout is defined and cmd_timeout is number  and cmd_timeout > 0 else none
        }
        | to_json
      }}


  haoskiosk_run_commands:
    url: "http://localhost:8080/run_commands"
    method: POST
    content_type: "application/json"
    payload: >-
      {{
        {
          'cmds': cmds,
          'cmd_timeout': cmd_timeout | int if cmd_timeout is defined and cmd_timeout is number and cmd_timeout > 0 else none
        }
        | to_json
      }}

  haoskiosk_screenshot:
    url: "http://localhost:8080/screenshot"
    method: POST
    content_type: "application/json"
    payload: >-
      {{
        {
          'delay': delay | int if delay is defined and delay | int(0) >= 0 else none,
          'filename': filename if filename is defined and filename != "" and "/" not in filename and "\0" not in filename else none,
          'quality': quality | int if quality is defined and 1 <= quality | int <= 100 else none
        }
        | to_json
      }}

  haoskiosk_current_processes:
    url: "http://localhost:8080/current_processes"
    method: GET
    content_type: "application/json"

  haoskiosk_disable_inputs:
    url: "http://localhost:8080/disable_inputs"
    method: POST
    content_type: "application/json"
    payload: "{}"

  haoskiosk_enable_inputs:
    url: "http://localhost:8080/enable_inputs"
    method: POST
    content_type: "application/json"
    payload: "{}"

  haoskiosk_mute_audio:
    url: "http://localhost:8080/mute_audio"
    method: POST
    content_type: "application/json"

  haoskiosk_unmute_audio:
    url: "http://localhost:8080/unmute_audio"
    method: POST
    content_type: "application/json"
    payload: >-
      {{
        {
          'volume': volume | int if volume is defined and volume is number and 0 <= volume | int <= 150 else none
        }
        | to_json
      }}

  haoskiosk_toggle_audio:
    url: "http://localhost:8080/toggle_audio"
    method: POST
    content_type: "application/json"
```

Note if optional \`REST_BEARER_TOKEN~ is set, then add the following two
authentication lines to each of the above stanzas:

```
    headers:
      Authorization: Bearer <REST_BEARER_TOKEN>
```

The rest commands can then be referenced from automation actions as:
`rest_command.haoskiosk_<command-name>`

#### Examples

```
actions:
  - action: rest_command.haoskiosk_launch_url
  - action: rest_command.haoskiosk_launch_url
    data:
      url: "https://homeassistant.local/my_dashboard"

  - action: rest_command.haoskiosk_refresh_browser

  - action: rest_command.haoskiosk_is_display_on

  - action: rest_command.haoskiosk_display_on
  - action: rest_command.haoskiosk_display_on
    data:
      timeout: 300

  - action: rest_command.haoskiosk_display_off

  - action: rest_command.haoskiosk_xset
    data:
      args: "<arg-string>"

  - action: rest_command.haoskiosk_run_command
    data:
      cmd: "command"
      cmd_timeout: <seconds>

  - action: rest_command.haoskiosk_run_commands
    data:
      cmds:
        - "<command1>"
        - "<command2>"
        ...
      cmd_timeout: <seconds>

  - action: rest_command.haoskiosk_current_processes

  - action: rest_command.haoskiosk_disable_inputs

  - action: rest_command.haoskiosk_enable_inputs

  - action: rest_command.haoskiosk_mute_audio

  - action: rest_command.haoskiosk_unmute_audio
  - action: rest_command.haoskiosk_unmute_audio
    data:
      volume: 100

  - action: rest_command.haoskiosk_toggle_audio
```

### REST API Use Cases

1. Create automations and services to:

   - Turn on/off display based on time-of-day, proximity, event triggers,
     voice commands, etc.

     See 'examples' folder for trigger based on ultrasonic distance and HA
     boolean sensor.

   - Send dashboard or other url to HAOSKiosk display based on event
     triggers or pre-programmed rotation (e.g., to sequentially view
     different cameras).

   - Create simple screensavers using a loop to iterate through an image
     folder and call `launch_url`

     See 'examples' folder for simple Bash script example screensaver.

2. Use custom command(s) to change internal parameters of HAOSKiosk and the
   luakit browser configuration.

______________________________________________________________________

## Gesture Commands

Each Gesture Command is a JSON-like key-value pair where the key is a valid
*Gesture String* corresponding to a specific sequence of button clicks or
finger taps and the value is an *Action Command* containing a structured
set of one or more commands to execute when the gesture is recognized.

The formats of the Gesture Strings and Action Commands are precisely
defined, so if they fail to load check your log for error messages.

### Gesture String Keys

Each Gesture String key is of form:

**`<CONTACTS>_<DEVICE>_<CLICKS>_<GESTURE>`**

where:

**`<CONTACTS>`** field captures he maximal contact set during the gesture.
Either:

- A number (`N`, `N+`, `N-`) representing the (maximum) number of contacts
  (buttons or fingers), where `N+` and `N-` respectively indicate greater
  than and less than or equal to `N`
  - List of button numbers and/or corresponding button names (for
    mouse-type devices only) e.g., `[Left, Right]`, `[1, 3]`, `[Left, 3]`

**`<DEVICE>`** field identifies the type of input contact either by:

- Device Type (e.g., `MOUSE`, `TOUCH`) or the wildcard `ANY`
- Mechanism (e.g., `Button`, `Finger`)

**`<CLICKS>`** field captures the number (`M`, `M+`, `M-`) of clicks/taps
in the gesture where `M+` and `M-` are respectively greater than or less
than or equal to `M` (e.g., `1` for single-click, `2` for double-click,
`2+` for 2 or more clicks)

**`<GESTURE>`** field specifies the general class or device-specific name
of the gesture

- Class (e.g., `CLICKTAP`, `DRAG`, `SWIPE`, `LONG`, `CORNER_<name>`) or the
  wildcard `ANY`
- Friendly Name (e.g., `Click`, `Tap`, `Drag`, `Swipe`, `Long Click`,
  `Long Tap`). Note the names may be device-specific (e.g., Click for
  Mouse, Tap for Touch)

#### Additional notes regarding gesture naming:

- `ANY` is a wildcard matching any gesture
- Corners are named: CORNER_TOPLEFT, CORNER_TOPRIGHT, CORNER_BOTLEFT,
  CORNER_BOTRIGHT
- `DRAG` and `SWIPE` differ primarily in velocity (`SWIPE` is faster)
- Both `DRAG` and `SWIPE` may include suffixes `_LEFT`, `_RIGHT`, `_UP`, or
  `_DOWN`
- Undirected `DRAG`/`SWIPE` act as wildcards for their directional variants
- `LONG` can take the optional device-specific suffixes `_CLICK` or `TAP`
- CORNER\_<name> triggers when click or tap is in within "click_dim" of the
  named corner (default 5 pixels)
- `DRAG`, `SWIPE`, and `LONG` (and their variants) are always single-click
  gestures
- Matching is case-insensitive

Note that Gesture String Keys are matched in order, so that you should
always enter keys from particular to more general when using wildcards

#### Validity Checks

- Single-click gestures cannot be used if more than 1 Click/Tap
- `Click` applies only to mouse devices; `Tap` applies only to touch
  devices

#### Valid Examples

```
[Left, Right]_MOUSE_3_CLICKTAP
[1,2,3]_MOUSE_1+_CORNER_TOPRIGHT
2_TOUCH_1_DRAG_LEFT
2_Button_1_Long Click
3_Finger_2_Tap
2+_Finger_1_Swipe_down
1_ANY_2-_CLICKTAP
1+_ANY_1+_ANY
```

#### Invalid Examples

```
1_Mouse_3-Tap     (Tap is for Touch)
1-Touch_2-Long    (Long gestures must be single contact)
```

### Action Commands

Action commands may be expressed in one of three forms:

1. **Single command string** e.g., `"ls -a -l"` Note that an empty string
   acts as a No-Op -- i.e., it will be ignored and can be used with
   wildcard gestures to block actions of lower priority.

2. **List of commands** - Each command may be either:

   - A string: `"echo hello"`
   - An argv-style list: `["ls", "-a", "-l"]`

Example `["echo hello", ["ls", "-a", "-l"]]`

Note that the commands themselves can either be shell commands or
kiosk-specific internal commands (see below) that begin with the prefix
'kiosk.'

3. **Command dictionary** with required key `"cmds":` and optional keys:
   `"msg":` and `"timeout"`

Examples:

```
{"cmds": "ls -al", "msg": "list all files", "timeout": 1}
{"cmds": ["echo hello", ["ls", "-al"]], "msg": "echo hello and list all files", "timeout": 5}
```

#### Kiosk-specific internal commands

- **kiosk.back**: Go back in browser history
- **kiosk.forward**: Go forward in browser history
- **kiosk.refresh_browser**: Reload current page
- **kiosk.launch_url <url>**: Launch <url> in existing tab/window.\
  If no <url> given, use HA_URL/HA_DASHBOARD as default
- **kiosk.display_on <timeout>**: Turn on display with optional timeout
- **kiosk.display_off**: Turn off display immediately
- **kiosk.toggle_keyboard**: Toggle onscreen keyboard
- **kiosk.toggle_audio**: Toggle mute state of default audio sink

### Defaults Gesture Command Bindings

The following gestures are included by default (but can be removed by
clicking on the `X` next to them):

- **Single Tap or Click in Top Right Corner**: *Toggle on-screen keyboard*

```
"1_ANY_1_CORNER_TOPRIGHT": {"cmds": "kiosk.toggle_keyboard", "msg": "Toggling Onboard keyboard..."}
```

- **Left Triple Mouse Click**: *Toggle on-screen keyboard*

```
"[Left]_MOUSE_3_CLICK": {"cmds": "kiosk.toggle_keyboard", "msg": "Toggling Onboard keyboard..."}
```

- **3-Finger Single Tap**: *Toggle on-screen keyboard*

```
"3_TOUCH_1_TAP": {"cmds": "kiosk.toggle_keyboard", "msg": "Toggling Onboard keyboard..."}
```

- **3-Finger Double Tap**: *Refresh Browser*

```
"3_TOUCH_2_TAP": {"cmds": "kiosk.refresh_browser", "msg": "Refresh Browser"}
```

- **3-Finger Triple Tap**: *Toggle audio mute*

```
"3_TOUCH_3_TAP": {"cmds": "kiosk.toggle_audio", "msg": "Toggle audio mute"}'
```

- **3-Finger Left Swipe**: *Go forward one element in browser history*

```
"3_TOUCH_1_SWIPE_LEFT": {"cmds": "kiosk.forward", "msg": "Go forward in the history browser"}
```

- **3-Finger Right Swipe**: *Go back one element in browser history*

```
"3_TOUCH_1_SWIPE_RIGHT": {"cmds": "kiosk.back", "msg": "Go back in the history browser"}
```

- **2-Finger Triple Tap**: *Restore Default HA dashboard
  (HA_URL/HA_Dashboard)*

```
"2_TOUCH_3_TAP": {"cmds": "kiosk.launch_url", "msg": "Restore default dashboard: HA_URL/HA_DASHBOARD"}
```

- **2-Finger Quadruple Tap**: *Open Google search*

```
"2_TOUCH_4_TAP": {"cmds": [["kiosk.lauch_url", "www.google.com"]], "msg": "Open Google search"}'
```

Note if you didn't have the built-in functions, you could have manually
implemented the above as:

```
"1_ANY_1_CORNER_TOPRIGHT": {"cmds": [["dbus-send", "--type=method_call", "--dest=org.onboard.Onboard", "/org/onboard/Onboard/Keyboard", "org.onboard.Onboard.Keyboard.ToggleVisible"]], "msg": "Toggling Onboard keyboard..."}

"[Left]_MOUSE_3_CLICK": {"cmds": [["dbus-send", "--type=method_call", "--dest=org.onboard.Onboard", "/org/onboard/Onboard/Keyboard", "org.onboard.Onboard.Keyboard.ToggleVisible"]], "msg": "Toggling Onboard keyboard..."}

"3_TOUCH_1_TAP": {"cmds": [["dbus-send", "--type=method_call", "--dest=org.onboard.Onboard", "/org/onboard/Onboard/Keyboard", "org.onboard.Onboard.Keyboard.ToggleVisible"]], "msg": "Toggling Onboard keyboard..."}

"3_TOUCH_2_TAP": {"cmds": [["xdotool", "key", "--clearmodifiers ctrl+r"]], "msg": "Refresh Browser"}

"3_TOUCH_3_TAP": {"cmds": [["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]], "msg": "Toggle audio mute"}'

"3_TOUCH_1_SWIPE_LEFT": {"cmds": [["xdotool", "key", "--clearmodifiers", "ctrl+Right"]], "msg": "Go forward in the history browser"}

"3_TOUCH_1_SWIPE_RIGHT": {"cmds": [["xdotool", "key", "--clearmodifiers", "ctrl+Left"]], "msg": "Go back in the history browser"}

"2_TOUCH_3_TAP": {"cmds": "luakit \"$HA_URL/$HA_DASHBOARD\"", "msg": "Restore default dashboard"}

"2_TOUCH_4_TAP": {"cmds": "luakit \"www.google.com\"", "msg": "Open Google search"}'
```

______________________________________________________________________

## KEYBOARD SHORTCUTS

The following new fixed keyboard shortcuts are defined (but subject to
change).

- **Ctrl+o:** *Toggle Onboard onscreen keyboard*

- **Ctrl+r:** *Reload page*

- **Ctrl+Left:** *Go back in the browser tab history*

- **Ctrl+Right:** *Go forward in the browser tab history*

- **Ctrl+Alt+t:** *Open new tab*

- **Ctrl+Alt+Shift+t:** *Close current tab*

- **Ctrl+Alt+w:** *Open new window*

- **Ctl+Alt+Left:** *Previous tab*

- **Ctl+Alt+Right:** *Next tab*

- **Ctl+Alt+Shift+Left:** *Previous window* (Also: **Alt+Shift+Tab**)

- **Ctl+Alt+Shift+Right:** *Next window* (Also: **Alt+Tab**)

- **Ctrl+Alt+k:** *Take screenshot and save to /media/screenshots*

Note that the Onbox Window manager defines many other default bindings.

______________________________________________________________________

## MISCELLANEOUS NOTES

#### Luakit browser

The Luakit browser is launched in kiosk-like (*passthrough*) mode. In
general, you want to stay in `passthrough` mode to preserve the kiosk-like
experience and pass all keystrokes to the browser page (except for explicit
bindings as defined above)

Luakit modes and commands are similar to vi

- To enter *normal* mode (similar to command mode in `vi`), press
  `ctl-alt-esc`.

- To return to *passthrough* mode, press `ctl-Z` or alternatively, press
  `i` to enter *insert*

See [luakit documentation](https://wiki.archlinux.org/title/Luakit) for
further usage information and available commands.
