################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: Dockerfile
# Version: 1.0.0
# Copyright Jeff Kosowsky
# Date: July 2025
################################################################################

ARG BUILD_FROM
FROM $BUILD_FROM

# Install Luakit and necessary dependencies
RUN apk update && apk add --no-cache \
    xorg-server \
    xf86-video-modesetting \
    xf86-input-libinput \
    libinput \
    udev \
    libinput-udev \
    libevdev \
    mesa-dri-gallium \
    mesa-egl \
    mesa-gles \
    libdrm \
    libxkbcommon \
    openbox \
    ttf-dejavu \
    util-linux \
    xset \
    xdotool \
    xrandr \
    xinput \
    bash \
    && apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/v3.21/community luakit=2.3.6-r0 \
    && rm -rf /var/cache/apk/*

# Set the display variable
ENV DISPLAY=:0

# Copy over 'xorg.conf' and lua 'userconf.lua' file
COPY xorg.conf /etc/X11/xorg.conf
COPY userconf.lua /root/.config/luakit/userconf.lua
COPY translations/*.yaml /translations/

COPY run.sh /
RUN chmod a+x /run.sh

COPY tag-input-devices.sh rotate_touch_input.sh /
RUN chmod a+x /tag-input-devices.sh /rotate_touch_input.sh

CMD ["/run.sh"]
