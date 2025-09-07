################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: Dockerfile
# Version: 1.1.0
# Copyright Jeff Kosowsky
# Date: September 2025
################################################################################

ARG BUILD_FROM
FROM $BUILD_FROM

# Install Luakit and necessary dependencies
RUN apk update && apk add --no-cache \
    xorg-server \
    xf86-video-modesetting \
    xf86-input-libinput \
    libinput \
#   libinput-tools \
    udev \
    libinput-udev \
    libevdev \
    mesa-dri-gallium \
    mesa-egl \
    mesa-gles \
    libdrm \
    libxkbcommon \
    ttf-dejavu \
    util-linux \
    xdotool \
    xinput \
    xrandr \
    xset \
    unclutter-xfixes \
    setxkbmap \
    openbox \
#    xfce4-settings \
#    xfwm4 \
#    xfce4-session \
    onboard \
    py3-pip \
    python3-tkinter \
    patch \
    bash \
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

COPY toggle_keyboard.py rest_server.py /
RUN pip install --no-cache-dir  --break-system-packages aiohttp #Required for rest_server.py

# Need to patch 'unique_instance.lua' so that new instance urls overwrite active url rather than add new tab
COPY unique_instance.patch /usr/share/luakit/lib
RUN patch -p2 /usr/share/luakit/lib/unique_instance.lua < /usr/share/luakit/lib/unique_instance.patch

CMD ["/run.sh"]
