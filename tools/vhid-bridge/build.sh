#!/bin/bash
# Build controller-vhid-bridge against the Karabiner-DriverKit-VirtualHIDDevice headers.
# Usage: VHID_SRC=/path/to/Karabiner-DriverKit-VirtualHIDDevice ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

VHID_SRC="${VHID_SRC:-}"
if [ -z "$VHID_SRC" ] || [ ! -d "$VHID_SRC/include" ]; then
  echo "Set VHID_SRC to a checkout of pqrs-org/Karabiner-DriverKit-VirtualHIDDevice" >&2
  exit 1
fi

clang++ -std=c++2b -O2 \
  -isystem "$VHID_SRC/include" \
  -isystem "$VHID_SRC/vendor/vendor/include" \
  main.cpp -o controller-vhid-bridge

echo "built: $(pwd)/controller-vhid-bridge"
