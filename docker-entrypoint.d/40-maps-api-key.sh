#!/bin/sh
set -eu

if [ -z "${GOOGLE_MAPS_API_KEY:-}" ]; then
  echo "GOOGLE_MAPS_API_KEY must be set for the Flutter web map." >&2
  exit 1
fi

sed "s|YOUR_GOOGLE_MAPS_API_KEY|${GOOGLE_MAPS_API_KEY}|g" \
  /usr/share/nginx/html/maps-config.js > /tmp/maps-config.js
mv /tmp/maps-config.js /usr/share/nginx/html/maps-config.js
