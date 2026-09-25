#!/usr/bin/env bash
# Stop authserver and worldserver, rebuild RelWithDebInfo, refresh chaos.conf, then start both servers.
# Does not run cmake. Does not overwrite authserver.conf or worldserver.conf.

set -euo pipefail

export MSYS2_ARG_CONV_EXCL="*"
export MSYS_NO_PATHCONV=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/c/AzerothCore Build"
BIN_DIR="${BUILD_DIR}/bin/RelWithDebInfo"
CHAOS_DIST="${ROOT}/modules/chaos/conf/chaos.conf.dist"
CHAOS_CONF="${BIN_DIR}/configs/modules/chaos.conf"
VSWHERE="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"

if ! command -v cygpath >/dev/null 2>&1; then
  echo "Run this script from Git Bash on Windows." >&2
  exit 1
fi

echo "Stopping authserver and worldserver..."
taskkill /F /IM worldserver.exe >/dev/null 2>&1 || true
taskkill /F /IM authserver.exe >/dev/null 2>&1 || true

echo "Rebuilding RelWithDebInfo..."
if [[ ! -f "$VSWHERE" ]]; then
  echo "vswhere.exe not found: ${VSWHERE}" >&2
  exit 1
fi

MSBUILD=""
while IFS= read -r line; do
  line="${line//$'\r'/}"
  if [[ -n "$line" ]]; then
    MSBUILD="$line"
    break
  fi
done < <("$VSWHERE" -latest -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe')
if [[ -z "${MSBUILD}" ]]; then
  echo "MSBuild was not found." >&2
  exit 1
fi
MSBUILD="$(cygpath -u "$MSBUILD")"

"$MSBUILD" "$(cygpath -w "${BUILD_DIR}/AzerothCore.sln")" /m "/p:Configuration=RelWithDebInfo" /nologo

echo "Refreshing chaos.conf..."
if [[ ! -f "$CHAOS_DIST" ]]; then
  echo "Missing ${CHAOS_DIST}" >&2
  exit 1
fi
mkdir -p "$(dirname "$CHAOS_CONF")"
cp -f "$CHAOS_DIST" "$CHAOS_CONF"

echo "Starting authserver and worldserver..."
BIN_WIN="$(cygpath -w "$BIN_DIR")"
powershell.exe -NoProfile -Command "Start-Process -FilePath '${BIN_WIN}\\authserver.exe' -WorkingDirectory '${BIN_WIN}'"
powershell.exe -NoProfile -Command "Start-Process -FilePath '${BIN_WIN}\\worldserver.exe' -WorkingDirectory '${BIN_WIN}'"

echo "Servers started from ${BIN_DIR}."
