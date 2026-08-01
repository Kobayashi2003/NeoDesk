<#
.SYNOPSIS
    Rebuild rustdesk/ from upstream + our overlay and patches.

.DESCRIPTION
    NeoDesk does not vendor RustDesk's source. This script recreates the
    buildable rustdesk/ tree from three inputs, all pinned by rustdesk.lock.json:

      1. upstream RustDesk at a tag        (git, shallow)
      2. overlay/   - files we own outright, copied over the top
      3. patches/   - small edits to upstream files, applied with `git apply`

    plus two binaries that are neither source nor ours to write:

      4. lib/generated_bridge*.dart  - committed under overlay/ (irreplaceable,
                                       tiny, and NOT generatable without a Rust
                                       toolchain; see CLAUDE.md)
      5. librustdesk.so              - extracted from the official release APK,
                                       which never expires, unlike CI artifacts

    Everything it writes is disposable: rustdesk/ is gitignored. Re-run it any
    time; it always starts from a clean checkout.

.PARAMETER Tag
    Upstream tag to sync. Defaults to the pinned value in rustdesk.lock.json.
    Passing something else is how you START an engine upgrade — read CLAUDE.md
    first, because the bridge and the .so must move together.

.PARAMETER SkipEngine
    Reuse an already-downloaded librustdesk.so instead of re-fetching the APK.

.EXAMPLE
    .\scripts\sync-rustdesk.ps1
    .\scripts\sync-rustdesk.ps1 -Tag 1.5.0
#>
[CmdletBinding()]
param(
    [string]$Tag,
    [switch]$SkipEngine
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$Lock = Join-Path $Root 'rustdesk.lock.json'
$Work = Join-Path $Root 'rustdesk'
$Cache = Join-Path $Root '.cache'

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "    $m" -ForegroundColor DarkGray }
function Die($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $Lock)) { Die "missing $Lock" }
$lockData = Get-Content $Lock -Raw | ConvertFrom-Json
if (-not $Tag) { $Tag = $lockData.rustdesk.tag }

# The proxy is required here: the build machine reaches GitHub through it.
if ($env:NEODESK_PROXY) {
    $env:HTTP_PROXY = $env:NEODESK_PROXY
    $env:HTTPS_PROXY = $env:NEODESK_PROXY
}

Step "syncing rustdesk $Tag"

# --- 1. upstream ------------------------------------------------------------
$src = Join-Path $Cache "rustdesk-$Tag"
if (-not (Test-Path (Join-Path $src '.git'))) {
    Step "cloning upstream $Tag (flutter/ only)"
    New-Item -ItemType Directory -Force -Path $Cache | Out-Null
    Remove-Item -Recurse -Force $src -ErrorAction SilentlyContinue
    # blob:none + sparse keeps this to a few MB; the Rust source is not needed
    # because the engine ships prebuilt.
    git clone --depth 1 --branch $Tag --filter=blob:none --sparse `
        https://github.com/rustdesk/rustdesk.git $src 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "clone failed" }
    Push-Location $src
    git sparse-checkout set flutter 2>&1 | Out-Null
    Pop-Location
} else {
    Ok "using cached clone"
}
$upstream = Join-Path $src 'flutter'
if (-not (Test-Path $upstream)) { Die "no flutter/ in the upstream checkout" }

Step "laying down a clean tree"
Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
if (Test-Path $Work) {
    Die @"
could not clear $Work.

Something is holding a handle on it - usually a Gradle or Dart daemon from an
earlier build. Stop it and retry:
    taskkill /f /im java.exe /im dart.exe
"@
}
# Create the target first and copy the CONTENTS. Copy-Item's meaning flips on
# whether the destination exists (copy AS vs copy INTO), which silently nests
# the tree one level deep if the removal above ever half-succeeds.
New-Item -ItemType Directory -Force -Path $Work | Out-Null
Copy-Item -Recurse -Force (Join-Path $upstream '*') $Work
# Upstream's own README would end up inside our build dir; it is noise.
Remove-Item (Join-Path $Work 'README.md') -ErrorAction SilentlyContinue
Ok "$((Get-ChildItem -Recurse -File $Work | Measure-Object).Count) files from upstream"

# NeoDesk is an Android-only client, so upstream's other platform scaffolding is
# dead weight in the build tree. Dropping it keeps `rustdesk/` honest about what
# it is; the Android build never reads any of it. Note lib/desktop and lib/web
# STAY — vendored Dart still imports them, and deleting them breaks the build.
$prune = @('ios', 'linux', 'macos', 'windows', 'test') +
         (Get-ChildItem $Work -Filter '*.sh' -File | ForEach-Object { $_.Name })
foreach ($p in $prune) {
    Remove-Item -Recurse -Force (Join-Path $Work $p) -ErrorAction SilentlyContinue
}

# --- 2. patches (before overlay: they must apply to pristine upstream) -------
Step "applying patches"
$patchDir = Join-Path $Root 'patches'
foreach ($p in Get-ChildItem $patchDir -Filter *.patch | Sort-Object Name) {
    Push-Location $Work
    # rustdesk/ sits inside the NeoDesk repo but is not part of it, so git would
    # resolve the patch paths against the OUTER repo root and refuse. Detaching
    # it from any repository makes git treat the cwd as the patch root.
    $out = git -c core.excludesFile=NUL --git-dir=NUL --work-tree=. `
        apply --unsafe-paths --whitespace=nowarn $p.FullName 2>&1
    $failed = $LASTEXITCODE -ne 0
    Pop-Location
    if ($failed) {
        Die @"
patch '$($p.Name)' did not apply to rustdesk $Tag.
git said: $out

That is the intended failure: upstream changed a file we modify, so the change
needs a human (or Claude) to look at it. See CLAUDE.md -> "When upstream
changes". Do NOT delete the patch to make this go away.
"@
    }
    Ok $p.Name
}

