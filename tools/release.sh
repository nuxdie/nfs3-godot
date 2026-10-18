#!/bin/bash
# Exports the Linux, Windows and macOS builds (export_presets.cfg) and packs each into
# build/release/nfs-revival-<version>-<platform>.zip, with a short how-to-run note.
#   tools/release.sh 0.1.0
# Needs the Godot 4.7 export templates installed. No game data goes into the builds.
set -euo pipefail
cd "$(dirname "$0")/.."
ver=${1:?usage: tools/release.sh <version>}
godot=${GODOT:-./godot}
out=build/release
rm -rf build/linux build/windows build/macos "$out"
mkdir -p build/linux build/windows build/macos "$out"

"$godot" --headless --path . --export-release Linux build/linux/nfs-revival.x86_64
"$godot" --headless --path . --export-release Windows "build/windows/NFS Revival.exe"
"$godot" --headless --path . --export-release macOS "build/macos/NFS Revival.zip"

note() {  # $1: platform, $2: executable name
	cat <<EOF
NFS Revival $ver ($1)
https://github.com/nuxdie/nfs3-godot

This build holds no game data. Put a copy of your own game files next to $2
(or point the environment variables at them):

  nfs3_data/   Need for Speed III: Hot Pursuit    (the folder holding gamedata/)  NFS3_DATA
  nfs4_data/   Need for Speed: High Stakes        (its Data folder)               NFS4_DATA
  nfs5_data/   Need for Speed: Porsche Unleashed  (its GameData folder)           NFS5_DATA
  nfs6_data/   Need for Speed: Hot Pursuit 2      (the install folder)            NFS6_DATA
  gt2_data/    Gran Turismo 2                     (a folder holding the disc image) GT2_DATA

Any one is enough; with none the game runs on a generated circuit with stand-in cars.
On Windows the default install folders under C:\\Program Files (x86)\\Electronic Arts
are found by themselves.
EOF
}

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

d="$stage/nfs-revival-$ver-linux"
mkdir -p "$d"
cp build/linux/nfs-revival.x86_64 "$d/"
note "Linux x86_64" nfs-revival.x86_64 > "$d/README.txt"
(cd "$stage" && zip -qr9 - "$(basename "$d")") > "$out/nfs-revival-$ver-linux-x86_64.zip"

d="$stage/nfs-revival-$ver-windows"
mkdir -p "$d"
cp "build/windows/NFS Revival.exe" "$d/"
note "Windows x86_64" "NFS Revival.exe" | sed 's/$/\r/' > "$d/README.txt"
(cd "$stage" && zip -qr9 - "$(basename "$d")") > "$out/nfs-revival-$ver-windows-x86_64.zip"

d="$stage/nfs-revival-$ver-macos"
mkdir -p "$d"
(cd "$d" && unzip -q "$OLDPWD/build/macos/NFS Revival.zip")
note "macOS universal" "NFS Revival.app" > "$d/README.txt"
cat >> "$d/README.txt" <<'EOF'

The app is not notarized: the first time, right-click it and choose Open (or run
`xattr -dr com.apple.quarantine "NFS Revival.app"`).
EOF
(cd "$stage" && zip -qry9 - "$(basename "$d")") > "$out/nfs-revival-$ver-macos-universal.zip"

(cd "$out" && sha256sum *.zip > SHA256SUMS.txt)
ls -la "$out"
