/// Launches the redesigned neodesk UI on top of the real RustDesk engine, and
/// supplies the real remote-frame render widget to neodesk's FrameLayer.
///
/// main.dart (mobile) calls [setupNeodesk] before runApp and uses
/// [NeodeskEntry] as the home page instead of RustDesk's HomePage.
library;

import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart' show ConfigKeys;
import 'package:neodesk_core/ui/home/app_lock_gate.dart';
import 'package:neodesk_core/ui/home/home_shell.dart';
import 'package:neodesk_core/ui/session/canvas_override.dart';
import 'package:neodesk_core/ui/session/cursor_override.dart';
import 'package:neodesk_core/ui/session/frame_override.dart';
import 'package:neodesk_core/ui/theme/app_colors.dart';
import 'package:neodesk_core/ui/theme/app_theme.dart';

import '../common.dart' show gFFI, MyTheme;
import '../consts.dart' show kCommConfKeyLang;
import '../models/model.dart' show preDefaultCursor;
import '../models/platform_model.dart' show bind;
import 'adapter.dart';
import '../utils/image.dart' show ImagePainter;

/// Single composition root over the real engine (mobile = one global session).
final RustdeskCore neodeskCore = RustdeskCore();

/// The Spotify-style dark theme used for the whole mobile app, so engine-spawned
/// Material surfaces (dialogs, toasts, bottom sheets) match the neodesk UI
/// instead of leaking RustDesk's light/system theme. See main.dart.
///
/// It is RustDesk's [MyTheme.darkTheme] re-tinted with the Spotify palette
/// (green accent + #121212/#282828 surfaces), NOT neodesk's own
/// `AppTheme.dark()`. This is deliberate: RustDesk dialogs call
/// `MyTheme.color(context)`, which does a non-null assertion on the
/// `ColorThemeExtension`/`TabbarTheme` theme-extensions. `copyWith` (with no
/// `extensions:` arg) keeps those extensions present, so the engine dialogs
/// stay crash-free while picking up the new accent/surface colours. The
/// neodesk home itself is additionally wrapped in `AppTheme.dark()` below.
ThemeData neodeskAppTheme() {
  final base = MyTheme.darkTheme;
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bgBase,
    canvasColor: AppColors.bgBase,
    dialogBackgroundColor: AppColors.bgElevated2,
    cardColor: AppColors.bgElevated2,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.bgElevated2,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
    // Give every engine-spawned dialog (password prompt, errors, confirmations)
    // the app's rounded dark style instead of default Material corners/titles.
    dialogTheme: DialogTheme(
      backgroundColor: AppColors.bgElevated2,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 15,
        height: 1.35,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textOnAccent,
        disabledForegroundColor: AppColors.textDisabled,
        disabledBackgroundColor: AppColors.bgElevated2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
  );
}

/// Must be called once before runApp (after engine init).
void setupNeodesk() {
  // Engine dialog language (password prompt, connection info, errors). `system`
  // follows the phone; otherwise a RustDesk code like `en` / `zh-cn`. (The
  // neodesk UI itself stays English regardless.)
  final lang = neodeskCore.config.get(ConfigKeys.language, defaultValue: 'system');
  bind.mainSetLocalOption(
      key: kCommConfKeyLang, value: lang == 'system' ? '' : lang);
  neodeskFrameOverride = (context) => const RustdeskFrameWidget();
  neodeskCanvasOverride = _RustdeskCanvasControl();
  neodeskCursorOverride = _RustdeskCursorControl();
}

/// Drives the real remote cursor via RustDesk's `CursorModel`, which converts
/// coordinates, renders the cursor, edge-pans the canvas and sends the move to
/// the peer. (Direct `inputModel.moveMouse` would move the remote but never
/// update the on-screen cursor.)
class _RustdeskCursorControl implements NeodeskCursorControl {
  @override
  Future<bool> moveTo(double screenX, double screenY) =>
      gFFI.cursorModel.move(screenX, screenY);

  @override
  void moveBy(double screenDx, double screenDy) => gFFI.cursorModel
      .updatePan(Offset(screenDx, screenDy), Offset.zero, false);

  @override
  Offset? get imagePosition =>
      Offset(gFFI.cursorModel.x, gFFI.cursorModel.y);
}

