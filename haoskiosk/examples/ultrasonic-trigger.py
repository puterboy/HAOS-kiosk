#!/usr/bin/env sh
"exec" "sudo" "$(dirname $(readlink -f $0))/venv/bin/python3" "$0" "$@"
#"exec" "$(dirname $0)/venv/bin/python3" "$0" "$@"
#Above lines used to invoke venv relative to current directory
#See: https://stackoverflow.com/questions/20095351/shebang-use-interpreter-relative-to-the-script-path

#Below shebang line only works if call strict from the script directory
#!$(dirname $0)/venv/bin/python3
#Below shebang line only works if already activated virtual environment
#!/usr/bin/env python3

################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: ultrasonic-trigger.py
# Version: 1.1.0
# Copyright Jeff Kosowsky
# Date: September 2025
#
# Use a FTDI FT232H USB-GPIO board to monitor the output of an ultrasonic
# HC-SR04 type distance sensor
#   - Print out distance every LOOPTIME seconds
#   - Turn on monitor if distance < NEAR_ON_DIST for COUNT_ON_THRESH seconds
#   - Turn off monitor if distance > FAR_OFF_DIST for COUNT_OFF_THRESH seconds
#
# When measuring distance:
#   - Take GPIO_READINGS_TO_AVERAGE and average the valid ones
#   - Mark as invalid measurement if more than half of the readings are errors
#   - Restart if more than INVALID_COUNT_THRESHOLD invalid measurements in a row
#
# Also, optionally, if the HA sensor HA_BINARY_SENSOR is set and evaluates to true,
# then don't measure distance and leave display in DEFAULT_DISPLAY_STATE
# This can be used to make the auto on/off  depend on the state of a sensor in HA.
#
#
# NOTES:
#   - Requires adding the following Python libraries: pyftdi, requests
#     Probably best to install in venv so it persists reboots
#   - Should run as root (e.g., 'sudo')
#
################################################################################
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
################################################################################


import logging
import os
import signal
import sys
import time
import types
from datetime import datetime, timedelta
import requests
from pyftdi.gpio import GpioController  # type: ignore[import-untyped]
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

#Relaunch 'unbuffered' if not already unbuffered so that you can pipe output real-time if desired
if os.environ.get('PYTHONUNBUFFERED') != '1':
    os.environ['PYTHONUNBUFFERED'] = '1'
    os.execvp(sys.executable, [sys.executable] + sys.argv)

# Suppress urllib3 retry warnings
logging.getLogger("urllib3").setLevel(logging.ERROR)

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
#    level=logging.DEBUG,
    format='%(asctime)s [%(funcName)s] %(levelname)s: %(message)s',
    datefmt="%H:%M:%S"
)
logger = logging.getLogger(__name__)

################################################################################
### Configurable variables

# Configure ultrasonic sensor readings
TRIG_PIN = 0                  # AD0 - Output
ECHO_PIN = 1                  # AD1 - Input
GPIO_READINGS_TO_AVERAGE = 5  # Number of distance readings to average
WAIT_TIMEOUT = 0.05           # Timeout for wait_for_pin (seconds) (this is conservative)
                              # Note HC-SR04 pulls pin low after 38ms (which with speed of sound 343m/s is equivalent to ~6.5m each way)
# HA general variables
HA_PORT = 8123
HA_BEARER_TOKEN = None       # Needed if using HA_BINARY_SENSOR

HA_BINARY_SENSOR=None        # Optional binary sensor to determine whether to measure distance and turn on/off display
HA_BINARY_SENSOR_FRIENDLY_NAME=None #Optional Friendly Name for binary sensor
if HA_BINARY_SENSOR_FRIENDLY_NAME is None and HA_BINARY_SENSOR is not None:
    #Get string after last '.', replace '_' with space, capitalize words
    HA_BINARY_SENSOR_FRIENDLY_NAME = HA_BINARY_SENSOR.rsplit('.', 1)[-1].replace('_', ' ').title()

DEFAULT_DISPLAY_STATE=True  # Default display state if HA_BINARY_SENSOR is 'True' (False=off; True=on)

# Configure REST API
REST_PORT = 8080
REST_BEARER_TOKEN=""

# Other parameters
LOOP_TIME = 1                 # Target loop time (seconds) - i.e., target time between distance measurements
NEAR_ON_DIST = 150            # Near distance threshold (in cm) before turning display on
FAR_OFF_DIST = 200            # Far distance threshold (in cm) before turning display off
COUNT_ON_THRESH = 2           # Number of 'near' distance measurements before turning on
COUNT_OFF_THRESH = 4          # Number of 'far' distance measurements before turning off


INVALID_COUNT_THRESHOLD= 10   # Number of consecutive invalid measurements before restarting
HTTP_TIMEOUT = 3              # Timeout for HTTP get and posts

