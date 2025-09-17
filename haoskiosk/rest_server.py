################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: services.py
# Version: 1.1.0
# Copyright Jeff Kosowsky
# Date: September 2025
#
# Launch REST API server with following commands:
#   launch_url {"url": "<url>"}
#   refresh_browser
#   display_status
#   display_on (optional) {"timeout": <non-negative integer>}
#   display_off
#   current_processes
#   xset
#   run_command {"cmd": "<command>"}
#   run_commands {"cmds": ["<command1>", "<command2>",...]}
#
# NOTE: for security only listens on 127.0.0.1 (localhost)
#       Also, can only run arbitrary commands if ALLOW_USER_COMMANDS = true
#
################################################################################

import os
import asyncio
from aiohttp import web
import re
import logging
import sys
import json
import contextlib

# Configure logging to stdout to match bashio::log format
logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
#    level=logging.DEBUG,
    format="[%(asctime)s] %(levelname)s: [%(filename)s] %(message)s",
    datefmt="%H:%M:%S"
)

# Get environment variables (set in run.sh)
ALLOW_USER_COMMANDS = os.getenv("ALLOW_USER_COMMANDS").lower() == "true"
SCREEN_TIMEOUT = os.getenv("SCREEN_TIMEOUT")
REST_PORT = os.getenv("REST_PORT")
REST_BEARER_TOKEN = os.getenv("REST_BEARER_TOKEN")
REST_IP = "127.0.0.1"

# Async subprocess configuration
MAX_PROCS = 5
_SUBPROC_SEM = asyncio.Semaphore(MAX_PROCS)
_current_procs = set()  # Track currently running subprocesses

def is_valid_url(url):
    """Validate URL format (allow without http(s)://)."""
    regex = re.compile(
        r'^(https?://)?'
        r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'
        r'localhost|'
        r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'
        r'(?::\d+)?'
        r'(?:/?|[/?]\S+)$', re.IGNORECASE)
    return re.match(regex, url) is not None

def sanitize_command(cmd):
    """Disallow dangerous characters in commands, allow semicolon."""
    if re.search(r'[&|<>]', cmd):
        raise ValueError("Command 'cmd' contains invalid characters")
    return cmd

async def run_command(command: str, log_prefix: str, cmd_timeout: int = None):
    """Run a command asynchronously with optional timeout (seconds)."""
    async with _SUBPROC_SEM:
        logging.debug(f"[{log_prefix}] Acquired semaphore for command: {command}")
        logging.info(f"[{log_prefix}] Run command: {command}")
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _current_procs.add(proc)
        try:
            if cmd_timeout is None:
                stdout, stderr = await proc.communicate()
            else:
                stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=int(cmd_timeout))
        except asyncio.TimeoutError:
            logging.error(f"[{log_prefix}] Timed out after {cmd_timeout}s; killing")
            with contextlib.suppress(ProcessLookupError):
                proc.kill()
            await proc.wait()
            return {"success": False, "stdout": "", "stderr": "", "error": f"Timed out after {cmd_timeout}s"}
        except asyncio.CancelledError:
            with contextlib.suppress(ProcessLookupError):
                proc.kill()
            await proc.wait()
            raise
        finally:
            _current_procs.discard(proc)
            logging.debug(f"[{log_prefix}] Released semaphore for command: {command}")

        stdout_text = stdout.decode(errors="replace").strip() if stdout else ""
        stderr_text = stderr.decode(errors="replace").strip() if stderr else ""
        if stdout_text:
            print("  " + stdout_text.replace("\n", "\n  "), file=sys.stdout)
        if stderr_text:
            print("  " + stderr_text.replace("\n", "\n  "), file=sys.stdout)

        if proc.returncode != 0:
            logging.error(f"[{log_prefix}] Failed (return code {proc.returncode})")
            return {"success": False, "stdout": stdout_text, "stderr": stderr_text, "error": f"Command failed with return code {proc.returncode}"}
        logging.info(f"[{log_prefix}] Succeeded")
        return {"success": True, "stdout": stdout_text, "stderr": stderr_text}