/// Drives the real remote canvas (pan / zoom) from neodesk's gesture layer and
/// exposes its live transform so the gesture layer can convert screen<->image
/// coordinates correctly. Backed by RustDesk's `CanvasModel`.
class _RustdeskCanvasControl implements NeodeskCanvasControl {
  @override
  double get scale => gFFI.canvasModel.scale;

  @override
  double get offsetX => gFFI.canvasModel.x;

  @override
  double get offsetY => gFFI.canvasModel.y;

  @override
  double get imageWidth => gFFI.canvasModel.getDisplayWidth().toDouble();

  @override
  double get imageHeight => gFFI.canvasModel.getDisplayHeight().toDouble();

  @override
  void panBy(double dx, double dy) {
    gFFI.canvasModel.panX(dx);
    gFFI.canvasModel.panY(dy);
  }

  @override
  void zoomBy(double scaleRatio, Offset focal) {
    gFFI.canvasModel.updateScale(scaleRatio, focal);
  }

  @override
  void setTransform(double scale, double offsetX, double offsetY) {
    // CanvasModel.update(x, y, scale) sets the transform atomically and notifies.
    gFFI.canvasModel.update(offsetX, offsetY, scale);
  }

  @override
  void refit() {
    // Re-applies the chosen view style to the current window size (reads the new
    // orientation via MediaQueryData.fromView). Fire-and-forget.
    gFFI.canvasModel.updateViewStyle();
  }
}

/// Home widget: neodesk's HomeShell themed with the Spotify-style dark theme.
class NeodeskEntry extends StatelessWidget {
  const NeodeskEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark(),
      child: AppLockGate(
        core: neodeskCore,
        child: HomeShell(core: neodeskCore),
      ),
    );
  }
}

/// Provider-free remote-frame painter bound directly to the global gFFI models
/// (mirrors mobile RustDesk's `ImagePaint`, but without the Provider ancestors
/// since neodesk's tree doesn't supply them). Draws the remote image plus the
/// real remote cursor on top.
class RustdeskFrameWidget extends StatelessWidget {
  const RustdeskFrameWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final ffiModel = gFFI.ffiModel;
    final img = gFFI.imageModel;
    final canvas = gFFI.canvasModel;
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([img, canvas]),
            builder: (context, _) {
              var s = canvas.scale;
              if (ffiModel.isPeerLinux) {
                final displays = ffiModel.pi.getCurDisplays();
                if (displays.isNotEmpty) s = s / displays[0].scale;
              }
              final adjust = canvas.getAdjustY();
              return CustomPaint(
                painter: ImagePainter(
                  image: img.image,
                  x: canvas.x / s,
                  y: (canvas.y + adjust) / s,
                  scale: s,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
          const _RemoteCursorPaint(),
        ],
      ),
    );
  }
}

/// Draws the real remote cursor (shape + position streamed from the peer),
/// transformed by the canvas. Provider-free port of RustDesk's `CursorPaint`.
/// Visible because neodesk keeps relative-mouse mode OFF (see neodesk/adapter).
class _RemoteCursorPaint extends StatelessWidget {
  const _RemoteCursorPaint();

  @override
  Widget build(BuildContext context) {
    final m = gFFI.cursorModel;
    final c = gFFI.canvasModel;
    return ListenableBuilder(
      listenable: Listenable.merge([m, c]),
      builder: (context, _) {
        // Honour the user's "Hide remote cursor" setting (set per session by
        // SessionController). Cheap bool, not a per-frame FFI config lookup.
        if (!neodeskShowRemoteCursor) return const SizedBox.shrink();
        // Fall back to a default arrow until the peer streams its cursor shape.
        final hasImage = m.image != null;
        final image = m.image ?? preDefaultCursor.image;
        if (image == null) return const SizedBox.shrink();
        final hotx = hasImage ? m.hotx : image.width / 2;
        final hoty = hasImage ? m.hoty : image.height / 2;
        final s = c.scale;
        const minSize = 12.0;
        final mins =
            minSize / (image.width > image.height ? image.width : image.height);
        final factor = s < mins ? s / mins : 1.0;
        final s2 = s < mins ? mins : s;
        final adjust = c.getAdjustY();
        return CustomPaint(
          painter: ImagePainter(
            image: image,
            x: (m.x - hotx) * factor + c.x / s2,
            y: (m.y - hoty) * factor + (c.y + adjust) / s2,
            scale: s2,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
