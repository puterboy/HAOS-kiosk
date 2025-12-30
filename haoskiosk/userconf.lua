--[=[
Add-on: HAOS Kiosk Display (haoskiosk)
File: userconf.lua for HA minimal browser run on server
Version: 1.2.0
Copyright Jeff Kosowsky
Date: December 2025

Code does the following:
    - Sets browser window to fullscreen
    - Sets zooms level to value of $ZOOM_LEVEL (default 100%)
    - Loads every URL in 'passthrough' mode so that you can type text as needed without triggering browser commands
    - Auto-logs in to Home Assistant using $HA_USERNAME and $HA_PASSWORD
    - Redefines key to return to normal mode (used for commands) from 'passthrough' mode to: 'Ctl-Alt-Esc'
      (rather than just 'Esc') to prevent unintended  returns to normal mode and activation of unwanted commands
    - Adds <Control-r> binding to reload browser screen (all modes)
    - Adds <Control-Left> and <Control-Right> bindings, to move backwards and forwards respectively in the browser history
    - Prevent printing of '--PASS THROUGH--' status line when in 'passthrough' mode
    - Set up periodic browser refresh every $BROWSWER_REFRESH seconds (disabled if 0)
      NOTE: Original method injected JS to refresh page, now using native luakit view:reload command for more robustness
      	    Also, every HARD_RELOAD_FREQ refreshes, we also fully refresh the cash
      NOTE: this is important since console messages overwrite dashboards
    - Allows for configurable browser $ZOOM_LEVEL
    - Set theme based on $HA_THEME.
      If no theme is set (or if set to '{}' or 'Home Assistant') then the default theme is used with light or dark depending on the value of $DARK_MODE
      Similarly, if the theme has both light and dark modes, then the value of $DARK_MODE determines the underlying mode.
      If theme is set to '{"dark":true} or {"dark":false} then the default theme is dark or light respectively, regardless of the value of $DARK_MODE
    - Set Home Assistant sidebar visibility using $HA_SIDEBAR environment variables
    - Set 'browser_mod-browser-id' to fixed value 'haos_kiosk'
    - If using onscreen keyboard, hide keyboard after page (re)load
    - Prevent session restore by overloading 'session.restore
]=]

-- -----------------------------------------------------------------------
-- Load required Luakit modules
local window = require "window"
local webview = require "webview"
local settings = require "settings"
local modes = package.loaded["modes"]

-- -----------------------------------------------------------------------
-- Configurable variables
local new_escape_key = "<Control-Mod1-Escape>" -- Ctl-Alt-Esc
local HARD_RELOAD_FREQ = 10  -- Frequency of fully reloading cache when refreshing page

