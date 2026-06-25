import 'package:flutter/widgets.dart';

/// Injection point so a host app (e.g. the real RustDesk engine integration)
/// can supply the actual remote-frame widget in place of the demo placeholder.
///
/// When null, [FrameLayer] paints the fake desktop (FakeCore demo). The real
/// app sets this once at startup to a builder returning RustDesk's image/
/// texture render widget. See DESIGN.md (M4).
typedef NeodeskFrameBuilder = Widget Function(BuildContext context);

NeodeskFrameBuilder? neodeskFrameOverride;
