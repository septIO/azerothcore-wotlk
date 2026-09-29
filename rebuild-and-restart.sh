#!/usr/bin/env bash
# Stop authserver and worldserver, rebuild RelWithDebInfo, refresh chaos.conf, then start both servers.
# If Wow.exe is already running, close it and clear its Cache while the build runs, then start it again after worldserver.
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
WOW_EXE='C:\AZChromieCraft_3.3.5a\Wow.exe'

run_powershell() {
  local ps1 rc
  ps1="$(mktemp --suffix=.ps1)"
  cat > "$ps1"
  powershell.exe -NoProfile -File "$(cygpath -w "$ps1")" && rc=0 || rc=$?
  rm -f "$ps1"
  return "$rc"
}

wow_client_running() {
  run_powershell <<PS1
\$exe = '${WOW_EXE}'
\$match = @(Get-CimInstance Win32_Process -Filter "Name = 'Wow.exe'" |
  Where-Object { \$_.ExecutablePath -ieq \$exe })
if (\$match.Count -gt 0) { exit 0 }
exit 1
PS1
}

close_wow_client() {
  run_powershell <<'PS1'
$exe = 'C:\AZChromieCraft_3.3.5a\Wow.exe'
$cache = 'C:\AZChromieCraft_3.3.5a\Cache'

function Get-WowProcesses {
  @(Get-CimInstance Win32_Process -Filter "Name = 'Wow.exe'" |
    Where-Object { $_.ExecutablePath -ieq $exe })
}

foreach ($proc in (Get-WowProcesses)) {
  Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
}

$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
  if ((Get-WowProcesses).Count -eq 0) { break }
  Start-Sleep -Milliseconds 200
}

if ((Get-WowProcesses).Count -ne 0) {
  Write-Error "Wow.exe did not exit."
  exit 1
}

if (Test-Path -LiteralPath $cache) {
  Remove-Item -LiteralPath $cache -Recurse -Force
}
PS1
}

start_wow_client() {
  run_powershell <<'PS1'
Start-Process -FilePath 'C:\AZChromieCraft_3.3.5a\Wow.exe' -WorkingDirectory 'C:\AZChromieCraft_3.3.5a'
PS1
}

if ! command -v cygpath >/dev/null 2>&1; then
  echo "Run this script from Git Bash on Windows." >&2
  exit 1
fi

echo "Stopping authserver and worldserver..."
taskkill /F /IM worldserver.exe >/dev/null 2>&1 || true
taskkill /F /IM authserver.exe >/dev/null 2>&1 || true

WOW_WAS_RUNNING=0
if wow_client_running; then
  WOW_WAS_RUNNING=1
fi

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

"$MSBUILD" "$(cygpath -w "${BUILD_DIR}/AzerothCore.sln")" /m "/p:Configuration=RelWithDebInfo" /nologo &
build_pid=$!

wow_rc=0
if [[ "$WOW_WAS_RUNNING" -eq 1 ]]; then
  echo "Closing Wow.exe and clearing Cache..."
  close_wow_client || wow_rc=$?
fi

build_rc=0
wait "$build_pid" || build_rc=$?
if [[ "$build_rc" -ne 0 ]]; then
  echo "Build failed." >&2
  exit "$build_rc"
fi
if [[ "$wow_rc" -ne 0 ]]; then
  echo "Closing Wow.exe failed; it will not be started again." >&2
fi

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
if [[ "$WOW_WAS_RUNNING" -eq 1 && "$wow_rc" -eq 0 ]]; then
  echo "Starting Wow.exe..."
  start_wow_client || echo "Wow.exe failed to start." >&2
fi
