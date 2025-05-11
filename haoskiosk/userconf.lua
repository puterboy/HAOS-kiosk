--[[
Add-on: HAOS Kiosk Display (haoskiosk)
File: userconf.lua for HA minimal browser run on server
Version: 0.9.8
Copyright Jeff Kosowsky
Date: March 2025

Code does the following:
    - Sets browser window to fullscreen
   - Sets zooms level to value of $ZOOM_LEVEL (default 100%)
    - Starts first window in 'passthrough' mode so that you can type text as needed without
      triggering browser commands
    - Auto-logs in to Home Assistant using $HA_USERNAME and $HA_PASSWORD
    - Redefines key to return to normal mode (used for commands) from 'passthrough' mode to: 'Ctl-Alt-Esc'
      (rather than just 'Esc') to prevent unintended  returns to normal mode and activation of unwanted commands
    - Prevent printing of '--PASS THROUGH--' status line when in 'passthrough' mode
    - Set up periodic browser refresh every $BROWSWER_REFRESH seconds (disabled if 0)
      NOTE: this is important since console messages overwrite dashboards
]]




-- -----------------------------------------------------------------------
-- Load required Luakit modules
local window = require "window"
local webview = require "webview"
local settings = require "settings"
local modes = package.loaded["modes"]
-- local msg = require "msg" -- DEBUG: Required for debugging messages

-- -----------------------------------------------------------------------
-- Load in environment variables to configure options
local username = os.getenv("HA_USERNAME") or ""
local password = os.getenv("HA_PASSWORD") or ""
local login_delay = tonumber(os.getenv("LOGIN_DELAY")) or 1 -- Delay in seconds before auto-login, default 1
local ha_url = os.getenv("HA_URL") or "http://localhost:8123"  -- Starting URL, default to local Home Assistant
ha_url = string.gsub(ha_url, "/+$", "") -- Strip trailing '/'
local browser_refresh = tonumber(os.getenv("BROWSER_REFRESH")) or 600  -- Refresh interval in seconds, default 600
local zoom_level = tonumber(os.getenv("ZOOM_LEVEL")) or 100

-- -----------------------------------------------------------------------
-- Set window to fullscreen
window.add_signal("init", function(w)
    w.win.fullscreen = true
end)

-- Set zoom level for windows (default 100%)
settings.webview.zoom_level = zoom_level

-- enable dark mode
settings.application.prefer_dark_mode = true

-- -----------------------------------------------------------------------
local first_window = true
webview.add_signal("init", function(view)
    -- Listen for page load events
    view:add_signal("load-status", function(v, status)
        if status ~= "finished" then return end  -- Only proceed when the page is fully loaded
--	msg.info("URI: " .. v.uri) -- DEBUG

        -- We want to start in passthrough mode (i.e. not normal command mode) -- 4 potential options for doing this
	-- Option#1 Sets passthrough mode for the first window (or all initial windows if using xdotool line)
	if first_window then
            -- Option 1a: [USED]
	    webview.window(v):set_mode("passthrough") -- This method only works  if no pre-existing tabs (e.g., using 'luakit -U')
	                                              -- Otherwise, first saved (and recovered) tab gets set to passthrough mode and not the specified start url
	    -- Option 1b: [NOT USED] Requires adding 'apk add xdotool' to Dockerfile -- also seems  to set for all pre-existing windows
--            os.execute("xdotool key ctrl+z")
--	    msg.info("Setting passthrough mode...") -- DEBUG
	    first_window = false
	end

--[[
	-- Option#2 [NOT USED] Set passthrough mode for all windows with url beginning with 'ha_url'
	if v.uri:match("^" .. ha_url) then
	    webview.window(v):set_mode("passthrough")
--	    msg.info("Setting passthrough mode...") -- DEBUG
	end
]]

        -- Set up auto-login for Home Assistant
        -- Check if the current URL matches the Home Assistant auth page
        local auth_pattern = "^" .. ha_url .. "/auth/authorize%?response_type=code"
        if v.uri:match(auth_pattern) then
            -- JavaScript to auto-fill and submit the login form
            local js_auto_login = string.format([[
                setTimeout(function() {
                    var usernameField = document.querySelector('input[name="username"]');
                    var passwordField = document.querySelector('input[name="password"]');
                    var submitButton = document.querySelector('mwc-button');
                    if (usernameField && passwordField && submitButton) {
                        usernameField.value = "%s";
                        usernameField.dispatchEvent(new Event('input', { bubbles: true }));
                        passwordField.value = "%s";
                        passwordField.dispatchEvent(new Event('input', { bubbles: true }));
                        submitButton.click();
                    }
                }, %d);
            ]], username, password, login_delay * 1000)
            v:eval_js(js_auto_login, { source = "auto_login.js" })  -- Execute the login script
        end

        -- Set up periodic page refresh if browser_interval is positive
        if browser_refresh > 0 then
            local js_refresh = string.format([[
                if (window.refreshInterval) clearInterval(window.refreshInterval);
                window.refreshInterval = setInterval(function() {
                    location.reload();
                }, %d);
            ]], browser_refresh * 1000)
            v:eval_js(js_refresh, { source = "auto_refresh.js" })  -- Execute the refresh script
        end
    end)
end)


-- -----------------------------------------------------------------------
-- Redefine <Esc> to <Ctl-Alt-Esc> to exit current mode and enter normal mode
modes.remove_binds({"passthrough"}, {"<Escape>"})
modes.add_binds("passthrough", {
    {"<Control-Mod1-Escape>", "Switch to normal mode", function(w)
    	w:set_prompt()
        w:set_mode() -- Use this if not redefining 'default_mode' since defaults to "normal"
--        w:set_mode("normal") -- Use this if redefining 'default_mode' [Option#3]
     end}
})

-- Clear the command line when entering passthrough instead of typing '-- PASS THROUGH --'
modes.get_modes()["passthrough"].enter = function(w)
    w:set_prompt()            -- Clear the command line prompt
    w:set_input()             -- Activate the input field (e.g., URL bar or form)
    w.view.can_focus = true   -- Ensure the webview can receive focus
    w.view:focus()            -- Focus the webview for keyboard input
end

-- Option#3:[NOT USED]  Makes 'passthrough' *always* the default mode for 'set_mode'
--[[
local lousy = require('lousy.mode')
window.methods.set_mode = function (object, mode, ...)
    local default_mode = 'passthrough'
    return lousy.set(object, mode or default_mode)
end
]]
