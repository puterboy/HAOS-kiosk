"""-------------------------------------------------------------------------------
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: services.py
# Version: 1.2.0
# Copyright Jeff Kosowsky
# Date: December 2025
#
# Launch REST API server with following commands:
#   POST /launch_url        {"url": "<url>"}
#   POST /refresh_browser
#   GET  /is_display_on
#   POST /display_on        (optional) {"timeout": <non-negative integer>}
#   POST /display_off
#   GET  /current_processes
#   POST /xset              {"args": "..."}
#   POST /run_command       {"cmd": "<command>", "cmd_timeout": <seconds>}
#   POST /run_commands      {"cmds": ["cmd1", "cmd2", ...], "cmd_timeout": <seconds>}
#
# NOTE: for security defaults to listening only on 127.0.0.1 (localhost)
# Also, can only run arbitrary commands if ALLOW_USER_COMMANDS = true
#----------------------------------------------------------------------------"""
# pylint: disable=line-too-long
# pylint: disable=invalid-name
# pylint: disable=too-many-instance-attributes
# pylint: disable=broad-except
# pylint: disable=too-many-arguments
# pylint: disable=too-many-positional-arguments
# pylint: disable=too-many-branches
# pylint: disable=too-many-statements
# pylint: disable=too-many-locals
# pylint: disable=too-many-lines

#-------------------------------------------------------------------------------
from __future__ import annotations
import asyncio
import ipaddress
import json
import logging
import os
import re
import sys
from contextlib import suppress
from typing import Any, Awaitable, Callable, Literal
from aiohttp import web  #type: ignore[import-not-found] #pylint: disable=import-error

#-------------------------------------------------------------------------------
__version__ = "1.2.0"
__author__ = "Jeff Kosowsky"
__copyright__ = "Copyright 2025 Jeff Kosowsky"

# ----------------------------------------------------------------------------- #
# Global variables
# ----------------------------------------------------------------------------- #

### Import environment variables (set in run.sh)
ALLOW_USER_COMMANDS: bool = os.getenv("ALLOW_USER_COMMANDS", "false").lower() == "true"
REST_PORT: int = int(os.getenv("REST_PORT", "8080"))
REST_IP: str = os.getenv("REST_IP", "127.0.0.1")
REST_BEARER_TOKEN: str | None = os.getenv("REST_BEARER_TOKEN") or None  # None = no authorization required

### Other Globals
MAX_CONCURRENT_COMMANDS: int = 5
SHORT_TIMEOUT: int = 5  # Timeout used for simple commands

# --------------------------------------------------------------------------- #
# Setup
# --------------------------------------------------------------------------- #

### Validate configuration at startup
try:
    ipaddress.ip_address(REST_IP)
    if not 1024 <= REST_PORT <= 65535:
        raise ValueError("REST IP Port must be integer 1024-65535")
except Exception as e:
    logging.error("Invalid configuration: %s", e)
    sys.exit(1)

### Logging - logging to stdout matches Home Assistant bashio::log  format

logging.basicConfig(
    stream  = sys.stdout,
    level   =  logging.INFO,
#   level   = loggingDEBUG
    format  = "[%(asctime)s] %(levelname)s: [%(filename)s:%(lineno)d] %(message)s",
    datefmt = "%H:%M:%S",
)

###  Concurrency control: limit number of simultaneous shell commands

_command_semaphore = asyncio.Semaphore(MAX_CONCURRENT_COMMANDS)
_active_processes: set[asyncio.subprocess.Process] = set()   # Track currently running subprocesses

# --------------------------------------------------------------------------- #
# Helper Functions
# --------------------------------------------------------------------------- #

def is_valid_url(url: str) -> bool:  #  Validate URLs (allows http://, https://, or bare domain/IP)
    """Validate URL format (allow without http(s)://)."""
    regex = re.compile(
        r'^(https?://)?'                     # Optional scheme
        r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'  # Domain
        r'localhost|'                        # localhost
        r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'  # or IP
        r'(?::\d+)?'                         # Optional port
        r'(?:/?|[/?]\S+)$', re.IGNORECASE)   # Path
    return bool(regex.match(url))

