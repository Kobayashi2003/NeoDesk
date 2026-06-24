/// neodesk_core — public surface of the core layer.
///
/// Import this single file to access every port, type and the composition root.
/// Only the engine-agnostic contracts are exported here; UI widgets live under
/// `lib/ui/` and are imported directly.
library neodesk_core;

// Value types
export 'core/types/ids.dart';
export 'core/types/enums.dart';
export 'core/types/peer_info.dart';
export 'core/types/display_info.dart';

// Ports (interfaces)
export 'core/ports/remote_session.dart';
export 'core/ports/frame_source.dart';
export 'core/ports/input_sink.dart';
export 'core/ports/config_store.dart';
export 'core/ports/peer_repository.dart';
export 'core/ports/file_transfer.dart';

// Config key registry
export 'core/config_keys.dart';

// App version
export 'core/version.dart';

// Composition root
export 'core/services/session_manager.dart';
