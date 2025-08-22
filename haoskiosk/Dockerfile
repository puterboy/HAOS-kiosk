################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: Dockerfile
# Version: 1.0.1
# Copyright Jeff Kosowsky
# Date: August 2025
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
    xdotool \
    xinput \
    xrandr \
    xset \
    unclutter-xfixes \
    setxkbmap \
    bash \
    squeekboard \
    && apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/v3.21/community luakit=2.3.6-r0 \
    && rm -rf /var/cache/apk/*

# Set the display variable
ENV DISPLAY=:0

# Copy over 'xorg.conf.default' and lua 'userconf.lua' file
COPY xorg.conf.default /etc/X11/
COPY userconf.lua /root/.config/luakit/
COPY translations/*.yaml /translations/

COPY run.sh /
RUN chmod a+x /run.sh

CMD ["/run.sh"]
