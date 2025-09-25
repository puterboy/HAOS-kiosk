--[[
Add-on: HAOS Kiosk Display (haoskiosk)
File: userconf.lua for HA minimal browser run on server
Version: 1.1.1
Copyright Jeff Kosowsky
Date: September 2025

Code does the following:
    - Sets browser window to fullscreen
    - Sets zooms level to value of $ZOOM_LEVEL (default 100%)
    - Loads every URL in 'passthrough' mode so that you can type text as needed without triggering browser commands
    - Auto-logs in to Home Assistant using $HA_USERNAME and $HA_PASSWORD
    - Redefines key to return to normal mode (used for commands) from 'passthrough' mode to: 'Ctl-Alt-Esc'
      (rather than just 'Esc') to prevent unintended  returns to normal mode and activation of unwanted commands
    - Adds <Control-r> binding to reload browser screen (all modes)
    - Prevent printing of '--PASS THROUGH--' status line when in 'passthrough' mode
    - Set up periodic browser refresh every $BROWSWER_REFRESH seconds (disabled if 0)
      NOTE: this is important since console messages overwrite dashboards
    - Allows for configurable browser $ZOOM_LEVEL
    - Prefer dark color scheme for websites that support it if $DARK_MODE environment variable true (default to true)
    - Set Home Assistant sidebar visibility using $HA_SIDEBAR environment variables
    - Set 'browser_mod-browser-id' to fixed value 'haos_kiosk'
    - If using onscreen keyboard, hide keyboard after page (re)load
    - Prevent session restore by overloading 'session.restore
]]

-- -----------------------------------------------------------------------
-- Load required Luakit modules
local window = require "window"
local webview = require "webview"
local settings = require "settings"
local modes = package.loaded["modes"]

-- -----------------------------------------------------------------------
-- Configurable variables
local new_escape_key = "<Control-Mod1-Escape>" -- Ctl-Alt-Esc

-- Load in environment variables to configure options
local defaults = {
    HA_USERNAME = "",
    HA_PASSWORD = "",
    HA_URL = "http://localhost:8123",
    DARK_MODE = true,
    HA_SIDEBAR = "",

    LOGIN_DELAY = 1,
    ZOOM_LEVEL = 100,
    BROWSER_REFRESH = 600,
                        }
local username = os.getenv("HA_USERNAME") or defaults.HA_USERNAME
local password = os.getenv("HA_PASSWORD") or defaults.HA_PASSWORD

local ha_url = os.getenv("HA_URL") or defaults.HA_URL  -- Starting URL
if not ha_url:match("^https?://[%w%.%-%%:]+[/%?%#]?[/%w%.%-%?%#%=%%]*$") then
    msg.warn("Invalid HA_URL value: '%s'; defaulting to %s", os.getenv("HA_URL") or "", defaults.HA_URL)
    ha_url = defaults.HA_URL
end
ha_url = string.gsub(ha_url, "/+$", "") -- Strip trailing '/'
local ha_url_base = ha_url:match("^(https?://[%w%.%-%%:]+)") or ha_url
ha_url_base = string.gsub(ha_url_base, "/+$", "") -- Strip trailing '/'

local raw_dark_mode = os.getenv("DARK_MODE")
local dark_mode = ({
    ["true"] = true,
    ["false"] = false
})[raw_dark_mode]
if dark_mode == nil then
    dark_mode = defaults.DARK_MODE
end

local raw_sidebar = os.getenv("HA_SIDEBAR") or defaults.HA_SIDEBAR -- Valid entries: full (or ""), narrow, none,
local valid_sidebars = {
    full = '',
    none = '"always_hidden"',
    narrow =
    '"auto"',
    [""] = ''
}
local sidebar = valid_sidebars[raw_sidebar]
if sidebar == nil then
    msg.warn("Invalid HA_SIDEBAR value: '%s'; defaulting to unset", raw_sidebar)
    sidebar = ''
end

local login_delay = tonumber(os.getenv("LOGIN_DELAY")) or defaults.LOGIN_DELAY -- Delay in seconds before auto-login
if login_delay <= 0 then
    msg.warn("Invalid LOGIN_DELAY value: '%s'; defaulting to %d", os.getenv("LOGIN_DELAY") or "", defaults.LOGIN_DELAY)
    login_delay = defaults.LOGIN_DELAY
end

