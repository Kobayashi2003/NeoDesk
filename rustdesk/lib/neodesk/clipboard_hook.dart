/// Notified by the engine when the peer pushes its clipboard (see
/// `models/model.dart`, the `clipboard` event). The neodesk adapter sets this so
/// it can capture the remote clipboard for an explicit "Copy remote clipboard"
/// action — on top of the engine's automatic `Clipboard.setData`.
library;

void Function(String text)? neodeskRemoteClipboardHook;
