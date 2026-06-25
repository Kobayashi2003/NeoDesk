<div align="center">

<img src="neodesk_core/assets/icon/neodesk_icon_1024.png" width="120" alt="NeoDesk icon">

# NeoDesk

**A RustDesk Android client with a UI redesigned to my taste.**

</div>

## About

NeoDesk is an Android remote-desktop client built on RustDesk's engine, with a
reworked user interface. It keeps RustDesk's speed and protocol and changes only
the client UI. I built it to have a client interface tailored to my own
preferences.

> Control end only (Android). The device being controlled still runs regular
> RustDesk / a RustDesk-compatible host.

## Download

Grab the latest `neodesk-debug-*.apk` from the
[Releases](https://github.com/Kobayashi2003/NeoDesk/releases) page and install it
on an arm64 Android device.

## Build

Requires Flutter 3.24.5 on `PATH` (or `$env:FLUTTER_HOME` set). The prebuilt
engine (`librustdesk.so`) is vendored, so no Rust toolchain is needed.

```powershell
.\scripts\build.ps1               # analyze + test, then release build -> dist\neodesk-<version>.apk
.\scripts\build.ps1 debug         # debug build
.\scripts\build.ps1 -SkipTests    # skip tests, just build
```

Or build directly without the script:

```powershell
cd rustdesk
flutter build apk --release --target-platform android-arm64
```

Behind a proxy, set `$env:NEODESK_PROXY` (e.g. `http://127.0.0.1:7890`) before
running the script. See [`scripts/README.md`](scripts/README.md) for details.

## What I wrote vs. what's from RustDesk

**Mine:**

- `neodesk_core/` — the entire redesigned UI plus a clean port/interface layer
  (it even runs as a standalone demo with no engine).
- `rustdesk/lib/neodesk/` — the adapter + launcher that bind that UI to the
  engine.

**From RustDesk (vendored, used unchanged as the backend):** everything else
under `rustdesk/` — RustDesk's Flutter client (`models/`, `mobile/`,
`common.dart`, …), its assets, and the prebuilt native engine
`librustdesk.so` (RustDesk 1.4.7).

## Thanks

Built on [RustDesk](https://github.com/rustdesk/rustdesk) — huge thanks to the
RustDesk project, whose engine and client this is based on.
