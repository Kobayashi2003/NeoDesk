import 'package:flutter/widgets.dart';

/// Set once at startup by the engine host to supply RustDesk's render widget.
/// When null, [FrameLayer] paints the demo placeholder.
typedef NeodeskFrameBuilder = Widget Function(BuildContext context);

NeodeskFrameBuilder? neodeskFrameOverride;
