import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/dimens.dart';
import '../../widgets/app_sheet.dart';
import '../gestures/gesture_help.dart';
import '../gestures/interaction_ui_mode.dart';
import '../session_controller.dart';

/// Top status bar + bottom toolbar, auto-hidden via [SessionController]. Both
/// bars are SafeArea-insetted (correct under portrait/landscape cutouts) and the
/// bottom cluster is centred within a max width. See DESIGN.md §4.5.
class OverlayChrome extends StatelessWidget {
  const OverlayChrome({
    super.key,
    required this.controller,
    required this.peerName,
    required this.onClose,
  });

  final SessionController controller;
  final String peerName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final visible = controller.chromeVisible;
        const dur = Duration(milliseconds: 200);
        return IgnorePointer(
          ignoring: !visible,
          child: Stack(
            children: [
              // Top bar slides up off-screen when collapsed; bottom bar slides
              // down — a clear collapse/expand that reads well in any orientation.
              Align(
                alignment: Alignment.topCenter,
                child: AnimatedSlide(
                  duration: dur,
                  curve: Curves.easeOut,
                  offset: visible ? Offset.zero : const Offset(0, -1),
                  child: AnimatedOpacity(
                    duration: dur,
                    opacity: visible ? 1 : 0,
                    child: _topBar(context),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSlide(
                  duration: dur,
                  curve: Curves.easeOut,
                  offset: visible ? Offset.zero : const Offset(0, 1),
                  child: AnimatedOpacity(
                    duration: dur,
                    opacity: visible ? 1 : 0,
                    child: _bottomBar(context),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // The bar background bleeds under the system bars / cutouts; SafeArea insets
  // only the content, so it stays correct in portrait *and* landscape (where the
  // notch and gesture insets move to the sides).
  Widget _topBar(BuildContext context) => Container(
        decoration: const BoxDecoration(color: OverlayColors.barBg),
        child: SafeArea(
          bottom: false,
          minimum: const EdgeInsets.fromLTRB(
              Dimens.s8, Dimens.s4, Dimens.s8, Dimens.s8),
          child: Row(
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left), onPressed: onClose),
              Expanded(
                child: Text(peerName,
                    style: AppTypography.body, overflow: TextOverflow.ellipsis),
              ),
              _zoomButton(Icons.fit_screen, 'Fit', controller.fitCanvas),
              _zoomButton(
                  Icons.center_focus_strong, '1:1', controller.nativeCanvas),
              // Explicitly collapse the toolbar (the floating handle re-shows it).
              _zoomButton(Icons.keyboard_arrow_up, 'Hide toolbar',
                  () => controller.setChrome(false)),
              const SizedBox(width: Dimens.s4),
              _modeChip(context),
            ],
          ),
        ),
      );

  /// Quick zoom controls (§4): a single tap can't toggle zoom (it's a click),
  /// so Fit / 100% are exposed as toolbar buttons.
  Widget _zoomButton(IconData icon, String tooltip, VoidCallback onTap) =>
      IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        color: AppColors.textSecondary,
        onPressed: onTap,
      );

  Widget _modeChip(BuildContext context) => GestureDetector(
        onTap: () => _pickMode(context),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Dimens.s12, vertical: Dimens.s4),
          decoration: BoxDecoration(
            color: AppColors.accentMuted,
            borderRadius: BorderRadius.circular(Dimens.rChip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune, size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(controller.mode.label,
                  style:
                      AppTypography.caption.copyWith(color: AppColors.accent)),
            ],
          ),
        ),
      );

  Widget _bottomBar(BuildContext context) => Container(
        decoration: const BoxDecoration(color: OverlayColors.barBg),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.symmetric(horizontal: Dimens.s8),
          child: SizedBox(
            height: Dimens.bottomBarHeight,
            // Centre the cluster within a max width so it reads as a compact tool
            // group instead of stretching edge-to-edge on a wide landscape screen.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _tool(Icons.keyboard, 'Keyboard', controller.toggleKeyboard),
                    _tool(Icons.functions, 'Fn keys',
                        controller.toggleSpecialKeyboard),
                    _tool(Icons.bolt, 'Combos',
                        controller.toggleCombosKeyboard),
                    _tool(Icons.more_horiz, 'More', () => _more(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _tool(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Dimens.rChip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Dimens.s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: AppColors.textPrimary),
              const SizedBox(height: 2),
              Text(label, style: AppTypography.caption.copyWith(fontSize: 11)),
            ],
          ),
        ),
      );

  void _pickMode(BuildContext context) {
    showAppSheet(
      context,
      (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: InteractionUiMode.values
            .map((m) => ListTile(
                  leading: Icon(
                    m == controller.mode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: m == controller.mode
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                  title: Text(m.label, style: AppTypography.body),
                  subtitle: Text(m.description, style: AppTypography.caption),
                  onTap: () {
                    controller.setMode(m);
                    Navigator.pop(ctx);
                  },
                ))
            .toList(),
      ),
    );
  }

  void _more(BuildContext context) {
    final isAndroid = controller.peer?.isAndroid ?? false;
    final displays = controller.peer?.displayCount ?? 1;
    final opacity =
        (double.tryParse(controller.core.config.get(ConfigKeys.panelOpacity)) ??
                0.9)
            .clamp(0.4, 1.0);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // scroll instead of overflowing in landscape
      backgroundColor: const Color(0xFF181818).withOpacity(opacity),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            if (displays > 1) _displayPicker(ctx, displays),
            ListTile(
              leading: const Icon(Icons.hd_outlined,
                  color: AppColors.textSecondary),
              title: const Text('Image quality'),
              trailing: Text(controller.imageQuality,
                  style: AppTypography.caption
                      .copyWith(color: AppColors.accent)),
              onTap: () {
                Navigator.pop(ctx);
                _quality(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune, color: AppColors.textSecondary),
              title: const Text('Custom quality'),
              onTap: () {
                Navigator.pop(ctx);
                _customQuality(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_settings_outlined,
                  color: AppColors.textSecondary),
              title: const Text('Codec'),
              onTap: () {
                Navigator.pop(ctx);
                _codec(context);
              },
            ),
            if (!isAndroid)
              ListTile(
                leading: const Icon(Icons.aspect_ratio_outlined,
                    color: AppColors.textSecondary),
                title: const Text('Resolution'),
                onTap: () {
                  Navigator.pop(ctx);
                  _resolution(context);
                },
              ),
            _toggleTile(ctx, 'Scroll strip', controller.scrollStripVisible,
                controller.toggleScrollStrip),
            _toggleTile(ctx, 'Sync clipboard', controller.clipboardEnabled,
                controller.toggleClipboard),
            _toggleTile(ctx, 'Play remote audio', controller.audioEnabled,
                controller.toggleAudio),
            _toggleTile(ctx, 'View only (no input)', controller.viewOnly,
                controller.toggleViewOnly),
            _toggleTile(ctx, 'Quality monitor', controller.qualityMonitorOn,
                controller.toggleQualityMonitor),
            ListTile(
              leading: const Icon(Icons.picture_in_picture_alt_outlined,
                  color: AppColors.textSecondary),
              title: const Text('Small window (PiP)'),
              subtitle: const Text('Keep streaming over other apps',
                  style: AppTypography.caption),
              onTap: () {
                Navigator.pop(ctx);
                controller.setChrome(false);
                controller.core.enterPictureInPicture();
              },
            ),
            // Remote-control actions (desktop targets only).
            if (!isAndroid) ...[
              ListTile(
                leading: const Icon(Icons.keyboard,
                    color: AppColors.textSecondary),
                title: const Text('Ctrl + Alt + Del'),
                onTap: () {
                  Navigator.pop(ctx);
                  controller.ctrlAltDel();
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline,
                    color: AppColors.textSecondary),
                title: const Text('Lock remote screen'),
                onTap: () {
                  Navigator.pop(ctx);
                  controller.lockScreen();
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.gesture),
              title: const Text('Gesture help'),
              onTap: () {
                Navigator.pop(ctx);
                showGestureHelp(context, controller.mode);
              },
            ),
            if (isAndroid) ...[
              ListTile(
                  leading: const Icon(Icons.arrow_back),
                  title: const Text('Back'),
                  onTap: () =>
                      controller.input.androidAction(AndroidSystemAction.back)),
              ListTile(
                  leading: const Icon(Icons.home),
                  title: const Text('Home'),
                  onTap: () =>
                      controller.input.androidAction(AndroidSystemAction.home)),
            ],
            ListTile(
              leading: const Icon(Icons.link_off, color: AppColors.danger),
              title: const Text('Disconnect',
                  style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(ctx);
                onClose();
              },
            ),
          ],
          ),
        ),
      ),
    );
  }

  /// Radio-style picker sheet: highlights [selected] of [items] (value→label).
  void _radioSheet(BuildContext context, Map<String, String> items,
      String selected, ValueChanged<String> onPick,
      {String? emptyHint}) {
    showAppSheet(
      context,
      (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (items.isEmpty && emptyHint != null)
            ListTile(title: Text(emptyHint, style: AppTypography.caption))
          else
            for (final e in items.entries)
              ListTile(
                leading: Icon(
                  e.key == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: e.key == selected
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
                title: Text(e.value, style: AppTypography.body),
                onTap: () {
                  onPick(e.key);
                  Navigator.pop(ctx);
                },
              ),
          const SizedBox(height: Dimens.s8),
        ],
      ),
    );
  }

  Future<void> _codec(BuildContext context) async {
    final info = await controller.codecInfo();
    if (!context.mounted) return;
    _radioSheet(
      context,
      {for (final c in info.available) c: c == 'auto' ? 'Auto' : c.toUpperCase()},
      info.current,
      (c) => controller.setCodec(c),
    );
  }

  Future<void> _resolution(BuildContext context) async {
    final info = await controller.resolutionInfo();
    if (!context.mounted) return;
    final cur = '${info.width}x${info.height}';
    _radioSheet(
      context,
      {for (final o in info.options) '${o.w}x${o.h}': '${o.w} × ${o.h}'},
      cur,
      (key) {
        final p = key.split('x');
        controller.changeResolution(int.parse(p[0]), int.parse(p[1]));
      },
      emptyHint: 'No alternate resolutions reported',
    );
  }

  Future<void> _customQuality(BuildContext context) async {
    var q = (await controller.getCustomQuality()).toDouble().clamp(10.0, 100.0);
    var fps = 30.0;
    if (!context.mounted) return;
    showAppSheet(
      context,
      (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => Padding(
            padding: const EdgeInsets.all(Dimens.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Custom quality', style: AppTypography.title),
                _sliderRow('Image quality', '${q.round()}%', q, 10, 100,
                    (v) => setSt(() => q = v),
                    (v) => controller.setCustomQuality(v.round())),
                _sliderRow('Frame rate', '${fps.round()} fps', fps, 5, 120,
                    (v) => setSt(() => fps = v),
                    (v) => controller.setCustomFps(v.round())),
                const SizedBox(height: Dimens.s8),
              ],
            ),
          ),
        ),
    );
  }

