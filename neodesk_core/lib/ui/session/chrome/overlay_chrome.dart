import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/dimens.dart';
import '../../widgets/app_sheet.dart';
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
              // Quick monitor switcher — only when the peer has >1 display.
              if ((controller.peer?.displayCount ?? 1) > 1)
                _zoomButton(Icons.monitor, 'Display',
                    () => _displaySheet(context, controller.peer!.displayCount)),
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
        tooltip: tr(tooltip),
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
              Text(tr(label),
                  style: AppTypography.caption.copyWith(fontSize: 11)),
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
              // ---- Display (multi-monitor only) ----
              if (displays > 1)
                _actionTile(ctx, Icons.monitor, 'Display',
                    trailing: '${controller.currentDisplay + 1} / $displays',
                    onTap: () => _displaySheet(context, displays)),

              // ---- Video ----
              _sheetHeader('Video'),
              _actionTile(ctx, Icons.hd_outlined, 'Quality',
                  trailing: _qualityLabel(controller.imageQuality),
                  onTap: () => _qualityMenu(context)),
              _actionTile(ctx, Icons.video_settings_outlined, 'Codec',
                  onTap: () => _codec(context)),
              if (!isAndroid)
                _actionTile(ctx, Icons.aspect_ratio_outlined, 'Resolution',
                    onTap: () => _resolution(context)),

              // ---- Session toggles ----
              _sheetHeader('Session'),
              _toggleTile(ctx, 'Sync clipboard', controller.clipboardEnabled,
                  controller.toggleClipboard),
              _toggleTile(ctx, 'Play remote audio', controller.audioEnabled,
                  controller.toggleAudio),
              _toggleTile(ctx, 'View only (no input)', controller.viewOnly,
                  controller.toggleViewOnly),
              _toggleTile(ctx, 'Quality monitor', controller.qualityMonitorOn,
                  controller.toggleQualityMonitor),
              _toggleTile(ctx, 'Scroll strip', controller.scrollStripVisible,
                  controller.toggleScrollStrip),

              // ---- Remote actions (desktop targets only) ----
              // Clipboard syncs automatically (engine built-in) and Ctrl+Alt+Del
              // can be a shortcut combo, so neither needs a More entry.
              if (!isAndroid) ...[
                _sheetHeader('Remote'),
                _actionTile(ctx, Icons.lock_outline, 'Lock remote screen',
                    onTap: () => controller.lockScreen()),
              ],

              // ---- This device ----
              _sheetHeader('This device'),
              _actionTile(ctx, Icons.picture_in_picture_alt_outlined,
                  'Small window (PiP)',
                  subtitle: 'Keep streaming over other apps', onTap: () {
                controller.setChrome(false);
                controller.core.enterPictureInPicture();
              }),
              if (isAndroid) ...[
                _actionTile(ctx, Icons.arrow_back, 'Back',
                    pop: false,
                    onTap: () => controller.input
                        .androidAction(AndroidSystemAction.back)),
                _actionTile(ctx, Icons.home, 'Home',
                    pop: false,
                    onTap: () => controller.input
                        .androidAction(AndroidSystemAction.home)),
              ],

              const Divider(height: 1, color: AppColors.divider),
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

  /// A small accent section label inside the More sheet.
  Widget _sheetHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Dimens.s16, Dimens.s16, Dimens.s16, Dimens.s4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(tr(title).toUpperCase(),
              style: AppTypography.caption.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
        ),
      );

  /// A More-sheet row. Closes the sheet first (unless [pop] is false, e.g. the
  /// Android Back/Home keys, which should stay open for repeated presses).
  Widget _actionTile(BuildContext ctx, IconData icon, String title,
          {String? trailing,
          String? subtitle,
          bool pop = true,
          required VoidCallback onTap}) =>
      ListTile(
        leading: Icon(icon, color: AppColors.textSecondary),
        title: Text(tr(title)),
        subtitle: subtitle == null
            ? null
            : Text(tr(subtitle), style: AppTypography.caption),
        trailing: trailing == null
            ? null
            : Text(tr(trailing),
                style:
                    AppTypography.caption.copyWith(color: AppColors.accent)),
        onTap: () {
          if (pop) Navigator.pop(ctx);
          onTap();
        },
      );

  /// Short label for the current image-quality preset.
  String _qualityLabel(String q) => switch (q) {
        ImageQuality.best => 'Best',
        ImageQuality.low => 'Low',
        ImageQuality.custom => 'Custom',
        _ => 'Balanced',
      };

  /// Merged quality picker: the three presets plus Custom (which opens the
  /// image-quality / frame-rate sliders). Replaces the old separate
  /// "Image quality" + "Custom quality" entries. Pops itself *before* acting so
  /// the Custom sliders open as a fresh sheet (not popped by this one).
  void _qualityMenu(BuildContext context) {
    const items = {
      ImageQuality.best: 'Best (sharpest)',
      ImageQuality.balanced: 'Balanced',
      ImageQuality.low: 'Low (fastest)',
      ImageQuality.custom: 'Custom…',
    };
    showAppSheet(
      context,
      (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in items.entries)
            ListTile(
              leading: Icon(
                e.key == controller.imageQuality
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: e.key == controller.imageQuality
                    ? AppColors.accent
                    : AppColors.textSecondary,
              ),
              title: Text(tr(e.value), style: AppTypography.body),
              onTap: () {
                Navigator.pop(ctx);
                if (e.key == ImageQuality.custom) {
                  _customQuality(context);
                } else {
                  controller.setImageQuality(e.key);
                }
              },
            ),
          const SizedBox(height: Dimens.s8),
        ],
      ),
    );
  }

  /// Display switcher sheet (radio list of monitors).
  void _displaySheet(BuildContext context, int count) => _radioSheet(
        context,
        {for (var i = 0; i < count; i++) '$i': '${tr('Display')} ${i + 1}'},
        '${controller.currentDisplay}',
        (k) => controller.setDisplay(int.parse(k)),
      );

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
            ListTile(title: Text(tr(emptyHint), style: AppTypography.caption))
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
                title: Text(tr(e.value), style: AppTypography.body),
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
                Text(tr('Custom quality'), style: AppTypography.title),
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
              Text(tr(label), style: AppTypography.body),
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

  Widget _toggleTile(
          BuildContext ctx, String label, bool value, VoidCallback onToggle) =>
      ListTile(
        leading: Icon(value ? Icons.toggle_on : Icons.toggle_off,
            color: value ? AppColors.accent : AppColors.textSecondary),
        title: Text(tr(label)),
        onTap: () {
          onToggle();
          Navigator.pop(ctx);
        },
      );
}