-- Load in environment variables to configure options
local defaults = {
    HA_USERNAME = "",
    HA_PASSWORD = "",
    HA_URL = "http://localhost:8123",
    DARK_MODE = true,
    HA_SIDEBAR = "",
    HA_THEME = "",

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
if raw_dark_mode == nil then
    dark_mode = defaults.DARK_MODE
else
    dark_mode = raw_dark_mode:lower()
    if dark_mode == "true" then
        dark_mode = true
    elseif dark_mode == "false" then
        dark_mode = false
    else
       dark_mode = defaults.DARK_MODE
    end
end

local raw_sidebar = os.getenv("HA_SIDEBAR") or defaults.HA_SIDEBAR -- Valid entries: full (or ""), narrow, none,
local valid_sidebars = {
    full = '',
    none = '"always_hidden"',
    narrow = '"auto"',
    [""] = ''
}
local sidebar = valid_sidebars[(raw_sidebar or ""):lower()] or ''
if sidebar == '' and raw_sidebar ~= "" and raw_sidebar ~= defaults.HA_SIDEBAR then
    msg.warn("Invalid HA_SIDEBAR value: '%s'; defaulting to unset", raw_sidebar)
    sidebar = ''
end

local theme = os.getenv("HA_THEME") or "" -- Any installed theme name (e.g., "midnight", "google", "minimal"), or empty to not override
if theme ~= "" then
   local firstchar = theme:sub(1,1)
   if firstchar ~= '"' and firstchar ~= "'" and firstchar ~= '{' then
       theme = '"' .. theme .. '"' -- Wrap in quotes
   end
    msg.info("Forcing HA_THEME to: %s", theme)
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

msg.info("USERNAME=%s; URL=%s; DARK_MODE=%s; SIDEBAR=%s; THEME=%s; LOGIN_DELAY=%.1f, ZOOM_LEVEL=%d, BROWSER_REFRESH=%d,  ONSCREEN_KEYBOARD=%s",
    username, ha_url, tostring(dark_mode), sidebar, theme, login_delay, zoom_level, browser_refresh, tostring(onscreen_keyboard))

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
-- Per-view weak table to track last URL for refresh debugging/reset detection
local refresh_state = setmetatable({}, { __mode = "k" }) -- Weak keys tied to view lifetime

-- -----------------------------------------------------------------------

-- Auto-login to homeassistant (if on HA url) and set 'sidebar settings

local ha_settings_applied = setmetatable({}, { __mode = "k" }) -- Flag to track if HA settings have already been applied in this session

webview.add_signal("init", function(view)
    ha_settings_applied[view] = false  -- Set theme and sidebar settings once  per view
    refresh_state[view] = { last_uri = nil }

    -- Listen for page load status events
    view:add_signal("load-status", function(v, status)  -- Note do NOT used "load-finished" since has redirects
        if status ~= "finished" then return end  -- Only proceed when the page is fully loaded

        local mem_file = io.open("/proc/self/statm", "r") -- Get memory consumption
        local rss_mb = "NA"
        if mem_file then
            local rss_pages = tonumber(mem_file:read("*a"):match("%S+%s+(%S+)"))
            mem_file:close()
            if rss_pages then
                rss_mb = math.floor(rss_pages * 4 / 1024)  -- Approximate MB (page size ~4kB on most systems)
            end
        end

        msg.info("URL: %s (RSS: %s MB)", v.uri, rss_mb) -- DEBUG

        -- Hide onscreen keyboard (if enabled) after page (re)load
        -- NOTE: this is needed since 'onboard' doesn't always hide keyboard unless focus explicitly lost
        if onscreen_keyboard then
            msg.info("Hiding onscreen keyboard...")
            luakit.spawn("dbus-send --dest=org.onboard.Onboard /org/onboard/Onboard/Keyboard org.onboard.Onboard.Keyboard.Hide")
        end

        -- Force passthrough mode on every page load so don't inadvertently type commands in kiosk
        webview.window(v):set_mode("passthrough")

        -- Set up auto-login for Home Assistant
        -- Check if current URL matches the Home Assistant auth page
        if v.uri:match("^" .. ha_url_base .. "/auth/authorize%?response_type=code") then
            msg.info("Authorizing: %s", v.uri) -- DEBUG
            -- JavaScript to auto-fill and submit the login form
            local js_auto_login = string.format([[
                setTimeout(function() {
                    try {
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
                    } catch(e) { console.warn('Auto-login JS error:', e); }
                }, %d);
            ]], single_quote_escape(username), single_quote_escape(password), login_delay * 1000)

            msg.info("Logging in: (username: %s): %s", username, v.uri) -- DEBUG
            v:eval_js(js_auto_login, { source = "auto_login.js", no_return = true })  -- Execute the login script
        end

        -- Set Home Assistant theme and sidebar visibility after dashboard load
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

                    // Set theme if specified
                    const theme = '%s';
                    const currentTheme = localStorage.getItem('selectedTheme') || '';
                    if (theme !== currentTheme) {
                        if (theme !== "") {
                            localStorage.setItem('selectedTheme', theme);
                        } else {
                            localStorage.removeItem('selectedTheme');
                        }
                    }

//                  localStorage.setItem('DebugLog', "Setting sidebar: " + currentSidebar + " -> " + sidebar + "; theme: " + currentTheme + " -> " + theme); // DEBUG
                } catch (err) {
                    console.error(err);
                    console.log("FAILED to set: Sidebar: " + sidebar + "  Theme: " + theme + " [" + err + "]"); // DEBUG
                    localStorage.setItem('DebugLog', "FAILED to set: Sidebar: " + sidebar + "  Theme: " + theme); // DEBUG
                }
            ]], single_quote_escape(sidebar), single_quote_escape(theme))

            v:eval_js(js_settings, { source = "ha_settings.js", no_return = true })
            msg.info("Applying HA settings on dashboard %s: theme=%s sidebar=%s", v.uri, theme, sidebar) -- DEBUG

            ha_settings_applied[v] = true   -- Mark in Lua session as settings applied
        end

        -- Suppress known harmless unhandled promise rejections in kiosk environment
        --   - Service worker / script load failures during reloads
        --   - View transition errors when monitor/document is hidden (common when screen off)
        -- Prevents page aborts/504s while keeping real errors visible
        local js_suppress_errors = [[
            window.addEventListener('unhandledrejection', function(e) {
                const reason = e.reason;
                let suppress = false;

                if (reason) {
                    const msg = typeof reason.message === 'string' ? reason.message : '';
                    const name = (reason.name || '').toLowerCase();

                    if (msg.includes('sw-modern.js') ||
                        msg.includes('load failed') ||
                        msg.includes('service worker') ||
                        name === 'invalidstateerror' &&
                            (msg.includes('document visibility state is hidden') ||
                             msg.includes('view transition')) ||
                        reason === '[object Object]' ||
                        msg === '' ||                    // Empty message common in HA reconnect bugs
                        typeof reason === 'object') {    // Catch generic objects
                        suppress = true;
                    }
                }

                if (suppress) {
                    console.warn('Suppressed known kiosk-safe unhandled rejection:', reason);
                    e.preventDefault(); // Prevent abort, potential load failure or error cascade
                }
            });
        ]]

        -- Inject suppress_errors script into the webview (once per load-finished)
        v:eval_js(js_suppress_errors, { source = "suppress_kiosk_errors.js", no_return = true })

        -- Add websocket recovery monitor
        -- Monitor HA websocket and force reload if dead (common after reconnect failures)
        local js_ws_recovery = [[

            (function() {
                if (window.ha_ws_recovery_interval) return;  // Only once
                window.ha_ws_recovery_interval = setInterval(function() {
                    if (window.APP && window.APP.connection && !window.APP.connection.connected) {
                        console.warn('HA websocket dead >10s - forcing reload for recovery');
                        location.reload();
                    }
                }, 10000);  // Check every 10 seconds
            })();
        ]]

        -- Inject websocket recovery monitor script into the webview (once per load-finished)
        v:eval_js(js_ws_recovery, { source = "ws_recovery.js", no_return = true })

    end)

    -- If browser_refresh set, then refresh browser every browser_refresh seconds after page finished/loaded/reloaded
    if browser_refresh > 0 then

        --[=[ Don't worry about refreshing non-visible pages since kiosks typically have only a single visible page - SO COMMENT OUT FOR NOW
	-- Check and set page visibility
        local page_visible = true  -- Per-view cached visibility (optimistic default)

        -- Inject JS on every load-finished
        view:add_signal("load-status", function(v, status)
            if status ~= "finished" then return end

            -- Evaluate document.visibilityState and update page_visible
            v:eval_js([[
                (function() {
                    return document.visibilityState;
                })();
            ]], {
                callback = function(state)
                    page_visible = (state == "visible")
                    msg.info("DEBUG: page visibility set to '%s': %s", state, v.uri) -- DEBUG
                end,
                error_callback = function(err)
                    msg.warn("ERROR: Couldn't determine page visibility: %s (%s)", v.uri, err)
                end,
            })
        end)
	]=]

	-- Refresh browser logic
        local refresh_timer = nil  -- Per-view refresh timer
        local hard_reload_count = 0
        local function reset_refresh_timer()
            if not view.uri or view.uri == "about:blank" then  return end -- Invalid or blank URL

            if refresh_timer then  -- Refresh existing timer
                msg.info("Restarting refresh timer (%ds): %s", browser_refresh, view.uri)
		refresh_timer:stop()   -- Stop current countdown
		refresh_timer:start()  -- Restart from full interval
            else  -- Initialize new timer
                msg.info("Initializing refresh timer (%ds): %s", browser_refresh, view.uri)
                refresh_timer = timer { interval = browser_refresh * 1000 }
                refresh_timer:add_signal("timeout", function(t)
                    if not view.is_alive then
                        msg.info("DEBUG: Skipping reload - webview not alive [shouldn't happen]")
                        return
                    end

		    if not view.uri or view.uri == "about:blank" then return end

		    --[=[ Comment out if not testing visibility
		    if not page_visible then
		        msg.info("Skipping reload - page not visible")
			return
                    end
		    ]=]

  		    hard_reload_count = hard_reload_count + 1
  		    local bypass_cache = (hard_reload_count % HARD_RELOAD_FREQ == 0)  -- Hard reload  every 10th
                    msg.info("RELOADING%s: %s", bypass_cache and " [HARD]" or "", view.uri)
       		    view:reload(bypass_cache)
                end)
                refresh_timer:start()
            end
        end

        -- Initial check (in case already loaded)
        reset_refresh_timer()

        -- Start/restart on finished loads when URI is valid
        view:add_signal("load-status", function(v, status)
            if status ~= "finished" then return end
	    reset_refresh_timer()
        end)

        -- Also on manual reloads
        view:add_signal("reload", function()
            reset_refresh_timer()
        end)

        -- *** CLEANUP: Stop refresh timer when this webview is destroyed ***
        view:add_signal("destroy", function()
            if refresh_timer then
                msg.info("DEBUG: Webview destroyed - stopping and discarding refresh timer")
                refresh_timer:stop()
                refresh_timer = nil  -- Allow garbage collection
            end
        end)

    end
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
    { "<Control-r>", "Reload page", function(w) w:reload() end },
    { "<Control-Left>", "Go back in the browser history", function(w, m) w:back(m.count) end },
    { "<Control-Right>", "Go forward in the browser history", function(w, m) w:forward(m.count) end },
    })

-- Clear the command line when entering passthrough instead of typing '-- PASS THROUGH --'
modes.get_modes()["passthrough"].enter = function(w)
    w:set_prompt()            -- Clear the command line prompt
    w:set_input()             -- Activate the input field (e.g., URL bar or form)
    w.view.can_focus = true   -- Ensure the webview can receive focus
    w.view:focus()            -- Focus the webview for keyboard input
end

-- -----------------------------------------------------------------------