################################################################################
### Ultrasonic distance sensing

TRIG_MASK = 1 << TRIG_PIN
ECHO_MASK = 1 << ECHO_PIN

# Setup ultrasonic sensor
gpio = GpioController()
try:
    gpio.configure('ftdi://ftdi:232h/1', direction=TRIG_MASK)  # TRIG = output, ECHO = input
except Exception as e:
    logger.error("Ultrasonic trigger GPIO initialization failed...exiting (%s)", e)
    sys.exit(1)

def handle_exit(_signum: int, _frame: types.FrameType | None) -> None:
    """Exit handler"""
    sys.exit(0)

# Register signals
for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, handle_exit)

def send_trigger_pulse()-> bool:
    """Send ultrasonic trigger pulse"""
    try:
        gpio.write(0)
        time.sleep(0.000002)  # 2 µs
        gpio.write(TRIG_MASK)  # Set TRIG high
        time.sleep(0.00001)    # 10 us pulse
        gpio.write(0)
        return True
    except Exception as e:
        logger.debug("GPIO write FAILED (%s)", e)
        return False

def wait_for_pin(echo_mask: int, echo_level: bool, timeout: float=WAIT_TIMEOUT) -> int | None:
    """Wait for pin"""
    timeout_ns = int(timeout * 1e9)
    start_ns = time.monotonic_ns()
    try:
        while (time_ns := time.monotonic_ns()) - start_ns < timeout_ns:
            if bool(gpio.read() & echo_mask) == echo_level:
                return time_ns
        return None
    except Exception as e:
        logger.debug("GPIO read FAILED (%s)", e)
        return None

invalid_count = 0  # Number of consecutive invalid measurements
def measure_distance() -> float | None:
    """Measure distance"""
    distances = []
    errors = 0
    for _ in range(GPIO_READINGS_TO_AVERAGE):
        if not send_trigger_pulse():
            errors += 1
            continue

        start_time = wait_for_pin(ECHO_MASK, True)
        if start_time is None:
            logger.debug("Timeout waiting for ECHO to go HIGH")
            errors += 1
            continue

        end_time = wait_for_pin(ECHO_MASK, False)
        if end_time is None:
            logger.debug("Timeout waiting for ECHO to go LOW")
            errors += 1
            continue

        pulse_duration_us = (end_time - start_time) / 1000  # ns to µs
        distance_cm = pulse_duration_us / 58.0  # HC-SR04 spec
        if distance_cm > 0:  # Skip invalid (negative or zero) distances
            distances.append(distance_cm)
        else:
            errors += 1
        time.sleep(0.01)  # Small delay between readings to avoid sensor overload

    global invalid_count
    if errors >= (GPIO_READINGS_TO_AVERAGE / 2):
        invalid_count +=1
        if invalid_count > INVALID_COUNT_THRESHOLD:
            logger.error("Too many invalid measurements (%d), restarting...", INVALID_COUNT_THRESHOLD)
            try:
                gpio.close()
            except Exception:
                pass
            os.execv(sys.executable, [sys.executable] + sys.argv)  # Restart...
        return None
    invalid_count = 0  # Reset invalid counter
    return sum(distances) / len(distances) if distances else None

################################################################################
### HAOKiosk monitor control

# Setup HTTP retry
session = requests.Session()
retries = Retry(total=3, backoff_factor=0.1, status_forcelist=[429, 500, 502, 503, 504], raise_on_status=False)
session.mount("http://", HTTPAdapter(max_retries=retries))

def display_state() -> bool:
    """Return display state"""
    url = f"http://localhost:{REST_PORT}/is_display_on"
    try:
        response = session.get(
            url,
            headers={"Authorization": f"Bearer {REST_BEARER_TOKEN}"},
            timeout = HTTP_TIMEOUT,
        )
        response.raise_for_status()
        data = response.json()
        if not data.get("success", False):
            logger.error("Failed to get display state")
            return False
        return data["display_on"] is True
    except (requests.RequestException, ValueError) as e:
        logger.error("HTTPRequest failed (%s)", e)
        return False

def display_state_print() -> None:
    """Print display state"""
    global display
    try:
        display = display_state()
        if display is True:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M')}] Display is ON")
        else:
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M')}] Display is OFF")
    except (requests.RequestException, ValueError) as e:
        logger.error("Display is INVALID (%s)", e)

def display_on() -> bool:
    """Turn display on"""
    url = f"http://localhost:{REST_PORT}/display_on"
    try:
        response = session.post(
            url,
            headers={"Authorization": f"Bearer {REST_BEARER_TOKEN}"},
            timeout = HTTP_TIMEOUT,
        )
        response.raise_for_status()
        data = response.json()
        if not data.get("success", False):
            logger.error("Failed to get display state")
            return False
        return True
    except (requests.RequestException, ValueError) as e:
        logger.error("HTTPRequest failed (%s)", e)
        return False

