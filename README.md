# HAOS-kiosk

Display HA dashboards in kiosk mode directly on your HAOS server.

## Author: Jeff Kosowsky (version: 1.2.0, December 2025)

## Description

Launches X-Windows on local HAOS server followed by OpenBox window manager
and Luakit browser.\
Standard mouse and keyboard interactions should work automatically.
Supports touchscreens (including onscreen keyboard) and screen rotation.
Includes REST API that can be used to control the display state and to send
new URLs (e.g., dashboards) to the kiosk browser.

You can press `ctl-R` at any time to refresh ( reload) the browser./
Alternatively, you can right click (or long press touchscreen) to access
browser menu that includes options for page `Back`, `Forward`, `Stop`, and
`Reload`.

**NOTE:** You must enter your HA username and password in the
*Configuration* tab for add-on to start.

**NOTE:** The add-on requires a valid, connected display in order to start.
\
If display does not show up, try rebooting and restarting the addon with
the display attached

**Note:** Luakit browser is launched in kiosk-like (*passthrough*) mode.\
To enter *normal* mode (similar to command mode in `vi`), press
`ctl-alt-esc`.\
You can then return to *passthrough* mode by pressing `ctl-Z` or enter
*insert* mode by pressing `i`.\
See luakit documentation for available commands.\
In general, you want to stay in `passthrough` mode.

**NOTE:** Should support any standard mouse, touchscreen, keypad and
touchpad so long as their /dev/input/eventN number is less than 25.

