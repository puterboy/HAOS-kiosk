################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: toggle_keyboard.py
# Version: 1.1.1
# Copyright Jeff Kosowsky
# Date: September 2025
#
# Creates a 1x1 pixel button at top right corner of screen to toggle onboard
# keyboard on/off.
# If optional parameter is true, then pixel is 'black', otherwise 'white'
################################################################################

import tkinter as tk
import subprocess
import sys

def toggle_keyboard(event):
    subprocess.Popen([
        "dbus-send",
        "--type=method_call",
        "--print-reply",
        "--dest=org.onboard.Onboard",
        "/org/onboard/Onboard/Keyboard",
        "org.onboard.Onboard.Keyboard.ToggleVisible"
    ])

root = tk.Tk()
root.overrideredirect(True)
root.geometry("+{}+{}".format(root.winfo_screenwidth()-1, 0))
root.attributes("-topmost", True)

color = "black" if len(sys.argv) > 1 and sys.argv[1].lower() == "true" else "white"

canvas = tk.Canvas(root, width=1, height=1, highlightthickness=0, bg=color)
canvas.pack()

canvas.bind("<Button-1>", toggle_keyboard)

root.mainloop()
