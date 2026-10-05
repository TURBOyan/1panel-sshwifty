#!/bin/sh
# Bring up the Sshwifty instance: generate the shared keypair (if absent),
# then start the container.
#
# Kept as a wrapper so the key always exists before Sshwifty reads
# sshwifty.conf.json -- the "Private Key" preset field is resolved from
# file:// at startup, and the config loader has no fallback.
set -eu

cd "$(cd "$(dirname "$0")" && pwd)"

# Required by the 1Panel template's variable substitution. 1Panel normally
# injects these from its own .env; supply defaults when running by hand.
CONTAINER_NAME="${CONTAINER_NAME:-sshwifty-preset-test}"
PANEL_APP_PORT_HTTP="${PANEL_APP_PORT_HTTP:-8182}"
export CONTAINER_NAME PANEL_APP_PORT_HTTP

./gen-key.sh

exec docker compose up -d
