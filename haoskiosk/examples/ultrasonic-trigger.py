################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: ultrasonic-trigger.py
# Version: 1.1.1
# Copyright Jeff Kosowsky
# Date: September 2025
#
# Use a FTDI FT232H USB-GPIO board to monitor the output of an ultrasonic
# HC-SR04 type distance sensor
#   - Print out distance every second
#   - Turn on monitor if distance < NEAR_ON_DIST for COUNT_ON_THRESH seconds
#   - Turn off monitor if distance > FAR_OFF_DIST for COUNT_OFF_THRESH seconds
#
# Also, optionally, don't measure distance and leave display in DEFAULT_DISPLAY_STATE
# if the HA sensor HA_BINARY_SENSOR is set and evaluates to true.
# This can be used to make the auto on/off  depend on the state of a sensor in HA.
#
# NOTES:
#   - Requires adding the following Python libraries: pyftdi, requests
#     Probably best to install in venv so it persists reboots
#   - Should run as root (e.g., 'sudo')
#
################################################################################

import sys
import time
import requests
from pyftdi.gpio import GpioController
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from datetime import datetime
import logging

# Suppress urllib3 retry warnings
logging.getLogger("urllib3").setLevel(logging.ERROR)

logging.basicConfig(
    stream=sys.stdout,
#    level=logging.DEBUG,
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s: [%(filename)s] %(message)s",
    datefmt="%H:%M:%S"
)

################################################################################
### Configurable variables

# Configure ultrasonic sensor readings
TRIG_PIN = 0                  # AD0 - Output
ECHO_PIN = 1                  # AD1 - Input
GPIO_READINGS_TO_AVERAGE = 5  # Number of distance readings to average
WAIT_TIMEOUT = 0.05           # Timeout for wait_for_pin (seconds)
                              # Note HC-SR04 pulls pin low after 38ms (which with speed of sound 343m/s is equivalent to ~6.5m each way)

# HA general variables
HA_PORT = 8123
HA_BEARER_TOKEN = None       # Needed if using HA_BINARY_SENSOR
HA_BINARY_SENSOR=None        # Optional binary sensor to determine whether to measure distance and turn on/off display

DEFAULT_DISPLAY_STATE=True   # Default display state if HA_BINARY_SENSOR is 'True' (False=off; True=on)

# Configure REST API
REST_PORT = 8080
REST_BEARER_TOKEN=""

# Other parameters
LOOP_TIME = 1                 # Target loop time (seconds) - i.e., target time between distance measurements
NEAR_ON_DIST = 150            # Near distance threshold (in cm) before turning display on
FAR_OFF_DIST = 200            # Far distance threshold (in cm) before turning display off
COUNT_ON_THRESH = 3           # Number of 'near' distance measurements before turning on
COUNT_OFF_THRESH = 5          # Number of 'far' distance measurements before turning off

################################################################################
### Ultrasonic distance sensing

TRIG_MASK = 1 << TRIG_PIN
ECHO_MASK = 1 << ECHO_PIN

# Setup ultrasonic sensor
gpio = GpioController()
try:
    gpio.configure('ftdi://ftdi:232h/1', direction=TRIG_MASK)  # TRIG = output, ECHO = input
except Exception as e:
    logging.error(f"[ultrasonic_trigger] Error: GPIO init failed")
    print("Exiting due to GPIO initialization failure")
    sys.exit(1)

def send_trigger_pulse():
    try:
        gpio.write(0)
        time.sleep(0.000002)  # 2 µs
        gpio.write(TRIG_MASK)  # Set TRIG high
        time.sleep(0.00001)    # 10 µs pulse
        gpio.write(0)
        return True
    except Exception as e:
        logging.debug(f"[send_trigger_pulse] Error: GPIO write failed")
        return False

def wait_for_pin(mask, level, timeout=WAIT_TIMEOUT):
    try:
        start = time.monotonic()
        while time.monotonic() - start < timeout:
            if bool(gpio.read() & mask) == level:
                return time.monotonic_ns()
        return None
    except Exception as e:
        logging.debug(f"[wait_for_pin] Error: GPIO read failed")
        return None

def measure_distance():
    distances = []
    errors = 0
    for _ in range(GPIO_READINGS_TO_AVERAGE):
        if not send_trigger_pulse():
            errors += 1
            continue

        start_time = wait_for_pin(ECHO_MASK, True)
        if start_time is None:
            if logging.getLogger().isEnabledFor(logging.DEBUG):
                print("Timeout waiting for ECHO to go HIGH")
            errors += 1
            continue

        end_time = wait_for_pin(ECHO_MASK, False)
        if end_time is None:
            if logging.getLogger().isEnabledFor(logging.DEBUG):
                print("Timeout waiting for ECHO to go LOW")
            errors += 1
            continue

        pulse_duration_us = (end_time - start_time) / 1000  # ns to µs
        distance_cm = pulse_duration_us / 58.0  # HC-SR04 spec
        if distance_cm > 0:  # Skip invalid (negative or zero) distances
            distances.append(distance_cm)
        else:
            errors += 1
        time.sleep(0.01)  # Small delay between readings to avoid sensor overload

    if errors >= (GPIO_READINGS_TO_AVERAGE / 2):
        return None
    return sum(distances) / len(distances) if distances else None