def sanitize_command(cmd: str) -> str:  # Command sanitization
    """Disallow dangerous shell metacharacters (& | < >), allow semicolon."""
    if re.search(r"[&|<>]", cmd):
        raise ValueError("Command contains forbidden characters: & | < >")
    return cmd.strip()

# --------------------------------------------------------------------------- #
# Core functions
# --------------------------------------------------------------------------- #

Payload = dict[str, Any]   # simple, correct, mypy-friendly
CommandKey = Literal["url", "timeout", "args", "cmd", "cmds", "cmd_timeout"]

async def run_shell_command(command: str, *, timeout: int | None = None,log_prefix: str = "shell") -> dict[str, Any]:
    """
    Execute a shell command safely with concurrency limiting and optional timeout.
    Returns dict containing: success, stdout, stderr, returncode, and possibly error.
    """
    async with _command_semaphore:
        logging.info("[%s] Executing: %s", log_prefix, command)

        proc: asyncio.subprocess.Process = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _active_processes.add(proc)

        try:
            if timeout is not None:
                stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
            else:
                stdout, stderr = await proc.communicate()
        except asyncio.TimeoutError:
            logging.error("[%s] Timeout after %ds → killing", log_prefix, timeout or 0)
            with suppress(ProcessLookupError):
                proc.kill()
            await proc.wait()
            return {"success": False, "error": f"Command timed out after {timeout}s"}
        finally:
            _active_processes.discard(proc)

        stdout_str: str = stdout.decode(errors="replace").strip() if stdout else ""
        stderr_str: str = stderr.decode(errors="replace").strip() if stderr else ""

        # Pretty-print output (HA style)
        for line in stdout_str.splitlines():
            print(" " + line)
        for line in stderr_str.splitlines():
            print(" " + line)

        success: bool = proc.returncode == 0
        if not success:
            logging.error("[%s] Failed (exit code %d)", log_prefix, proc.returncode)

        return {
            "success": success,
            "stdout": stdout_str,
            "stderr": stderr_str,
            "returncode": proc.returncode,
        }

# --------------------------------------------------------------------------- #
# Decorator
# --------------------------------------------------------------------------- #

def api_endpoint(  # Decorator
        *,
        required: list[str] | None = None,
        optional: list[str] | None = None,
        validators: dict[str, Callable[[Any], bool]] | None = None,
        needs_user_commands: bool = False,
) -> Callable[[Callable[[Payload], Awaitable[dict[str, Any]]]], Callable[[web.Request], Awaitable[web.Response]]]:
    """Universal decorator: JSON validation, auth, logging, error handling."""
    required = required or []
    optional = optional or []
    validators = validators or {}
    allowed = set(required) | set(optional)

    def decorator(func: Callable[[Payload], Awaitable[dict[str, Any]]]) -> Callable[[web.Request], Awaitable[web.Response]]:
        name = func.__name__.replace("handle_", "").replace("_", " ")

        async def wrapper(request: web.Request) -> web.Response:  # pylint: disable=too-many-return-statements
            if needs_user_commands and not ALLOW_USER_COMMANDS:
                return web.json_response({"success": False, "error": "User commands are disabled"}, status=403)

            # Only try to read JSON body on methods that usually have one
            payload: Payload = {}
            if request.method in ("POST", "PUT") and request.can_read_body:
                try:
                    data = await request.json()
                    if not isinstance(data, dict):
                        return web.json_response({"success": False, "error": "JSON object required"}, status=400)
                    payload = data

                except json.JSONDecodeError:
                    return web.json_response({"success": False, "error": "Invalid JSON"}, status=400)

            # Validation
            if bad := set(payload) - allowed:
                return web.json_response({"success": False, "error": f"Invalid keys: {bad}"}, status=400)

            if missing := set(required) - set(payload):
                return web.json_response({"success": False, "error": f"Missing keys: {missing}"}, status=400)

            for k, v in payload.items():
                if k in validators and not validators[k](v):
                    return web.json_response({"success": False, "error": f"Invalid {k}: {v}"}, status=400)

            logging.info("[%s] %s", name, payload or "(no payload)")

            try:
                result = await func(payload)   # Always pass payload (may be empty)
                return web.json_response(result)
            except Exception as e:
                logging.exception("[%s] Failed", name)
                return web.json_response({"success": False, "error": str(e)}, status=500)

        return wrapper
    return decorator