**NOTE:** If not working, please first check the bug reports (open and
closed), then try the testing branch (add the following url to the
repository: https://github.com/puterboy/HAOS-kiosk#testing). If still no
solution, file an issue on github
[bug report](https://github.com/puterboy/HAOS-kiosk/issues) and include
full details of your setup and what you did along with a complete log.

### If you appreciate my efforts:

[![Buy Me a Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/puterboy)

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
`true`. (Default: false)

To move, resize, or configure keyboard options, long press on the `...`
within the `Return` key. You can also resize the keyboard by pressing and
dragging along the keyboard edges.

You can manually toggle keyboard visibility on/off by tapping extreme top
right of screen or triple-clicing.

See https://github.com/dr-ni/onboard for more details

### Save Onscreen Config

Save and restore changes to onscreen keyboard settings made during each
session if set to `true`. Overwrites default settings. (Default: true)

### Xorg.conf

Append to or replace existing, default xorg.conf file.\
Select 'Append' or 'Replace options.\
To restore default, set to empty and select 'Append' option.

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

Optional authorization token for REST API. (Default: "") If set, then add
line `-H "Authorization: Bearer <REST_BEARER_TOKEN>"` to REST API calls.

### Allow User Commands

Allow user to run arbitrary one or more commands in the HAOSkiosk container
via the respective REST APIs: `run_command` and `run_commands` (Default:
false)

Warning: Allowing this could allow the user to inject potentially dangerous
root-level commands

### Debug

For debugging purposes, launches `Xorg` and `openbox` and then sleeps
without launching `luakit`.\
Manually, launch `luakit` (e.g.,
`luakit -U localhost:8123/<your-dashboard>`) from Docker container.\
E.g., `sudo docker exec -it addon_haoskiosk bash`

### Gestures

Editable list of JSON-like key-value pairs where the key represents a
(valid) *gesture string* and the value is a structured set of one or more
*action* commands. See section "GESTURE COMMANDS" below for more details.

## REST APIs

### launch_url {"url": "\<url>"}

Launch the specified 'url' in the kiosk display. Overwrites current active
tab.

Usage:
`curl -X POST http://localhost:<REST_PORT>/launch_url -H "Content-Type: application/json" -d '{"url": "<URL>"}'`

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
curl -X POST http://localhost:8080/display_on -H "Content-Type: application/json" -d '{"timeout": <timeout>}
```

### display_off

Turn off display

Usage:

`curl -X POST http://localhost:<REST_PORT>/display_off`

### xset

Run `xset <args>` to get/set display information. In particular, use `-q`
to get display information.

Usage:

`curl -X POST http://localhost:<REST_PORT>/xset -H "Content-Type: application/json" -d '{"args": "<arg-string>"}'`

### current_processes

Return number of currently running concurrent processes out of max allowed

Usage: `curl -X GET http://localhost:8080/current_processes`

### run_command {"cmd": "\<command>"}

Run `command` in the HAOSKiosk Docker container where `cmd_timeout` is an
optional timeout in seconds.

Only allowed if `Allow User Commands` option is set to true.

Usage:

`curl -X POST http://localhost:<REST_PORT>/run_command -H "Content-Type: application/json" -d '{"cmd": "<command>", "cmd_timeout": <seconds>}'`

### run_commands {"cmds": ["\<command1>", "\<command2>",...], "cmd_timeout": \<seconds>}}

Run multiple commands in the HAOSKiosk Docker container where `cmd_timeout`
is an optional timeout in seconds.

Only allowed if `Allow User Commands` option is set to true.

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

______________________________________________________________________

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
    payload: '{% if timeout is defined and timeout is number and timeout >= 0 %}{"timeout": {{ timeout | int }}}{% else %}{}{% endif %}'

  haoskiosk_display_off:
    url: "http://localhost:8080/display_off"
    method: POST
    content_type: "application/json"
    payload: "{}"

  haoskiosk_current_processes:
    url: "http://localhost:8080/current_processes"
    method: GET
    content_type: "application/json"

  haoskiosk_xset:
    url: "http://localhost:8080/xset"
    method: POST
    content_type: "application/json"
    payload: '{"args": "{{ args }}"}'

  haoskiosk_run_command:
    url: "http://localhost:8080/run_command"
    method: POST
    content_type: "application/json"
    payload: '{% if cmd_timeout is defined and cmd_timeout is number and cmd_timeout > 0 %}{"cmd": "{{ cmd }}", "cmd_timeout": {{ cmd_timeout | int }}}{% else %}{"cmd": "{{ cmd }}"}{% endif %}'

  haoskiosk_run_commands:
    url: "http://localhost:8080/run_commands"
    method: POST
    content_type: "application/json"
    payload: '{% if cmd_timeout is defined and cmd_timeout is number and cmd_timeout > 0 %}{"cmds": {{ cmds | tojson }}, "cmd_timeout": {{ cmd_timeout | int }}}{% else %}{"cmds": {{ cmds | tojson }}}{% endif %}'
```

Note if optional \`REST_BEARER_TOKEN~ is set, then add the following two
authentication lines to each of the above stanzas:

```
    headers:
      Authorization: Bearer <REST_BEARER_TOKEN>
```

The rest commands can then be referenced from automation actions as:
`rest_command.haoskiosk_<command-name>`

For example:

```
actions:
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

  - action: rest_command.haoskiosk_current_processes

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

### GESTURE COMMANDS

Each Gesture Command is a JSON-like key-value pair where the key is a valid
*Gesture String* corresponding to a specific sequence of button clicks or
finger taps and the value is an \*Action Command" containing a structured
set of one or more commands to execute when the gesture is recognized.

The formats of the Gesture Strings and Action Commands are precisely
defined, so if they fail to load check your log for error messages.

````
- Each Gesture String key is of form:
  ```
  "N-[MOUSE|TOUCH|ANY]_M-[CLICKTAP|CLICK|TAP|DRAG|SWIPE|LONG|CORNER_TOP|ANY]":
  ```
 where:
   `N` = The contact set during the gesture. Either:
    - Digit representing (maximum) number of contacts (buttons or fingers) - e.g.,  2
       - List of button names and/or numbers of specific buttons pressed (if a mouse) - e.g., [Left, Right] or [1, 3] or [Left, 3] etc.
       - 'A' (wildcard)

   `M` = Number of clicks/taps in the gesture (e.g., 1 for single-click, 2 for double-click etc) or 'A' (wildcard)
   ANY = Wildcard for any of the string entries (eg., for device type or gesture type)

Examples include:
```
   3-TOUCH_1-TAP
   2-TOUCH_2-SWIPE_RIGHT
   [Left,Right]-MOUSE_1-DRAG
   A-ANY_A-ANY          ← wildcard fallback
```

Notes:
   1. `DRAG` and SWIPE differ in velocity -- i.e., SWIPE is *faster*
   2. The gestures DRAG and SWIPE can also have the optional suffixes: _LEFT, _RIGHT, _UP, or _DOWN
   3. Conversely, DRAG and SWIPE serve as wildcard matches relative to their directional counterparts
   4. LONG can take the optional suffix _CLICK or _TAP
   5. CORNER_TOP activates when click or tap is in the extreme top-right corner of the scree
   6. DRAG, SWIPE, and LONG gestures (and their variants) are by definition only single-click
   7. Matching is case insensitive
   8. Entries are matched in order, so that you should always go from particular to more general when using wildcards
````

- Each value is an *Action Command* which can be expressed in one of the
  following 3 forms:
  1. Single command string - e.g., `"ls -a -l"`
  2. List of one or more commands each of which is can be one of the
     following forms:
     - String form - e.g., `["echo hello"]`
     - List of argv-style component string - e.g., `["ls", "-a", "-l"]`
       Example: `["echo hello", ["ls", "-a", "-l"]]`
  3. Dictionary with required key `"cmds":` and optional keys: `"msg":`,
     `"timeout":` where the value of `"cmds":` is of form 1 or 2 e.g.,
     `{"cmds": "ls -al", "msg": "list all files", "timeout": 1}` e.g.,
     `{"cmds": ["echo hello", ["ls" "-al"]], "msg": "echo hello and list all files"}`

## MISCELLANEOUS NOTES

- If screen is not working on an RPI3, try adding the following lines to
  the `[pi3]` section of your `config.txt` on the boot partition:
  ```
  dtoverlay=vc4-fkms-v3d
  max_framebuffers=2
  ```
