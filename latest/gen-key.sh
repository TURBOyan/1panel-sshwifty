#!/bin/sh
# Generate the shared SSH keypair used by the Sshwifty presets.
#
# The container user cannot generate keys (the image has no ssh-keygen),
# so the pair is created here on the host and bind-mounted read-only.
#
# Idempotent: an existing key is reused, never overwritten. To force a new
# key, delete ssh-keys/ and run this again (you must then re-add the new
# public key to every target machine).
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
KEY_DIR="$DIR/ssh-keys"
KEY="$KEY_DIR/id_ed25519"

# The image runs as uid:gid 1000 ("sshwifty"); the mounted key must be
# readable by that user even though its mode is 600.
OWNER="${SSHWIFTY_KEY_OWNER:-1000:1000}"

if [ -f "$KEY" ]; then
	echo "Reusing existing key: $KEY"
else
	mkdir -p "$KEY_DIR"
	ssh-keygen -t ed25519 -N '' -C 'sshwifty-shared' -f "$KEY"
	echo "Generated new keypair: $KEY"
fi

chown "$OWNER" "$KEY" "$KEY.pub"
chmod 600 "$KEY"
chmod 644 "$KEY.pub"

echo
echo "Add this PUBLIC key to every target machine's ~/.ssh/authorized_keys:"
echo "--------------------------------------------------------------------"
cat "$KEY.pub"
echo "--------------------------------------------------------------------"