def display_off() -> bool:
    """Turn display off"""
    url = f"http://localhost:{REST_PORT}/display_off"
    try:
        response = session.post(
            url,
            headers={"Authorization": f"Bearer {REST_BEARER_TOKEN}"},
            timeout = HTTP_TIMEOUT,
        )
        response.raise_for_status()
        data = response.json()
        if not data.get("success", False):
            return False
        return True
    except (requests.RequestException, ValueError) as e:
        logger.error("HTTPRequest failed (%s)", e)
        return False

last_display_time = datetime.now()
def display_on_print() -> None:
    """Turn on display and show duration since last on"""
    global last_display_time
    old_display_time = last_display_time
    last_display_time = datetime.now()
    display_time_diff = last_display_time - old_display_time
    display_time_diff = display_time_diff - timedelta(microseconds=display_time_diff.microseconds)

    if display_on():
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M')}] ***Turning display ON*** (Duration: {display_time_diff})")
        global display
        display = True
    else:
        logger.error("FAILED to turn display ON")

def display_off_print() ->None:
    """Turn off display and show duration since last off"""
    global last_display_time
    old_display_time = last_display_time
    last_display_time = datetime.now()
    display_time_diff = last_display_time - old_display_time
    display_time_diff = display_time_diff - timedelta(microseconds=display_time_diff.microseconds)

    if display_off():
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M')}] ***Turning display OFF*** (Duration: {display_time_diff})")
        global display
        display = False
    else:
        logger.error("FAILED to turn display OFF")

def ha_binary_sensor_state(sensor: str) -> bool | None:
    """Show state of binary sensor used to turn/off ultrasonic-governed display mechanism"""
    if sensor is None:
        return None
    url = f"http://localhost:{HA_PORT}/api/states/{sensor}"
    try:
        response = session.get(
            url,
            headers={"Authorization": f"Bearer {HA_BEARER_TOKEN}"},
            timeout = HTTP_TIMEOUT,
        )
        response.raise_for_status()

        data: dict[str, str] = response.json()
        state = data.get("state")
        if state not in ("on", "off"):
            logger.debug("Unexpected state value: %s", state)
            return None
        return state == "on"

    except (requests.RequestException, ValueError) as e:
        logger.error("HTTP Request failed (%s)", e)
        return None

################################################################################
### Main loop

display = False
loop_num = -1
count = 0
binary_sensor_state = None
try:
    while True:
        loop_start = time.monotonic()
        loop_num += 1
        if not loop_num % 60:  # HA_BINARY_SENSOR state once a minute
                               # Also, update display state in case gets out of sync
            old_binary_sensor_state = binary_sensor_state
            binary_sensor_state = ha_binary_sensor_state(HA_BINARY_SENSOR)
            if binary_sensor_state is not None and binary_sensor_state != old_binary_sensor_state:  # Status of binary_sensor_state changed
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M')}] '{HA_BINARY_SENSOR_FRIENDLY_NAME}' = {binary_sensor_state}")
                if binary_sensor_state:  # Binary sensor turned on so set to default state
                    if DEFAULT_DISPLAY_STATE:
                        display_on_print()  # Default true
                    else:
                        display_off_print()  # Default false
            if not binary_sensor_state:
                display_state_print()  # Set and show display state every 60 seconds

        if binary_sensor_state:  # Avoid calculating distance & turning on/off display
            time.sleep(LOOP_TIME)
            continue

        distance = measure_distance()
        if distance is not None:
            distance_ft = distance / 30.48
            print(f"Distance: {distance_ft:.2f} ft ({int(distance)} cm)")
            if distance < NEAR_ON_DIST:
                count = max(count, 0)
                count += 1
                if display is False and count >= COUNT_ON_THRESH:
                    display_on_print()  # Turn ON display
            elif distance > FAR_OFF_DIST:
                count = min(count, 0)
                count -= 1
                if display is True and count <= -COUNT_OFF_THRESH:
                    display_off_print()  # Turn OFF display
        else:
            print("Distance: Invalid")

        loop_duration = time.monotonic() - loop_start
        sleep_time = max(0, LOOP_TIME - loop_duration)
        logger.debug("Sleeping for %.3f seconds", sleep_time)
        if sleep_time > 0:
            time.sleep(sleep_time)

finally:
    try:
        if display is False:
            display_on_print()  # Turn display back on...
        gpio.close()
    except Exception as e:
        logger.error("Error: GPIO close failed (%s)", e)
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M')}] Exiting...")

# vim: set filetype=python :
# Local Variables:
# mode: python
# End:
