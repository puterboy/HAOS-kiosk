################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: Dockerfile
# Version: 1.3.2.2
# Original Copyright Jeff Kosowsky
# updated to support fonts, chrome, remove static lua version from alpine that is not used by HA.
# Corrections by TrooperThorn
# REMOVED openbox, luakit, onboard, and xdotool are completely removed.
# Date: August 2026
################################################################################
# 64 Bit systems ONLY
ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM ${BUILD_FROM}
#===============================================================================
# Install Cage, Chromium, and necessary hardware drivers
RUN apk add --no-cache \
    cage \
    chromium \
    eudev \
    mesa-dri-gallium \
    mesa-egl \
    mesa-gl \
    mesa-gles \
    seatd \
    wayland \
    font-noto \
    font-noto-emoji \
    wlr-randr \
    wtype \
    wlopm

# Copy the execution script into the container
COPY run.sh /run.sh
RUN chmod a+x /run.sh

# Start the script when the container launches
CMD [ "/run.sh" ]
