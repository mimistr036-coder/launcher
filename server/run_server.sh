#!/usr/bin/env bash
# Запуск выделенного сервера (ПК Linux/macOS или VDS)
# Порт: --port=7777 или переменная SRV_PORT. Godot: GODOT_BIN или в PATH.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
exec "$GODOT" --headless --path "$DIR/server" "$@"
