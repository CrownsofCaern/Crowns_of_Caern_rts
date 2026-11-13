#!/bin/bash
# Double-click to play Warbound on a Mac. Keep this file inside the repository (tools/mac/).
# Set GODOT if Godot 4.5 is not in /Applications.
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/../.." || exit 1
echo "Updating game files (the first start takes a few minutes)..."
"$GODOT" --headless --path . --import >/dev/null 2>&1
exec "$GODOT" --path . "$@"