################################################################################
### HAOKiosk monitor control

# Setup HTTP retry
session = requests.Session()
retries = Retry(total=3, backoff_factor=0.1, status_forcelist=[429, 500, 502, 503, 504], raise_on_status=False)
session.mount("http://", HTTPAdapter(max_retries=retries))

def display_state() -> bool:
    url = f"http://localhost:{REST_PORT}/is_display_on"
    try:
        response = session.get(
            url,
            headers={"Authorization": f"Bearer {REST_BEARER_TOKEN}"}
        )
        response.raise_for_status()
        data = response.json()
        if not data.get("success", False):
            logging.debug(f"[display_state] Error: Failed to get state")
            return False
        return data["display_on"]
    except (requests.RequestException, ValueError):
        logging.debug(f"[display_state] Error: Request failed")
        return False

def display_state2() -> bool: #Alternative - uses and parses 'xset -q' command
    url = f"http://localhost:{REST_PORT}/xset"
    try:
        response = session.post(
            url,
            headers={"Authorization": f"Bearer {REST_BEARER_TOKEN}"},
            json={"args": "-q"}
        )
        response.raise_for_status()
        data = response.json()
        if not data.get("success", False) or not data.get("result", {}).get("success", False):
            logging.debug(f"[display_state2] Error: Failed to get state")
            return False
        stdout_text = data["result"].get("stdout", "")
        return "Monitor is On" in stdout_text
    except (requests.RequestException, ValueError):
        logging.debug(f"[display_state2] Error: Request failed")
        return False

def display_state_print():
    global display
    try:
        new_display = display_state()
        if new_display is True:
            display = True
            print('Display is ON')
        elif new_display is False:
            print('Display is OFF')
    except (requests.RequestException, ValueError):
        print('Display is INVALID')

def display_on() -> bool:
    url = f"http://localhost:{REST_PORT}/display_on"
    try:
        response = session.post(
            url,
            headers={"Authorization": f"Bearer {REST_BEARER_TOKEN}"}
        )
        response.raise_for_status()
        data = response.json()
        if not data.get("success", False):
            return False
        return True
    except (requests.RequestException, ValueError):
        return False

def display_on_print():
    if display_on():
        print("***Turning display ON***")
        global display
        display = True
    else:
        print("FAILED to turn display ON")

def display_off() -> bool:
    url = f"http://localhost:{REST_PORT}/display_off"
    try:
        response = session.post(
            url,
            headers={"Authorization": f"Bearer {REST_BEARER_TOKEN}"}
        )
        response.raise_for_status()
        data = response.json()
        if not data.get("success", False):
            return False
        return True
    except (requests.RequestException, ValueError):
        return False

def display_off_print():
    if display_off():
        print("***Turning display OFF***")
        global display
        display = False
    else:
        print("FAILED to turn display OFF")

def is_binary_sensor() -> bool:
    if HA_BINARY_SENSOR is None: return None
    url = f"http://localhost:{HA_PORT}/api/states/{HA_BINARY_SENSOR}"
    try:
        response = session.get(
            url,
            headers={"Authorization": f"Bearer {HA_BEARER_TOKEN}"}
        )
        response.raise_for_status()
        data = response.json()

        state = data.get("state")
        if state not in ("on", "off"):
            logging.debug(f"[is_binary_sensor] Unexpected state value: {state}")
            return False
        return state == "on"

    except (requests.RequestException, ValueError):
        logging.debug(f"[is_binary_sensor] Error: Request failed")
        return False

################################################################################
### Main loop

display = False
loop_num = -1;
count = 0
binary_sensor_state = None
try:
    while True:
        loop_start = time.monotonic()
        loop_num += 1
        if not loop_num % 60:  # HA_BINARY_SENSOR state once a minute
                               # Also, update display state in case gets out of sync
            old_binary_sensor_state = binary_sensor_state
            binary_sensor_state = is_binary_sensor();
            if binary_sensor_state is not None and binary_sensor_state != old_binary_sensor_state:
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M')}] {HA_BINARY_SENSOR}={binary_sensor_state}")
                if binary_sensor_state:
                    if DEFAULT_DISPLAY_STATE:
                        display_on_print()  # Turn on display
                    else:
                        display_off_print()  # Turn off display
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
                if count < 0:
                    count=0
                count += 1
                if display is False and count >= COUNT_ON_THRESH:
                    display_on_print()  # Turn ON display
            elif distance > FAR_OFF_DIST:
                if count > 0:
                    count=0
                count -= 1
                if display is True and count <= -COUNT_OFF_THRESH:
                    display_off_print()  # Turn OFF display
        else:
            print("Distance: Invalid")

        loop_duration = time.monotonic() - loop_start
        sleep_time = max(0, LOOP_TIME - loop_duration)
        if logging.getLogger().isEnabledFor(logging.DEBUG):
            logging.debug(f"Sleeping for {sleep_time:.3f} seconds")
        if sleep_time > 0:
            time.sleep(sleep_time)

except KeyboardInterrupt:
    try:
        gpio.close()
    except Exception as e:
        logging.error(f"[main] Error: GPIO close failed")
    print("\nExiting.")

# vim: set filetype=python :
# Local Variables:
# mode: python
# End:
