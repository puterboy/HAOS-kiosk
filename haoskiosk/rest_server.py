"""-------------------------------------------------------------------------------
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: services.py
# Version: 1.3.0
# Copyright Jeff Kosowsky
# Date: January 2026

 Launch REST API server with following commands:
   POST /launch_url        {"url": "<url>"}
   POST /refresh_browser
   GET  /is_display_on
   POST /display_on        (optional) {"timeout": <non-negative integer>}
   POST /display_off
   GET  /current_processes
   POST /xset              {"args": "..."}
   POST /run_command       {"cmd": "<command>", "cmd_timeout": <seconds>}
   POST /run_commands      {"cmds": ["cmd1", "cmd2", ...], "cmd_timeout": <seconds>}

 For security:
   - Defaults to listening only on 127.0.0.1 (localhost)
   - Requires REST_BEARER_TOKEN if caller is not localhost
   - Commands must:
       - Satisfy whitelist regex
       - Not be on blacklist
       - Not contain destructive tokens
     This can be over-ridden by setting ALLOW_ALL_USER_COMMANDS = True, BUT not allowed now

#-------------------------------------------------------------------------------
###  MYTODOS:
 - Add broader whitelist
 - Add ability to import whitelist (maybe add special key to allow all?)
 - Test
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
import inspect
import ipaddress
import logging
import os
import re
import shlex
import shutil
import sys
from contextlib import suppress
from functools import wraps
from typing import Any, Awaitable, cast, Callable, Final, Literal, TypedDict, TypeVar
from aiohttp import web  #type: ignore[import-not-found] #pylint: disable=import-error

#-------------------------------------------------------------------------------
__version__ = "1.3.0"
__author__ = "Jeff Kosowsky"
__copyright__ = "Copyright 2025 Jeff Kosowsky"

# ----------------------------------------------------------------------------- #
# Global variables
# ----------------------------------------------------------------------------- #

### Import environment variables (set in run.sh)
REST_PORT: int = int(os.getenv("REST_PORT", "8080"))
REST_IP: str = os.getenv("REST_IP", "127.0.0.1")
REST_BEARER_TOKEN: str | None = os.getenv("REST_BEARER_TOKEN") or None  # None = no authorization required

# Note setting True is a real security risk since it allows all commands and tokens
# If just want all programs, set COMMAND_WHITELIST_REGEX to "*"
ALLOW_ALL_USER_COMMANDS: bool = os.getenv("ALLOW_ALL_USER_COMMANDS", "false").lower() == "true"

### Other Globals
MAX_CONCURRENT_COMMANDS: int = 5
SHORT_TIMEOUT: int = 5  # Timeout used for simple commands


# --------------------------------------------------------------------------- #
# Security Model
# --------------------------------------------------------------------------- #

## Restrict paths to specific, non-system bins
ALLOWED_PATHS = {"/bin", "/usr/bin", "/usr/local/bin"} # Executables must be in these directories

## Commands that are white-listed -- all others are blocked (Note: set to ".*" to allow all or "" to block all)
DEFAULT_COMMAND_WHITELIST_REGEX = r"cat|date|dbus-send|echo|false|grep|head|ls|luakit|notify-send|ping|ping6|ps|pstree|sleep|tail|test|top|tree|xdotool|xset"
COMMAND_WHITELIST_REGEX = os.getenv("COMMAND_WHITELIST", DEFAULT_COMMAND_WHITELIST_REGEX).strip()

COMPILED_WHITELIST_REGEX: re.Pattern[str] | None = None
if COMMAND_WHITELIST_REGEX:
    COMMAND_WHITELIST_REGEX = '^(?:' + COMMAND_WHITELIST_REGEX + ')$'  # Make sure starts with '^' and ends with '$'
    try:
        COMPILED_WHITELIST_REGEX = re.compile(COMMAND_WHITELIST_REGEX)
    except re.error as e:
        logging.error("Invalid COMMAND_WHITELIST_REGEX '%s', blocking all commands: %s", COMMAND_WHITELIST_REGEX, e)
        COMPILED_WHITELIST_REGEX = re.compile(r"(?!)")  # Match nothing

## Commands blocked (unless 'ALLOW_ALL_USER_COMMANDS' is True)
# Note we only need to consider commands in ALLOWED_PATHS
COMPILED_BLACKLIST_REGEX: Final[re.Pattern[str]] = re.compile(
    r"^(?:"  # Always pin beginning
    r"python[\d.]+|"
    r"ash|bash|sh|su|"
    r"env|exec|"
    r"kill|killall|pkill|"
    r"cp|chmod|chown|dd|ln|mv|rm|tar|"
    r"mount|umount|"
    r"curl|nc|wget|"
    r"find|xargs"
    r")$" # Always pin end
)

# Allowed Redirections
SAFE_REDIRECT_REGEX: Final[re.Pattern[str]] = re.compile(
    r">\s*/dev/null|"
    r">>\s*/dev/null|"
    r"2\s*>\s*/dev/null|"
    r"2\s*>>\s*/dev/null|"
    r"&\s*>\s*/dev/null|"
    r"&\s*>>\s*/dev/null|"
    r"2\s*>&\s*1|"
    r"1\s*>&\s*2"
)

# Command separators to parse and split
SEPARATORS: frozenset[str] = frozenset({ "&&", "||", ";", "|", "&", "$(", "${", "`", "(", "{", "[[", "((" })
SEP_REGEX: Final[re.Pattern[str]] = re.compile('(?:' + '|'.join(re.escape(op) for op in sorted(SEPARATORS, key=len, reverse=True)) + ')')

DANGEROUS_SHELL_TOKENS: set[str] = { # Disallowed shell tokens if just expecting string arguments (used only in xset for now)
    ";", "&&", "||", "|", "&", "`", "$(", "${", ">", "<", "2>", "&>", "*?", "[",
}

VALID_URL_REGEX: Final[re.Pattern[str]] = re.compile(
    r'^(https?://)?'                  # Optional scheme
    r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'  # Domain
    r'localhost|'                     # localhost
    r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'  # IPv4
    r'(?::\d{1,5})?'                  # Optional port (1-65535 max, but \d+ is fine)
    r'(?:/?|[/?][^\s]*)?$',           # Path/query/fragment (allows #fragment, rejects spaces)
    re.IGNORECASE
)

def is_valid_url(url: str) -> bool:
    """Validate URL format (allows http://, https://, bare domain/IP, path, query, fragment)."""
    return bool(VALID_URL_REGEX.fullmatch(url.strip()))

# --------------------------------------------------------------------------- #
# Setup
# --------------------------------------------------------------------------- #

### Logging - logging to stdout matches Home Assistant bashio::log  format
logging.basicConfig(
    stream  = sys.stdout,
    level   =  logging.INFO,
#    level   = logging.DEBUG,
    format  = "[%(asctime)s] %(levelname)s: [%(filename)s:%(funcName)s] %(message)s",
    datefmt = "%H:%M:%S",
)
logger = logging.getLogger(__name__)

### Validate configuration at startup
try:
    ipaddress.ip_address(REST_IP)
    if not 1024 <= REST_PORT <= 65535:
        raise ValueError("REST IP Port must be integer 1024-65535")
except Exception as e:
    logging.error("Invalid configuration: %s", e)
    sys.exit(1)


###  Concurrency control: limit number of simultaneous shell commands

_command_semaphore = asyncio.Semaphore(MAX_CONCURRENT_COMMANDS)
_active_processes: set[asyncio.subprocess.Process] = set()   # Track currently running subprocesses

# --------------------------------------------------------------------------- #
# Helper Functions
# --------------------------------------------------------------------------- #
def is_path_allowed(prog_path: str) -> bool:
    """Return True if binary is in an allowed directory."""
    try:
        real_path = os.path.realpath(prog_path)
        return any(real_path.startswith(allowed + "/") for allowed in ALLOWED_PATHS)
    except Exception:
        return False

def is_command_allowed(command_str: str) -> tuple[bool, str]:  #pylint: disable=too-many-return-statements
    """ Return True if all programs called bycommand string are in the white list and not in the blacklist.
        Also returns True if 'ALLOW_ALL_USER_COMMANDS' is True
    """

    if ALLOW_ALL_USER_COMMANDS:
        return True, "All commands allowed"

    # Extract all programs in the potentially compound command
    programs = set()
    parts = SEP_REGEX.split(command_str)
    for part in parts:
        part = part.strip()
        if not part:
            continue
        try:
            tokens = shlex.split(part)
            if tokens:
                prog = tokens[0]
                programs.add(prog)
        except (ValueError, IndexError):
            continue

    if not programs:
        return False, "No programs found"

    for prog in programs:
        # 1. Program not found
        prog_path = shutil.which(prog) or ""
        if not prog_path:
            return False, f"Program not found: {prog}"

        # 2. PATH restriction
        if not is_path_allowed(prog_path):
            return False, f"Program not in allowed paths: {prog_path}"

        # 3. Whitelist — Allow if whitelisted; deny if not
        # Note whitelist overrides blacklist if set
        if COMPILED_WHITELIST_REGEX is not None:
            if not COMPILED_WHITELIST_REGEX.fullmatch(prog):
                return False, f"Program not in Whitelist: {prog}"
            continue

        # 4. Blacklist — Deny if blacklisted
        if COMPILED_BLACKLIST_REGEX.fullmatch(prog):
            return False, f"Blacklisted program: {prog}"


    return True, "Safe - Whitelisted"

# --------------------------------------------------------------------------- #
# Core functions
# --------------------------------------------------------------------------- #

CommandKey = Literal["url", "timeout", "args", "cmd", "cmds", "cmd_timeout"]

async def execute_command(command: str|list[str], *, timeout: int | None = None, allow_command: bool = False,
                          print_stdout: bool = True, print_stderr: bool = True, log_prefix: str = "execute_command") -> dict[str, Any]:
    """
    Execute a shell command safely with concurrency limiting and optional timeout.
    Returns dict containing: success, stdout, stderr, returncode, and possibly error.
    Enforces security model unless ALLOW_ALL_USER_COMMANDS is True
    """

    # Normalize to string for safety check
    if isinstance(command, list):
        if not command:
            return {"success": False, "error": "empty command list"}
        cmd_str = " ".join(shlex.quote(str(x)) for x in command)
        shell = False  # list form so NEVER shell
    else: # String
        cmd_str = command.strip()
        if not cmd_str:
            return {"success": False, "error": "empty command string"}
        needs_shell = bool(re.search(r'["`\' ]|\$[^(]', cmd_str))  #Needs shell if quotes, spaces, backslashes, backquotes, environment variables
        shell = needs_shell or ALLOW_ALL_USER_COMMANDS

    if not allow_command:  # Check that command_allowed
        allowed, reason = is_command_allowed(cmd_str)
        if not allowed:
            logging.error("[%s] COMMAND BLOCKED (%s): %s", log_prefix, reason, repr(command))
            return {"success": False, "error": f"Command blocked: {reason}"}

    logging.info("[%s] Running (%s): %s", log_prefix, "shell" if shell else "exec", repr(command))

    async with _command_semaphore:
        if shell:
            proc = await asyncio.create_subprocess_shell(
                cmd_str,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        else: # Always use exec with list form if shell = False
            args = command if isinstance(command, list) else shlex.split(cmd_str)
            proc = await asyncio.create_subprocess_exec(
                *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )

        _active_processes.add(proc)
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        except asyncio.TimeoutError:
            logging.error("[%s] Timeout after %ds, killing process", log_prefix, timeout or 0)
            with suppress(ProcessLookupError):
                proc.kill()
            await proc.wait()
            return {"success": False, "error": f"Timeout after {timeout}s"}
        finally:
            _active_processes.discard(proc)

        stdout_str = stdout.decode(errors="replace").strip() if stdout else ""
        stderr_str = stderr.decode(errors="replace").strip() if stderr else ""

        if logger.getEffectiveLevel() <= logging.INFO and print_stdout:  # Print stdout
            for line in stdout_str.splitlines():  # Pretty-print output (HA style)
                print(" " + line)
        if logger.getEffectiveLevel() <= logging.ERROR and print_stderr:  # Print stderr
            for line in stderr_str.splitlines():  # Pretty-print output (HA style)
                print(" " + line)

        success = proc.returncode == 0
        if not success:
            logging.error("[%s] Failed (exit %d)", log_prefix, proc.returncode)

        return {
            "success": success,
            "stdout": stdout_str,
            "stderr": stderr_str,
            "returncode": proc.returncode,
        }

# --------------------------------------------------------------------------- #
# Decorator for Internally Defined API endpoint functions
# --------------------------------------------------------------------------- #

# Registry of internal functions
FunctionRegistry: dict[str, Callable[..., Any]] = {}

# Optional custom error message for validation
class ValidatorSpec(TypedDict, total=False):
    """ Class that bundles validation test and error messages for registry function validation tests"""
    test: Callable[[Any], bool]
    err: str

# Accept either callable or dict
Validator = Callable[[Any], bool] | ValidatorSpec

Payload = dict[str, Any]
F = TypeVar('F', bound=Callable[..., Any])
prefix: str | None  = None
def register_function(
        name: str,
        *,
        required: list[str] | None = None,
        optional: list[str] | None = None,
        validators: dict[str, Validator] | None = None,
) -> Callable[[F], F]:
    """
    Register a user-callable internal function.
    Name is the friendly name of the function (without the optional prefix)
    - If the function has a 'timeout' parameter -> validate it
    - If not -> silently inject timeout=None
    - If user passes timeout=0 or omits it -> treat as "no timeout" (timeout=None)
    Returns a decorator
    Use as: @register_function("kiosk.<name>", required=[...], optional=[...], validators={...}
    """

    required = required or []
    optional = optional or []
    validators = validators or {}
    allowed_params = set(required) | set(optional)

    fullname = prefix + "." + name  if prefix is not None else name
    def decorator(func: F) -> F:
        sig = inspect.signature(func)

        @wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            # Case 1: REST style — first arg is dict (Payload)
            if args and isinstance(args[0], dict):
                data = args[0]
            else:
                # Case 2: Shell function style — bind args/kwargs
                bound = sig.bind(*args, **kwargs)
                bound.apply_defaults()
                data = bound.arguments

            # === Validation ===
            missing = [k for k in required if k not in data]
            if missing: # Missing parameters
                raise ValueError(f"{fullname}: Missing required parameters: {missing}")

            extra = [k for k in data if k not in allowed_params and k != "timeout"]
            if extra: # Extra parameters
                raise ValueError(f"{fullname}: Unknown parameters: {extra}")

            for key, spec in validators.items(): # Custom validation
                if key not in data:
                    continue

                value = data[key]
                if isinstance(spec, dict):
                    test = spec["test"]
                    err = spec.get("err", f"{key} is invalid")
                else:
                    test = spec
                    err = f"{key} is invalid"

                if not test(value):
                    raise ValueError(f"{fullname}: {err}")

            # === Smart timeout handling (only for internal functions) ===
            if "timeout" in data:
                raw = data["timeout"]
                if raw is not None:
                    if not isinstance(raw, int) or raw <= 0:
                        raise ValueError(f"{name}: Timeout must be int > 0 or omitted, got {raw!r}")
                    data["timeout"] = raw

            data["_cmd_name"] = fullname  # Inject _cmd_name

            # === Call original function ===
            if args and isinstance(args[0], dict):
                return func(data)                # REST style payload
            return func(**data)                  # Internal function style args

        wrapper.__name__ = func.__name__
        wrapper.__doc__ = func.__doc__
        FunctionRegistry[fullname] = wrapper  # Register function
        return cast(F, wrapper)

    return decorator

# --------------------------------------------------------------------------- #
# API endpoints
# --------------------------------------------------------------------------- #

PROTECTED_COMMANDS = {  # These commands can only be run on localhost unless REST_BEARER_TOKEN set and used
    "run_command",
    "run_commands",
    "xset",  # if you want
}

HTTP_GET_COMMANDS = {  # Commands using GET (rather than POST) method
    "is_display_on",
    "current_processes"
}

@register_function("launch_url", required=["url"], validators={"url": is_valid_url})
async def handle_launch_url(data: Payload) -> dict[str, Any]:
    """Launch browser with given URL."""
    url = str(data["url"])
    if not url.startswith(("http://", "https://")):
        url = "http://" + url
    result = await execute_command(f"luakit -n '{url}' &", log_prefix="launch_url", allow_command=True)
    return {"success": result["success"], "result": result}

@register_function("refresh_browser")
async def handle_refresh_browser(data: Payload) -> dict[str, Any]:  # pylint: disable=unused-argument
    """Send Ctrl+R to refresh browser."""
    result = await execute_command( ["xdotool", "key", "--clearmodifiers", "ctrl+r"],
                                    timeout=SHORT_TIMEOUT, log_prefix="refresh_browser", allow_command=True)
    return {"success": result["success"]}

@register_function("is_display_on")  # GET endpoint – we register manually below
async def handle_is_display_on(data: Payload) -> dict[str, Any]:  # pylint: disable=unused-argument
    """Return boolean whether monitor is currently on."""
    result = await execute_command(["xset", "-q"], print_stdout=False,
                                   timeout=SHORT_TIMEOUT, log_prefix="is_display_on", allow_command=True)
    if not result["success"]:
        return {"success": False, "error": "Failed to query display state"}

    is_on = "Monitor is On" in result["stdout"]
    logging.info("[is_display_on] Monitor is %s", "ON" if is_on else "OFF")
    return {"success": True, "display_on": is_on}

@register_function("display_on", optional=["timeout"], validators={"timeout": lambda x: x is None or (isinstance(x, int) and x >= 0)})
async def handle_display_on(data: Payload) -> dict[str, Any]:
    """Turn display on, optionally set blanking timeout. If 0, then disables timeout"""
    blank_timeout = data.get("timeout")

    cmds = [ ["xset", "dpms", "force", "on"] ]
    log_msg = ""
    if blank_timeout is None:
        pass
    elif blank_timeout == 0:
        cmds += [ ["xset", "s", "off"], ["xset", "-dpms"] ]
        log_msg = " Screen timeout disabled"
    elif blank_timeout > 0:
        t = str(blank_timeout)
        cmds += [ ["xset", "s", t], ["xset", "dpms", t, t, t] ]
        log_msg = f" Screen timeout: {blank_timeout}s"

    results = [await execute_command(cmd, timeout=SHORT_TIMEOUT, log_prefix="display_on", allow_command=True) for cmd in cmds]
    logging.info("[display_on]%s", log_msg)
    return {"success": all(r["success"] for r in results), "results": results}

@register_function("display_off")
async def handle_display_off(data: Payload) -> dict[str, Any]:  # pylint: disable=unused-argument
    """Force display off immediately."""
    result = await execute_command(["xset", "dpms", "force", "off"],
                                   timeout=SHORT_TIMEOUT, log_prefix="display_off", allow_command=True)
    return {"success": result["success"]}

@register_function("current_processes")  # GET endpoint
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

@register_function("xset", required=["args"], validators={"args": lambda x: isinstance(x, str) and bool(x.strip())})
async def handle_xset(data: Payload) -> dict[str, Any]:
    """Run arbitrary xset command (sanitized)."""
    args = data["args"]
    # Block dangerous shell metacharacters — even with allow_all_user_commands=False
    dangerous_tokens = [tok for tok in DANGEROUS_SHELL_TOKENS if tok in args]
    if dangerous_tokens:
        return {"success": False, "error": "Forbidden shell metacharacters in xset args: {dangerous_tokens}"}
    args_list = shlex.split(args)  # Convert to list for safer execution
    result = await execute_command(["xset"] + args_list, timeout=SHORT_TIMEOUT, log_prefix="xset", allow_command=True)
    return {"success": result["success"], "result": result}

@register_function("run_command", required=["cmd"], optional=["cmd_timeout"],
              validators={"cmd_timeout": lambda x: x is None or (isinstance(x, int) and x > 0)})
async def handle_run_command(data: Payload) -> dict[str, Any]:
    """Execute a single user-supplied command (if allowed)."""
    cmd = data["cmd"]
    timeout = data.get("cmd_timeout")
    result = await execute_command(cmd, timeout=timeout, log_prefix="run_command")
    return {"success": result["success"], "result": result}

@register_function("run_commands", required=["cmds"], optional=["cmd_timeout"],
              validators={"cmd_timeout": lambda x: x is None or (isinstance(x, int) and x > 0)})
async def handle_run_commands(data: Payload) -> dict[str, Any]:
    """Execute multiple user-supplied commands sequentially."""
    raw_cmds = data["cmds"]
    if not isinstance(raw_cmds, list):
        return {"success": False, "error": "'cmds' must be a list"}

    timeout = data.get("cmd_timeout")
    results = []
    for cmd in raw_cmds:
        if not isinstance(cmd, (str, list)):
            results.append({"success": False, "error": f"Invalid command type ({type(cmd)}): {cmd!r}"})
            continue
        res = await execute_command(cmd, timeout=timeout, log_prefix="run_commands")
        results.append(res)

    return {"success": all(r["success"] for r in results), "results": results}

# --------------------------------------------------------------------------- #
# Security middleware
# --------------------------------------------------------------------------- #

@web.middleware  #type: ignore[misc]
async def security_middleware(
        request: web.Request, handler: Callable[[web.Request], Awaitable[web.Response]]
) -> web.Response:
    """
    aiohttp middleware that:
    - Enforces Bearer token authentication.
    - Blocks PROTECTED_COMMANDS if not calling from localhost/127.0.0.1

    Note: If REST_BEARER_TOKEN environment variable is set (non-empty), every incoming request must contain the header:
        Authorization: Bearer <token>

    If the token is missing or invalid → returns HTTP 401 immediately.
    Otherwise passes the request to the next handler.
    """
    if REST_BEARER_TOKEN:
        auth_header = request.headers.get("Authorization", "")
        if auth_header != f"Bearer {REST_BEARER_TOKEN}":
            logging.warning("[auth] Invalid REST_BEARER_TOKEN from %s", request.remote or "unknown")
            return web.json_response(
                {"success": False, "error": "Invalid or missing REST_BEARER_TOKEN Authorization token"},
                status=401,)

    cmd_name = getattr(handler, "cmd_name")
    if cmd_name in PROTECTED_COMMANDS:
        remote_ip = request.remote or "unknown"
        if  remote_ip not in ("127.0.0.1", "::1", "localhost") and REST_BEARER_TOKEN is None:
            logging.warning("[security] Blocked protected REST command from %s: %s", remote_ip, cmd_name)
            return web.json_response({
                "success": False,
                "error": "Protected REST commands require localhost or bearer token"
            }, status=403)
    return await handler(request)

# --------------------------------------------------------------------------- #
# Application factory
# --------------------------------------------------------------------------- #

async def create_app() -> web.Application:
    """Create and configure the aiohttp Application instance."""

    app = web.Application(middlewares=[security_middleware])

    # Register routes for defined functions
    for fullname, func in FunctionRegistry.items():
        route = f"/{fullname}"

        async def make_handler(request: web.Request, function: Callable[..., Any] = func, name: str = fullname) -> web.Response:
            payload = await request.json() if request.can_read_body else {}
            try:
                result = await function(payload)
                return web.json_response(result)
            except Exception as e:
                logging.exception("Handler error: %s", name)
                return web.json_response({"success": False, "error": str(e)}, status=500)

        make_handler.cmd_name = fullname  # type: ignore[attr-defined]

        if fullname in HTTP_GET_COMMANDS:
            app.router.add_get(route, make_handler)
        else:
            app.router.add_post(route, make_handler)

    # === Special routes ===
    # Health check — always allowed, no auth, no protection
    app.router.add_get("/health", lambda _: web.json_response({"status": "ok"}))

    # Catch-all 404 — clean and safe
    async def not_found(request: web.Request) -> web.Response:
        logging.warning("[404] %s %s from %s", request.method, request.path, request.remote or "unknown")
        return web.json_response(
            {"success": False, "error": f"Endpoint not found: {request.path}"},
            status=404
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