async def single_command_handler(request, command, log_prefix, data_keys=None, require_keys=False, cmd_timeout: int = None):
    """Handle a single command with validation for multiple keys."""
    try:
        data = {}
        if request.can_read_body:
            try:
                data = await request.json()
            except json.JSONDecodeError:
                logging.error(f"[{log_prefix}] Invalid JSON payload")
                return web.json_response({"success": False, "error": "Invalid JSON payload"}, status=400)

        logging.info(f"[{log_prefix}] Called{' with ' + str(data) if data else ''}")

        allowed_keys = {key for key, _ in data_keys} if data_keys else set()
        if data and set(data.keys()) - allowed_keys:
            logging.error(f"[{log_prefix}] Invalid keys in payload: {set(data.keys()) - allowed_keys}")
            return web.json_response({"success": False, "error": f"Invalid keys in payload: {set(data.keys()) - allowed_keys}"}, status=400)

        if require_keys and data_keys and not all(key in data for key, _ in data_keys):
            missing_keys = {key for key, _ in data_keys if key not in data}
            logging.error(f"[{log_prefix}] Missing required keys: {missing_keys}")
            return web.json_response({"success": False, "error": f"Missing required keys: {missing_keys}"}, status=400)

        values = {}
        for key, validate_fn in (data_keys or []):
            value = data.get(key)
            if validate_fn and (value is None or not validate_fn(value)):
                logging.error(f"[{log_prefix}] Invalid {key}: {value}")
                return web.json_response({"success": False, "error": f"Invalid {key}"}, status=400)
            values[key] = value

        result = await run_command(command.format(**values) if values else command, log_prefix, cmd_timeout)
        return web.json_response({"success": result["success"], "result": result})
    except Exception as e:
        logging.error(f"[{log_prefix}] Error: {str(e)}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def execute_commands(commands, log_prefix, cmd_timeout: int = None):
    """Execute multiple commands sequentially with optional timeout."""
    results = []
    for cmd in commands:
        result = await run_command(cmd, log_prefix, cmd_timeout)
        results.append(result)
    success = all(result["success"] for result in results)
    return {"success": success, "results": results}

async def multi_command_handler(request, commands, log_prefix, cmd_timeout: int = None):
    """Execute multiple commands and return JSON response."""
    result = await execute_commands(commands, log_prefix, cmd_timeout)
    return web.json_response({"success": result["success"], "results": result["results"]})

async def handle_launch_url(request):
    """Handle /launch_url endpoint."""
    return await single_command_handler(
        request, "luakit {url}", "launch_url", data_keys=[("url", is_valid_url)], require_keys=True, cmd_timeout=None
    )

async def handle_refresh_browser(request):
    """Handle /refresh_browser endpoint."""
    return await single_command_handler(
        request, "xdotool key --clearmodifiers ctrl+r", "refresh_browser", data_keys=None, cmd_timeout=None
    )

async def handle_is_display_on(request):
    """Handle /is_display_on endpoint to check if monitor is on or off. Returns boolean true/false"""
    try:
        result = await run_command("xset -q | grep 'Monitor is'", "is_display_on")
        if not result["success"]:
            logging.error(f"[is_display_on] Failed to get display state: {result['error']}")
            return web.json_response({"success": False, "error": result["error"]}, status=500)

        monitor_on = "Monitor is On" in result["stdout"]
        logging.info(f"[is_display_on] Display is {'on' if monitor_on else 'off'}")
        return web.json_response({"success": True, "display_on": monitor_on})
    except Exception as e:
        logging.error(f"[is_display_on] Error: {str(e)}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def handle_display_on(request):
    """Handle /display_on endpoint."""
    try:
        data = {}
        if request.can_read_body:
            try:
                data = await request.json()
            except json.JSONDecodeError:
                logging.error("[display_on] Invalid JSON payload")
                return web.json_response({"success": False, "error": "Invalid JSON payload"}, status=400)

        if not data:
            logging.info("[display_on] Called")
            return await single_command_handler(request, "xset dpms force on", "display_on", data_keys=None, cmd_timeout=None)

        logging.info(f"[display_on] Called with {data}")

        if "timeout" in data:
            try:
                timeout = int(data.get("timeout"))
                if timeout < 0:
                    raise ValueError("Timeout must be non-negative")
            except (TypeError, ValueError):
                logging.error(f"[display_on] Invalid timeout: {data.get('timeout')}")
                return web.json_response({"success": False, "error": "Timeout must be a non-negative integer"}, status=400)

            commands = [
                "xset dpms force on",
                f"xset s {timeout}",
                f"xset dpms {timeout} {timeout} {timeout}"
            ]
            result = await execute_commands(commands, "display_on", cmd_timeout=None)
            if result["success"]:
                logging.info(f"[display_on] Screen timeout {'disabled' if timeout <= 0 else f'reset to {timeout} seconds'}")
            return web.json_response({"success": result["success"], "results": result["results"]})

        if set(data.keys()) - {"timeout"}:
            logging.error(f"[display_on] Invalid keys in payload: {set(data.keys()) - {'timeout'}}")
            return web.json_response({"success": False, "error": f"Invalid keys in payload: {set(data.keys()) - {'timeout'}}"}, status=400)

        logging.info("[display_on] Called with empty payload")
        return await single_command_handler(request, "xset dpms force on", "display_on", data_keys=None, cmd_timeout=None)
    except Exception as e:
        logging.error(f"[display_on] Error: {str(e)}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def handle_display_off(request):
    """Handle /display_off endpoint."""
    return await single_command_handler(
        request, "xset dpms force off", "display_off", data_keys=None, cmd_timeout=None
    )

async def handle_current_processes(request):
    """Return count of currently running subprocesses."""
    logging.info(f"[current_processes] {len(_current_procs)} concurrent active out of {MAX_PROCS} max")
    return web.json_response({"success": True, "current_processes": len(_current_procs)})

async def handle_xset(request):
    """Handle /xset endpoint."""
    return await single_command_handler(
        request,
        "xset {args}",
        "xset",
        data_keys=[("args", lambda x: isinstance(x, str) and x.strip() != "")],
        require_keys=True,
        cmd_timeout=None
    )

async def handle_run_command(request):
    """Handle /run_command endpoint."""
    try:
        if not ALLOW_USER_COMMANDS:
            logging.error("[run_command] User commands are disabled")
            return web.json_response({"success": False, "error": "User commands are disabled"}, status=403)

        # Validate command input
        data = {}
        if request.can_read_body:
            try:
                data = await request.json()
            except json.JSONDecodeError:
                logging.error("[run_command] Invalid JSON payload")
                return web.json_response({"success": False, "error": "Invalid JSON payload"}, status=400)

        command = data.get("cmd")
        if not command:
            logging.error("[run_command] No command provided")
            return web.json_response({"success": False, "error": "No command provided"}, status=400)

        cmd_timeout = None
        if "cmd_timeout" in data:
            try:
                cmd_timeout = int(data.get("cmd_timeout"))
                if cmd_timeout <= 0:
                    raise ValueError("Timeout must be a positive integer")
            except (TypeError, ValueError):
                logging.error(f"[run_command] Invalid cmd_timeout: {data.get('cmd_timeout')}")
                return web.json_response({"success": False, "error": "Timeout must be a positive integer"}, status=400)

        if set(data.keys()) - {"cmd", "cmd_timeout"}:
            logging.error(f"[run_command] Invalid keys in payload: {set(data.keys()) - {'cmd', 'cmd_timeout'}}")
            return web.json_response({"success": False, "error": f"Invalid keys in payload: {set(data.keys()) - {'cmd', 'cmd_timeout'}}"}, status=400)

        logging.info(f"[run_command] Called with command: {command}")
        try:
            command = sanitize_command(command)
        except ValueError as e:
            logging.error(f"[run_command] Invalid command: {str(e)}")
            return web.json_response({"success": False, "error": str(e)}, status=400)

        result = await run_command(command, "run_command", cmd_timeout)
        return web.json_response({"success": result["success"], "result": result})
    except Exception as e:
        logging.error(f"[run_command] Error: {str(e)}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

async def handle_run_commands(request):
    """Handle /run_commands endpoint."""
    try:
        if not ALLOW_USER_COMMANDS:
            logging.error("[run_commands] User commands are disabled")
            return web.json_response({"success": False, "error": "User commands are disabled"}, status=403)

        # Validate commands input
        data = {}
        if request.can_read_body:
            try:
                data = await request.json()
            except json.JSONDecodeError:
                logging.error("[run_commands] Invalid JSON payload")
                return web.json_response({"success": False, "error": "Invalid JSON payload"}, status=400)

        commands = data.get("cmds", [])
        if not commands:
            logging.error("[run_commands] No commands provided")
            return web.json_response({"success": False, "error": "No commands provided"}, status=400)

        cmd_timeout = None
        if "cmd_timeout" in data:
            try:
                cmd_timeout = int(data.get("cmd_timeout"))
                if cmd_timeout <= 0:
                    raise ValueError("Timeout must be a positive integer")
            except (TypeError, ValueError):
                logging.error(f"[run_commands] Invalid cmd_timeout: {data.get('cmd_timeout')}")
                return web.json_response({"success": False, "error": "Timeout must be a positive integer"}, status=400)

        if set(data.keys()) - {"cmds", "cmd_timeout"}:
            logging.error(f"[run_commands] Invalid keys in payload: {set(data.keys()) - {'cmds', 'cmd_timeout'}}")
            return web.json_response({"success": False, "error": f"Invalid keys in payload: {set(data.keys()) - {'cmd', 'cmd_timeout'}}"}, status=400)

        logging.info(f"[run_commands] Called with commands: {commands}")
        try:
            commands = [sanitize_command(cmd) for cmd in commands]
        except ValueError as e:
            logging.error(f"[run_commands] Invalid command: {str(e)}")
            return web.json_response({"success": False, "error": str(e)}, status=400)

        result = await execute_commands(commands, "run_commands", cmd_timeout)
        return web.json_response({"success": result["success"], "results": result["results"]})
    except Exception as e:
        logging.error(f"[run_commands] Error: {str(e)}")
        return web.json_response({"success": False, "error": str(e)}, status=500)

@web.middleware
async def auth_middleware(request, handler):
    """Middleware to check Authorization Bearer token."""
    if REST_BEARER_TOKEN:
        auth_header = request.headers.get("Authorization")
        if not auth_header or auth_header != f"Bearer {REST_BEARER_TOKEN}":
            logging.error("[auth] Invalid or missing Authorization token")
            return web.json_response({"success": False, "error": "Invalid or missing Authorization token"}, status=401)
        logging.debug("[auth] Valid Authorization token")
    else:
        logging.debug("[auth] No REST_BEARER_TOKEN set or empty, bypassing authorization")
    return await handler(request)

@web.middleware
async def handle_404_middleware(request, handler):
    """Middleware to handle 404 errors."""
    try:
        response = await handler(request)
        logging.debug(f"[handle_404_middleware] Response type: {type(response)}")
        if isinstance(response, web.Response):
            return response
        return response
    except web.HTTPNotFound:
        logging.error(f"[main] Invalid endpoint requested: {request.path}")
        return web.json_response({"success": False, "error": f"Requested endpoint {request.path} is invalid"}, status=404)

async def main():
    """Run REST server."""
    app = web.Application(middlewares=[auth_middleware, handle_404_middleware])
    app.router.add_post("/launch_url", handle_launch_url)
    app.router.add_post("/refresh_browser", handle_refresh_browser)
    app.router.add_get("/is_display_on", handle_is_display_on)
    app.router.add_post("/display_on", handle_display_on)
    app.router.add_post("/display_off", handle_display_off)
    app.router.add_get("/current_processes", handle_current_processes)
    app.router.add_post("/xset", handle_xset)
    app.router.add_post("/run_command", handle_run_command)
    app.router.add_post("/run_commands", handle_run_commands)
    logging.info(f"[main] Starting REST server on http://127.0.0.1:{REST_PORT}")
    runner = web.AppRunner(app)
    await runner.setup()
    try:
        site = web.TCPSite(runner, REST_IP, REST_PORT)
        await site.start()
    except OSError as e:
        logging.error(f"[main] Failed to start server on port {REST_PORT}: {str(e)}")
        sys.exit(1)
    await asyncio.Event().wait()  # Run forever

if __name__ == "__main__":
    asyncio.run(main())
