#!/usr/bin/env bash
# Builds the desktop release archives (Windows, macOS, Linux) into an output
# folder, each with the game's licence, credits, the font licences and the
# Godot Engine's third-party notices beside the game files.
#
#   tools/release/package.sh <version label> [output dir]   (default: build/release)
#
# Needs Godot 4.5.1 on PATH (or $GODOT) with the matching export templates.
set -euo pipefail
GODOT="${GODOT:-godot}"
label="${1:?usage: package.sh <version label> [output dir]}"
cd "$(dirname "$0")/../.."

for f in LICENSE CREDITS.md; do
	[[ -f "$f" ]] || { echo "$f is missing; every build must ship it" >&2; exit 1; }
done

out="$(mkdir -p "${2:-build/release}" && cd "${2:-build/release}" && pwd)"
stage="$out/stage"
rm -rf "$stage" "$out"/*.zip "$out"/*.tar.gz "$out"/SHA256SUMS.txt
mkdir -p "$stage"
name="CrownsOfCaernWarbound-$label"

"$GODOT" --headless --path . --import >/dev/null 2>&1 || "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --script res://tools/release/write_notices.gd -- "$stage/THIRD_PARTY_NOTICES.txt"
grep -q "Godot Engine contributors" "$stage/THIRD_PARTY_NOTICES.txt"

add_notices() {
	cp LICENSE CREDITS.md "$stage/THIRD_PARTY_NOTICES.txt" "$1/"
	cp tools/release/README-player.txt "$1/README.txt"
	mkdir -p "$1/licenses"
	cp assets/fonts/*-OFL.txt "$1/licenses/"
}

export_preset() { # preset, target file
	echo "== Exporting $1"
	mkdir -p "$(dirname "$2")"
	"$GODOT" --headless --path . --export-release "$1" "$2" 2>&1 | tee "$stage/export-$1.log"
	if [[ ! -s "$2" ]] || grep -qE "ERROR: .*([Ee]xport|template)" "$stage/export-$1.log"; then
		echo "Export of $1 failed" >&2
		exit 1
	fi
}

# Windows (the game data is embedded in the .exe)
dir="$stage/$name-windows-x86_64"
export_preset "Windows Desktop" "$dir/CrownsOfCaernWarbound.exe"
rm -f "$dir"/*.console.exe
add_notices "$dir"
(cd "$stage" && zip -qr "$out/$name-windows-x86_64.zip" "$name-windows-x86_64")

# macOS: Godot writes a zip holding the ad-hoc signed .app; the notices go
# beside the app, not inside it, so the signature stays valid.
dir="$stage/$name-macos"
export_preset "macOS" "$stage/macos-export.zip"
mkdir -p "$dir"
(cd "$dir" && unzip -q "$stage/macos-export.zip")
add_notices "$dir"
(cd "$stage" && zip -qry "$out/$name-macos-universal.zip" "$name-macos")

# Linux (the game data is embedded in the binary)
dir="$stage/$name-linux-x86_64"
export_preset "Linux" "$dir/CrownsOfCaernWarbound.x86_64"
chmod +x "$dir/CrownsOfCaernWarbound.x86_64"
add_notices "$dir"
tar -C "$stage" -czf "$out/$name-linux-x86_64.tar.gz" "$name-linux-x86_64"

cd "$out"
if command -v sha256sum >/dev/null; then sum="sha256sum"; else sum="shasum -a 256"; fi
$sum ./*.zip ./*.tar.gz | sed 's| \./| |' > SHA256SUMS.txt
cat SHA256SUMS.txt
ls -lh "$out"
