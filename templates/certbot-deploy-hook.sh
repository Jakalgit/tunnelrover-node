#!/bin/bash
# Reloads the shared nginx and restarts the Hysteria container whose certificate was renewed.
set -u

if command -v systemctl >/dev/null 2>&1; then
  systemctl reload nginx || true
fi

shopt -s nullglob
for envfile in /etc/tunnelrover/nodes/*.env; do
  domain=""
  container=""
  # shellcheck disable=SC1090
  source "$envfile"
  for renewed in ${RENEWED_DOMAINS:-}; do
    if [[ -n "$domain" && "$renewed" == "$domain" && -n "$container" ]]; then
      docker restart "$container" || true
    fi
  done
done
