#!/usr/bin/env bash
# Builds the ready-to-open place file:
#   build/StealAPlanet.rbxl   (map already built, open it in Roblox Studio)
# Requirements: rojo (https://rojo.space) and lune (https://lune-org.github.io/docs)
# Optional: luau-lsp + Roblox definitions for type checking (set LUAU_LSP and ROBLOX_DEFS).
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build

if [[ -n "${LUAU_LSP:-}" && -n "${ROBLOX_DEFS:-}" ]]; then
	echo "==> Type checking (strict)"
	rojo sourcemap default.project.json --output build/sourcemap.json --include-non-scripts
	"$LUAU_LSP" analyze --platform=roblox --sourcemap=build/sourcemap.json \
		--definitions=@roblox="$ROBLOX_DEFS" src/
fi

echo "==> Logic tests"
lune run tests/run.luau
lune run tests/smoke.luau

echo "==> Building place with Rojo"
rojo build default.project.json -o build/StealAPlanet.unbaked.rbxlx

echo "==> Baking the map into the place"
lune run tools/bake-map.luau build/StealAPlanet.unbaked.rbxlx build/StealAPlanet.rbxl
rm -f build/StealAPlanet.unbaked.rbxlx build/sourcemap.json

echo "==> Done: build/StealAPlanet.rbxl"