  Widget _sliderRow(String label, String value, double v, double min, double max,
          ValueChanged<double> onChanged, ValueChanged<double> onEnd) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Dimens.s12),
            child: Row(children: [
              Text(label, style: AppTypography.body),
              const Spacer(),
              Text(value, style: AppTypography.caption),
            ]),
          ),
          Slider(
            value: v.clamp(min, max),
            min: min,
            max: max,
            activeColor: AppColors.accent,
            onChanged: onChanged,
            onChangeEnd: onEnd,
          ),
        ],
      );

  void _quality(BuildContext context) => _radioSheet(
        context,
        const {
          ImageQuality.best: 'Best (sharpest)',
          ImageQuality.balanced: 'Balanced',
          ImageQuality.low: 'Low (fastest)',
        },
        controller.imageQuality,
        controller.setImageQuality,
      );

  Widget _toggleTile(
          BuildContext ctx, String label, bool value, VoidCallback onToggle) =>
      ListTile(
        leading: Icon(value ? Icons.toggle_on : Icons.toggle_off,
            color: value ? AppColors.accent : AppColors.textSecondary),
        title: Text(label),
        onTap: () {
          onToggle();
          Navigator.pop(ctx);
        },
      );

  Widget _displayPicker(BuildContext ctx, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Dimens.s16, Dimens.s12, Dimens.s16, Dimens.s4),
        child: Row(
          children: [
            const Icon(Icons.monitor, color: AppColors.textSecondary),
            const SizedBox(width: Dimens.s12),
            const Text('Display', style: AppTypography.body),
            const SizedBox(width: Dimens.s16),
            ...List.generate(count, (i) {
              final active = controller.currentDisplay == i;
              return Padding(
                padding: const EdgeInsets.only(right: Dimens.s8),
                child: GestureDetector(
                  onTap: () {
                    controller.setDisplay(i);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Dimens.s12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? AppColors.accent : AppColors.bgElevated2,
                      borderRadius: BorderRadius.circular(Dimens.rChip),
                    ),
                    child: Text('${i + 1}',
                        style: AppTypography.caption.copyWith(
                          color: active
                              ? AppColors.textOnAccent
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ),
              );
            }),
          ],
        ),
      );
}