# --------------------------------------------------------------------------- #
# Endpoints:
# --------------------------------------------------------------------------- #

@api_endpoint(required=["url"], validators={"url": is_valid_url})
async def handle_launch_url(data: Payload) -> dict[str, Any]:
    """Launch browser with given URL."""
    url = str(data["url"])
    if not url.startswith(("http://", "https://")):
        url = "http://" + url
    result = await run_shell_command(f"luakit '{url}' &", log_prefix="launch_url")
    return {"success": result["success"], "result": result}

@api_endpoint()
async def handle_refresh_browser(data: Payload) -> dict[str, Any]:  # pylint: disable=unused-argument
    """Send Ctrl+R to refresh browser."""
    result = await run_shell_command( "xdotool key --clearmodifiers ctrl+r", timeout=SHORT_TIMEOUT, log_prefix="refresh_browser")
    return {"success": result["success"]}

@api_endpoint()  # GET endpoint – we register manually below
async def handle_is_display_on(data: Payload) -> dict[str, Any]:  # pylint: disable=unused-argument
    """Return boolean whether monitor is currently on."""
    result = await run_shell_command("xset -q | grep -i 'Monitor is'", timeout=SHORT_TIMEOUT, log_prefix="is_display_on")
    if not result["success"]:
        return {"success": False, "error": "Failed to query display state"}

    is_on = "Monitor is On" in result["stdout"]
    logging.info("[is_display_on] Monitor is %s", "ON" if is_on else "OFF")
    return {"success": True, "display_on": is_on}

@api_endpoint(optional=["timeout"])
async def handle_display_on(data: Payload) -> dict[str, Any]:
    """Turn display on, optionally set blanking timeout."""
    timeout_val = data.get("timeout")

    if timeout_val is None:
        result = await run_shell_command("xset dpms force on", timeout=SHORT_TIMEOUT, log_prefix="display_on")
        return {"success": result["success"]}

    try:
        timeout = int(timeout_val)
        if timeout < 0:
            raise ValueError
    except ValueError:
        return {"success": False, "error": "timeout must be non-negative integer"}

    if timeout == 0:
        cmds = [
            "xset dpms force on",
            "xset s off",
            "xset -dpms",
        ]
        log_msg = "disabled"
    else:
        cmds = [
            "xset dpms force on",
            f"xset s {timeout}",
            f"xset dpms {timeout} {timeout} {timeout}",
        ]
        log_msg = f"{timeout} seconds"

    results = [await run_shell_command(cmd, timeout=SHORT_TIMEOUT, log_prefix="display_on") for cmd in cmds]
    logging.info("[display_on] Screen timeout %s", log_msg)
    return {"success": all(r["success"] for r in results), "results": results}

@api_endpoint()
async def handle_display_off(data: Payload) -> dict[str, Any]:  # pylint: disable=unused-argument
    """Force display off immediately."""
    result = await run_shell_command("xset dpms force off", timeout=SHORT_TIMEOUT, log_prefix="display_off")
    return {"success": result["success"]}

@api_endpoint()  # GET endpoint
async def handle_current_processes(data: Payload) -> dict[str, Any]:  # pylint: disable=unused-argument
    """Report number of currently running subprocesses."""
    count = len(_active_processes)
    logging.info(
        "[current_processes] %d active (max %d)", count, MAX_CONCURRENT_COMMANDS
    )
    return {
        "success": True,
        "current_processes": count,
        "max_allowed": MAX_CONCURRENT_COMMANDS,
    }

@api_endpoint(required=["args"], validators={"args": lambda x: isinstance(x, str) and bool(x.strip())})
async def handle_xset(data: Payload) -> dict[str, Any]:
    """Run arbitrary xset command (sanitized)."""
    args = sanitize_command(str(data["args"]))
    result = await run_shell_command(f"xset {args}", timeout=SHORT_TIMEOUT, log_prefix="xset")
    return {"success": result["success"], "result": result}

