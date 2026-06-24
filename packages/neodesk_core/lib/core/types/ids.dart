/// Identifier value types shared across the core layer.
///
/// In RustDesk these come from the FFI bridge:
///   - `SessionID` is `UuidValue` on desktop and a fixed const on mobile
///     (see `flutter/lib/models/model.dart` -> `FFI(SessionID? sId)`).
/// We keep it opaque here so the adapter can map it without leaking the
/// `uuid` package into the new UX layer.
library;

/// Opaque per-connection session identifier.
///
/// Maps 1:1 to RustDesk's `SessionID` (UuidValue). The adapter is responsible
/// for the conversion; the rest of the app treats it as a black-box token.
typedef SessionId = String;

/// A peer device id (the numeric RustDesk ID a user types to connect).
typedef PeerId = String;
