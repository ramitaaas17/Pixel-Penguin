#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
godotBin="${GODOT_BIN:-godot}"
command -v "$godotBin" >/dev/null || { echo "Instala Godot y sus plantillas Web de la misma versión."; exit 1; }
mkdir -p frontend/game
touch frontend/game/.gdignore
"$godotBin" --headless --path . --editor --import
"$godotBin" --headless --path . --export-release Web frontend/game/index.html
