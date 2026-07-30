#!/bin/bash
# Installs controller-vhid-bridge as a root LaunchDaemon so the virtual mouse
# is always available (starts at boot, restarts if it dies).
#
#   sudo ./install.sh          install and start
#   sudo ./install.sh remove   stop and uninstall
set -euo pipefail

LABEL="com.toby.controller.vhidbridge"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
DEST="/usr/local/libexec/controller-vhid-bridge"
SRC="$(cd "$(dirname "$0")" && pwd)/controller-vhid-bridge"

if [ "$(id -u)" != "0" ]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

if [ "${1:-}" = "remove" ]; then
  launchctl bootout system "$PLIST" 2>/dev/null || true
  rm -f "$PLIST" "$DEST"
  echo "removed"
  exit 0
fi

if [ ! -x "$SRC" ]; then
  echo "Build it first: VHID_SRC=... ./build.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "$DEST")"
install -m 755 "$SRC" "$DEST"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${DEST}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/var/log/controller-vhid-bridge.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/controller-vhid-bridge.log</string>
</dict>
</plist>
PLISTEOF

chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootout system "$PLIST" 2>/dev/null || true
launchctl bootstrap system "$PLIST"

sleep 2
if pgrep -f "$DEST" >/dev/null; then
  echo "installed and running — log: /var/log/controller-vhid-bridge.log"
else
  echo "installed but not running; check /var/log/controller-vhid-bridge.log" >&2
fi