local zoom_level = tonumber(os.getenv("ZOOM_LEVEL")) or defaults.ZOOM_LEVEL
if zoom_level <= 0 then
    msg.warn("Invalid ZOOM_LEVEL value: '%s'; defaulting to %d", os.getenv("ZOOM_LEVEL") or "", defaults.ZOOM_LEVEL)
    zoom_level = defaults.ZOOM_LEVEL
end

local browser_refresh = tonumber(os.getenv("BROWSER_REFRESH")) or defaults.BROWSER_REFRESH  -- Refresh interval in seconds
if browser_refresh < 0 then
    msg.warn("Invalid BROWSER_REFRESH value: '%s'; defaulting to %d", os.getenv("BROWSER_REFRESH") or "", defaults.BROWSER_REFRESH)
    browser_refresh = defaults.BROWSER_REFRESH
end

local onscreen_keyboard = os.getenv("ONSCREEN_KEYBOARD") == "true"

msg.info("USERNAME=%s; URL=%s; DARK_MODE=%s; SIDEBAR=%s; LOGIN_DELAY=%.1f, ZOOM_LEVEL=%d, BROWSER_REFRESH=%d,  ONSCREEN_KEYBOARD=%s",
    username, ha_url, tostring(dark_mode), sidebar, login_delay, zoom_level, browser_refresh, tostring(onscreen_keyboard))

-- -----------------------------------------------------------------------
-- Forward console messages to stdout
settings.set_setting("webview.enable_write_console_messages_to_stdout", true)

-- Prefer Dark mode if set to true
settings.application.prefer_dark_mode = dark_mode

-- Set window to fullscreen
window.add_signal("init", function(w)
    w.win.fullscreen = true
end)

-- Set zoom level for windows (default 100%)
settings.webview.zoom_level = zoom_level

-- Prevent session restore by overloading 'session.restore'
local session = require "session"
session.restore = function()
    return nil
end

-- Force new URLs from new 'luakit' instances to launch in current/last active tab of first window
-- Note requires patch to /usr/share/luakit/lib/unique_instance.lua
local unique_instance = require "unique_instance"
unique_instance.open_link_in_current_tab  = true


-- -----------------------------------------------------------------------
-- Helper functions
local function single_quote_escape(str) -- Single quote strings before injection into JS
    if not str or str == "" then return str end
    str = str:gsub("\\", "\\\\")
    str = str:gsub("'", "\\'")
    str = str:gsub("\n", "\\n")
    str = str:gsub("\r", "\\r")
    return str
end

-- -----------------------------------------------------------------------
-- Auto-login to homeassistant (if on HA url) and set 'sidebar settings

local ha_settings_applied = setmetatable({}, { __mode = "k" }) -- Flag to track if HA settings have already been applied in this session

