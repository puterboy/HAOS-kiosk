#!/usr/bin/bashio

bashio::log.info "Configuring Wayland runtime environment..."

export XDG_RUNTIME_DIR=/tmp/xdg
mkdir -p $XDG_RUNTIME_DIR
chmod 0700 $XDG_RUNTIME_DIR
export WAYLAND_DISPLAY=wayland-0

# 1. Read your specific UI options
URL=$(bashio::config 'ha_url')
ROTATION_CONFIG=$(bashio::config 'rotate_display')
IGNORE_CERTS=$(bashio::config 'ignore_certificate_errors')

# 2. Map your rotation values to wlroots standard transforms
case $ROTATION_CONFIG in
    "normal")
        export WLR_OUTPUT_TRANSFORM="normal"
        ;;
    "right")
        export WLR_OUTPUT_TRANSFORM="90"
        ;;
    "inverted")
        export WLR_OUTPUT_TRANSFORM="180"
        ;;
    "left")
        export WLR_OUTPUT_TRANSFORM="270"
        ;;
    *)
        export WLR_OUTPUT_TRANSFORM="normal"
        ;;
esac

bashio::log.info "Display rotation set to: ${WLR_OUTPUT_TRANSFORM}"

# 3. Build Chromium flags
CHROMIUM_FLAGS="--kiosk --no-sandbox --enable-features=UseOzonePlatform --ozone-platform=wayland --disable-infobars"

if bashio::config.true 'ignore_certificate_errors'; then
    CHROMIUM_FLAGS="${CHROMIUM_FLAGS} --ignore-certificate-errors"
fi

bashio::log.info "Starting Cage with Chromium pointing to: ${URL}"

# 4. Execute Cage and Chromium
exec cage -s -- chromium-browser ${CHROMIUM_FLAGS} "${URL}"
    exec sleep infinite
fi