@api_endpoint(required=["cmd"], optional=["cmd_timeout"],
              validators={"cmd_timeout": lambda x: x is None or (isinstance(x, int) and x > 0)},
              needs_user_commands=True)
async def handle_run_command(data: Payload) -> dict[str, Any]:
    """Execute a single user-supplied command (if allowed)."""
    cmd = sanitize_command(str(data["cmd"]))
    timeout = data.get("cmd_timeout")
    result = await run_shell_command(cmd, timeout=timeout, log_prefix="run_command")
    return {"success": result["success"], "result": result}

@api_endpoint(required=["cmds"], optional=["cmd_timeout"], needs_user_commands=True)
async def handle_run_commands(data: Payload) -> dict[str, Any]:
    """Execute multiple user-supplied commands sequentially."""
    raw_cmds = data["cmds"]
    if not isinstance(raw_cmds, list):
        return {"success": False, "error": "'cmds' must be a list"}

    cmds = [sanitize_command(str(c)) for c in raw_cmds]
    timeout = data.get("cmd_timeout")

    results = [
        await run_shell_command(cmd, timeout=timeout, log_prefix="run_commands")
        for cmd in cmds
    ]
    return {"success": all(r["success"] for r in results), "results": results}

# --------------------------------------------------------------------------- #
# Bearer token middleware
# --------------------------------------------------------------------------- #

@web.middleware
async def bearer_auth_middleware(
        request: web.Request, handler: Callable[[web.Request], Awaitable[web.Response]]
) -> web.Response:
    """
    aiohttp middleware that enforces Bearer token authentication.
    If REST_BEARER_TOKEN environment variable is set (non-empty), every incoming request must contain the header:
        Authorization: Bearer <token>
    If the token is missing or invalid → returns HTTP 401 immediately.
    Otherwise passes the request to the next handler.
    """
    if REST_BEARER_TOKEN:
        auth_header = request.headers.get("Authorization", "")
        if auth_header != f"Bearer {REST_BEARER_TOKEN}":
            logging.warning("[auth] Invalid token from %s", request.remote or "unknown")
            return web.json_response(
                {"success": False, "error": "Invalid or missing Authorization token"},
                status=401,
            )
    return await handler(request)

# --------------------------------------------------------------------------- #
# Application factory
# --------------------------------------------------------------------------- #

async def create_app() -> web.Application:
    """Create and configure the aiohttp Application instance."""
    app = web.Application(middlewares=[bearer_auth_middleware])

    # Register routes
    app.router.add_post("/launch_url", handle_launch_url)
    app.router.add_post("/refresh_browser", handle_refresh_browser)
    app.router.add_get("/is_display_on", handle_is_display_on)
    app.router.add_post("/display_on", handle_display_on)
    app.router.add_post("/display_off", handle_display_off)
    app.router.add_get("/current_processes", handle_current_processes)
    app.router.add_post("/xset", handle_xset)
    app.router.add_post("/run_command", handle_run_command)
    app.router.add_post("/run_commands", handle_run_commands)
    app.router.add_get("/health", lambda _: web.json_response({"status": "ok"}))

    # Catch-all 404
    async def not_found(request: web.Request) -> web.Response:
        """Handle 404 for undefined routes."""
        logging.warning("[404] %s %s", request.method, request.path)
        return web.json_response(
            {"success": False, "error": f"Endpoint not found: {request.path}"}, status=404
        )

    app.router.add_route("*", "/{tail:.*}", not_found)

    return app


# --------------------------------------------------------------------------- #
# Server startup
# --------------------------------------------------------------------------- #
async def main() -> None:
    """Start the REST server."""
    app = await create_app()
    logging.info("Starting HAOS Kiosk REST server on http://%s:%s", REST_IP, REST_PORT)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, REST_IP, REST_PORT)

    try:
        await site.start()
        logging.info("Server started – ready to accept requests")
    except OSError as exc:
        logging.error("Failed to bind to %s:%s → %s", REST_IP, REST_PORT, exc)
        sys.exit(1)

    await asyncio.Event().wait()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