webview.add_signal("init", function(view)
    ha_settings_applied[view] = false  -- Set sidebar settings once  per view

    -- Listen for page load events
    view:add_signal("load-status", function(v, status)
        if status ~= "finished" then return end  -- Only proceed when the page is fully loaded
        msg.info("URI: %s", v.uri) -- DEBUG

        -- Hide onscreen keyboard (if enabled) after page (re)load
        -- NOTE: this is needed since 'onboard' doesn't always hide keyboard unless focus explicitly lost
	if onscreen_keyboard then
	    msg.info("Hiding onscreen keyboard...")
	    luakit.spawn("dbus-send --type=method_call --print-reply --dest=org.onboard.Onboard /org/onboard/Onboard/Keyboard org.onboard.Onboard.Keyboard.Hide")
	end

	-- Force passthrough mode on every page load so don't inadvertently type commands in kiosk
	webview.window(v):set_mode("passthrough")

        -- Set up auto-login for Home Assistapnt
        -- Check if current URL matches the Home Assistant auth page
        if v.uri:match("^" .. ha_url_base .. "/auth/authorize%?response_type=code") then
	    msg.info("Authorizing: %s", v.uri) -- DEBUG
            -- JavaScript to auto-fill and submit the login form
            local js_auto_login = string.format([[
                setTimeout(function() {
		    const usernameField = document.querySelector('input[autocomplete="username"]');
		    const passwordField = document.querySelector('input[autocomplete="current-password"]');
		    const haCheckbox = document.querySelector('ha-checkbox');
		    const submitButton = document.querySelector('ha-button, mwc-button');

                    if (usernameField && passwordField && submitButton) {
                        usernameField.value = '%s';
                        usernameField.dispatchEvent(new Event('input', { bubbles: true }));
                        passwordField.value = '%s';
                        passwordField.dispatchEvent(new Event('input', { bubbles: true }));
                    } else {
                        console.log('Auto-login failed: missing elements', {
                            username: !!usernameField,
                            password: !!passwordField,
                            submit: !!submitButton
			});
		    }

		    if (haCheckbox) {
		        haCheckbox.setAttribute('checked', '');
			haCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
		    }

                    submitButton.click();

                }, %d);
            ]], single_quote_escape(username), single_quote_escape(password), login_delay * 1000)

	    msg.info("Logging in: (username: %s): %s", username, v.uri) -- DEBUG
            v:eval_js(js_auto_login, { source = "auto_login.js", no_return = true })  -- Execute the login script
        end

        -- Set Home Assistant sidebar visibility after dashboard load
        -- Check if current URL starts with ha_url but not an auth page
        if not ha_settings_applied[v]
           and (v.uri .. "/"):match("^" .. ha_url_base .. "/") -- Note ha_url was stripped of trailing slashes
           and not v.uri:match("^" .. ha_url_base .. "/auth/") then

            local js_settings = string.format([[
                try {
	            // Set browser_mod browser ID to "haos_kiosk"
                    localStorage.setItem('browser_mod-browser-id', 'haos_kiosk');

                    // Set sidebar visibility
		    const sidebar = '%s';
                    const currentSidebar = localStorage.getItem('dockedSidebar') || '';

                    if (sidebar !== currentSidebar) {
                        if (sidebar !== "") {
                            localStorage.setItem('dockedSidebar', sidebar);
                        } else {
                            localStorage.removeItem('dockedSidebar');
                        }
                    }

//                  localStorage.setItem('DebugLog', "Setting: : " + currentSidebar + " -> " + sidebar); // DEBUG

                } catch (err) {
		    console.error(err);
		    console.log("FAILED to set: Sidebar: " + sidebar + "[" + err + "]"); // DEBUG
                    localStorage.setItem('DebugLog', "FAILED to set: Sidebar: " + sidebar); // DEBUG
                }
            ]], single_quote_escape(sidebar))

            v:eval_js(js_settings, { source = "ha_settings.js", no_return = true })
            msg.info("Applying HA settings on dashboard %s: sidebar=%s", v.uri, theme, sidebar) -- DEBUG

            ha_settings_applied[v] = true   -- Mark in Lua session as settings applied
        end


        -- Set up periodic page refresh (once per page load) if browser_refresh interval is positive
        if browser_refresh > 0 then
            -- JavaScript to block HA reloads and set up periodic reloads
            local js_refresh = string.format([[
                if (window.ha_refresh_id) clearInterval(window.ha_refresh_id);
                window.ha_refresh_id = setInterval(function() {
                    location.reload();
                }, %d);
                window.addEventListener('beforeunload', function() {
                    clearInterval(window.ha_refresh_id);
                });
            ]], browser_refresh * 1000)

            -- Inject refresh script into the webview
            v:eval_js(js_refresh, { source = "auto_refresh.js", no_return = true })  -- Execute the refresh script
            msg.info("Injecting refresh interval: %s", v.uri)  -- DEBUG
        end

    end)
end)

-- -----------------------------------------------------------------------
-- Redefine <Esc> to 'new_escape_key' (e.g., <Ctl-Alt-Esc>) to exit current mode and enter normal mode
modes.remove_binds({"passthrough"}, {"<Escape>"})
modes.add_binds("passthrough", {
    {new_escape_key, "Switch to normal mode", function(w)
        w:set_prompt()
        w:set_mode() -- Use this if not redefining 'default_mode' since defaults to "normal"
--        w:set_mode("normal") -- Use this if redefining 'default_mode' [Option#3]
     end}
}
)
-- Add <Control-r> binding in all modes to reload page
modes.add_binds("all", {
    { "<Control-r>", "reload page", function (w) w:reload() end },
    })

-- Clear the command line when entering passthrough instead of typing '-- PASS THROUGH --'
modes.get_modes()["passthrough"].enter = function(w)
    w:set_prompt()            -- Clear the command line prompt
    w:set_input()             -- Activate the input field (e.g., URL bar or form)
    w.view.can_focus = true   -- Ensure the webview can receive focus
    w.view:focus()            -- Focus the webview for keyboard input
end
