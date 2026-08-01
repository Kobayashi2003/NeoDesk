# Build the NeoDesk Android APK. Runs analyze + unit tests first, then builds.
#
#   .\scripts\build.ps1 [debug|release] [-SkipTests]
#     Mode       debug (fast, ~75 MB) | release (R8-minified, ~25 MB; default)
#     -SkipTests build without running analyze/tests
#   Output: dist\neodesk-<version>.apk  (or neodesk-debug-<version>.apk)
#
# Requirements (read from your environment; missing ones fail fast):
#   * Flutter 3.24.5 on PATH, or $env:FLUTTER_HOME pointing at the Flutter SDK.
#   * A working Android toolchain (run `flutter doctor` if a build complains).
# Optional:
#   * $env:NEODESK_PROXY  - http proxy for network access (pub get / build).
#   * $env:DIST_DIR       - output dir (default: <repo>\dist).
param(
  [ValidateSet('debug', 'release')]
  [string]$Mode = 'release',
  [switch]$SkipTests,
  [switch]$SkipSync
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# --- rustdesk/ is generated, not vendored ------------------------------------
# It may be absent (fresh clone) or stale (overlay/patches edited since the last
# sync), so rebuild it unless explicitly told not to. See CLAUDE.md.
if (-not $SkipSync) {
  & (Join-Path $PSScriptRoot 'sync-rustdesk.ps1')
  if ($LASTEXITCODE -ne 0) { throw 'sync-rustdesk failed' }
}
elseif (-not (Test-Path (Join-Path $root 'rustdesk\pubspec.yaml'))) {
  throw '-SkipSync given but rustdesk/ does not exist. Run scripts\sync-rustdesk.ps1 first.'
}

# --- require flutter 3.24.5 --------------------------------------------------
# FLUTTER_HOME wins over PATH: a machine can easily have a newer Flutter first on
# PATH (e.g. a package-manager install), and this RustDesk vintage does not build
# with it - the failure is a wall of unrelated analyzer errors like
# "DialogTheme can't be assigned to DialogThemeData", which sends you hunting in
# the wrong place. So pin it here and verify.
$wantFlutter = '3.24.5'
if ($env:FLUTTER_HOME -and (Test-Path "$env:FLUTTER_HOME\bin\flutter.bat")) {
  $env:PATH = "$env:FLUTTER_HOME\bin;$env:PATH"
}
elseif (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "flutter not found. Set `$env:FLUTTER_HOME to a Flutter $wantFlutter SDK, or put it on PATH."
}
$flutterVer = (& flutter --version 2>&1 | Select-Object -First 1) -replace '^Flutter ([0-9.]+).*', '$1'
if ($flutterVer -ne $wantFlutter) {
  throw @"
wrong Flutter: found $flutterVer at $((Get-Command flutter).Source), need $wantFlutter.
Set `$env:FLUTTER_HOME to the $wantFlutter SDK (this machine: D:\Program\flutter_3245).
"@
}

# Proxy is needed for network steps (pub get / build); the Dart test harness
# breaks with it on, so it's turned off around analyze/test.
function Use-Proxy([bool]$on) {
  if ($on) {
    if ($env:NEODESK_PROXY) { $env:HTTP_PROXY = $env:NEODESK_PROXY; $env:HTTPS_PROXY = $env:NEODESK_PROXY }
  }
  else {
    Remove-Item env:HTTP_PROXY, env:HTTPS_PROXY -ErrorAction SilentlyContinue
  }
}

# --- dependencies ------------------------------------------------------------
Write-Host '==> Fetching dependencies' -ForegroundColor Cyan
Use-Proxy $true
Push-Location (Join-Path $root 'neodesk_core'); & flutter pub get | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'pub get failed (neodesk_core)' }; Pop-Location
Push-Location (Join-Path $root 'rustdesk');      & flutter pub get | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'pub get failed (rustdesk)' }; Pop-Location

# --- analyze + tests (skip with -SkipTests) ---------------------------------
if (-not $SkipTests) {
  Use-Proxy $false
  Write-Host '==> Analyzing neodesk_core (our UI + ports)' -ForegroundColor Cyan
  Push-Location (Join-Path $root 'neodesk_core'); & flutter analyze lib; $e1 = $LASTEXITCODE; Pop-Location
  Write-Host '==> Analyzing rustdesk adapter (lib\neodesk)' -ForegroundColor Cyan
  Push-Location (Join-Path $root 'rustdesk'); & flutter analyze lib\neodesk; $e2 = $LASTEXITCODE; Pop-Location
  Write-Host '==> Running neodesk_core unit tests' -ForegroundColor Cyan
  Push-Location (Join-Path $root 'neodesk_core'); & flutter test; $e3 = $LASTEXITCODE; Pop-Location
  if ($e1 -ne 0 -or $e2 -ne 0 -or $e3 -ne 0) {
    Write-Host 'FAIL Analyze/tests failed - not building.' -ForegroundColor Red
    exit 1
  }
  Write-Host ' ok  Analyze + tests passed.' -ForegroundColor Green
}

# --- build -------------------------------------------------------------------
$ver = 'unknown'
$verFile = Join-Path $root 'neodesk_core\lib\core\version.dart'
if ((Get-Content $verFile -Raw) -match "kNeodeskVersion\s*=\s*'([0-9][0-9.]*)'") { $ver = $matches[1] }
$dist = if ($env:DIST_DIR) { $env:DIST_DIR } else { Join-Path $root 'dist' }
New-Item -ItemType Directory -Force -Path $dist | Out-Null

Use-Proxy $true
Write-Host "==> Building $Mode APK (v$ver, android-arm64)" -ForegroundColor Cyan
Push-Location (Join-Path $root 'rustdesk')
try {
  & flutter build apk "--$Mode" --target-platform android-arm64
  if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }

  $src = "build\app\outputs\flutter-apk\app-$Mode.apk"
  if (-not (Test-Path $src)) { throw "expected output not found: $src" }

  $suffix = if ($Mode -eq 'debug') { '-debug' } else { '' }
  $out = Join-Path $dist "neodesk$suffix-$ver.apk"
  Copy-Item -Force $src $out

  $sz = '{0:N1} MB' -f ((Get-Item $out).Length / 1MB)
  Write-Host " ok  APK -> $out ($sz)" -ForegroundColor Green
}
finally { Pop-Location }
