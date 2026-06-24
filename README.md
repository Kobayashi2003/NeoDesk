<div align="center">

<img src="assets/icon/neodesk_icon_1024.png" width="120" alt="NeoDesk icon">

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

Requires Flutter 3.24.5. The prebuilt engine (`librustdesk.so`) is vendored, so no
Rust toolchain is needed for a debug build:

```bash
cd apps/neodesk
flutter build apk --debug --target-platform android-arm64
```

## What I wrote vs. what's from RustDesk

**Mine:**

- `packages/neodesk_core/` — the entire redesigned UI plus a clean
  port/interface layer (it even runs as a standalone demo with no engine).
- `apps/neodesk/lib/neodesk/` — the adapter + launcher that bind that UI to the
  engine.

**From RustDesk (vendored, used unchanged as the backend):** everything else
under `apps/neodesk/` — RustDesk's Flutter client (`models/`, `mobile/`,
`common.dart`, …), its assets, and the prebuilt native engine
`librustdesk.so` (RustDesk 1.4.7).

## Thanks

Built on [RustDesk](https://github.com/rustdesk/rustdesk) — huge thanks to the
RustDesk project, whose engine and client this is based on.
