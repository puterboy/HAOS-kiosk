#!/bin/bash

IMAGE_FOLDER="<relative_path_to_image_folder from /config/www>"
DISPLAY_TIME=10
REST_PORT=8080

cd /config/www || exit
while true; do
    for IMAGE in "$IMAGE_FOLDER"/*; do
        curl -s -X POST http://localhost:$REST_PORT/launch_url -H "Content-Type: application/json" -d "{\"url\": \"localhost:8123/local/$IMAGE\"}" > /dev/null
        sleep "$DISPLAY_TIME"
    done
done