# --- 3. overlay -------------------------------------------------------------
Step "copying overlay"
$overlay = Join-Path $Root 'overlay'
Get-ChildItem -Recurse -File $overlay | ForEach-Object {
    $rel = $_.FullName.Substring($overlay.Length + 1)
    $dst = Join-Path $Work $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item -Force $_.FullName $dst
}
Ok "$((Get-ChildItem -Recurse -File $overlay | Measure-Object).Count) files"

# --- 4. version -------------------------------------------------------------
# Single source of truth: neodesk_core/lib/core/version.dart. Injected rather
# than patched, because both sides change it every release and the patch would
# conflict forever.
Step "stamping version"
$verFile = Join-Path $Root 'neodesk_core/lib/core/version.dart'
$verMatch = Select-String -Path $verFile -Pattern "kNeodeskVersion = '([^']+)'"
if (-not $verMatch) { Die "cannot read kNeodeskVersion from $verFile" }
$version = $verMatch.Matches[0].Groups[1].Value
$build = $lockData.neodesk.buildNumber
$pubspec = Join-Path $Work 'pubspec.yaml'
(Get-Content $pubspec -Raw) -replace '(?m)^version: .*$', "version: $version+$build" |
    Set-Content -NoNewline $pubspec
Ok "$version+$build"

# --- 5. the native engine ---------------------------------------------------
$jni = Join-Path $Work 'android/app/src/main/jniLibs/arm64-v8a'
New-Item -ItemType Directory -Force -Path $jni | Out-Null
$soCache = Join-Path $Cache "librustdesk-$($lockData.engine.tag)-arm64.so"

if (-not (Test-Path $soCache)) {
    if ($SkipEngine) { Die "-SkipEngine given but no cached engine at $soCache" }
    Step "extracting librustdesk.so from the official $($lockData.engine.tag) APK"
    $apk = Join-Path $Cache "rustdesk-$($lockData.engine.tag).apk"
    if (-not (Test-Path $apk)) {
        Invoke-WebRequest -Uri $lockData.engine.apkUrl -OutFile $apk
    }
    # An APK is a zip; take only the arm64 engine (build.gradle ships arm64 only).
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'lib/arm64-v8a/librustdesk.so' }
        if (-not $entry) { Die "no lib/arm64-v8a/librustdesk.so inside $apk" }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $soCache, $true)
    } finally { $zip.Dispose() }
}
Copy-Item -Force $soCache (Join-Path $jni 'librustdesk.so')

# libc++_shared.so rides along in the same APK and is equally required.
$cxxCache = Join-Path $Cache "libc++_shared-$($lockData.engine.tag)-arm64.so"
if (-not (Test-Path $cxxCache)) {
    $apk = Join-Path $Cache "rustdesk-$($lockData.engine.tag).apk"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'lib/arm64-v8a/libc++_shared.so' }
        if ($entry) {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $cxxCache, $true)
        }
    } finally { $zip.Dispose() }
}
if (Test-Path $cxxCache) { Copy-Item -Force $cxxCache (Join-Path $jni 'libc++_shared.so') }
Ok "engine in place"

# --- 6. verify --------------------------------------------------------------
# The bridge and the engine are generated from the same Rust source and must
# agree. A bridge missing a symbol the engine exports is survivable; a call site
# for a symbol the engine LACKS crashes at runtime, so check that direction hard.
Step "verifying bridge against the engine"
$so = Join-Path $jni 'librustdesk.so'
$soHash = (Get-FileHash $so -Algorithm SHA256).Hash.ToLower()
if ($lockData.engine.sha256 -and $lockData.engine.sha256 -ne $soHash) {
    Die "librustdesk.so sha256 mismatch`n  expected $($lockData.engine.sha256)`n  got      $soHash"
}
Ok "engine sha256 ok"

$bridgeText = Get-Content (Join-Path $Work 'lib/generated_bridge.dart') -Raw
$bridgeFns = @([regex]::Matches($bridgeText, "'(wire_[a-z_0-9]+)'") |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)

# Symbol names live in the .so's string table; scan the bytes rather than
# needing nm/objdump on Windows. This is `strings | grep -x` semantics: cut the
# binary into runs of printable ASCII and keep the runs that are ENTIRELY a
# symbol name. Matching without that boundary also catches fragments of
# unrelated strings (wire_format, wire_pkt); requiring NUL on both sides is the
# opposite error and misses most of the table.
$bytes = [System.IO.File]::ReadAllBytes($so)
$ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
$soFns = [regex]::Split($ascii, '[^\x20-\x7E]+') |
    Where-Object { $_ -match '^wire_[a-z_0-9]+$' } | Sort-Object -Unique

# @() so a single result stays an array - PowerShell unrolls one-element
# pipelines to a scalar, and .Count then blows up.
$missing = @($soFns | Where-Object { $bridgeFns -notcontains $_ })
if ($missing.Count -gt 0) {
    Die "the engine exports symbols the bridge does not declare:`n  $($missing -join "`n  ")"
}
$extra = @($bridgeFns | Where-Object { $soFns -notcontains $_ })
if ($extra.Count -gt 0) {
    Write-Host "    NOTE: bridge declares $($extra.Count) symbol(s) the engine lacks:" -ForegroundColor Yellow
    $extra | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
    Write-Host "    Harmless only while nothing CALLS them - see CLAUDE.md." -ForegroundColor Yellow
}
Ok "$($bridgeFns.Count) bridge symbols, $($soFns.Count) engine symbols"

Write-Host ""
Write-Host "rustdesk/ is ready. Next: .\scripts\build.ps1" -ForegroundColor Green
