import 'package:flutter/material.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../session/gestures/gesture_settings_page.dart';
import '../session/gestures/gesture_tuning_page.dart';
import '../session/gestures/interaction_ui_mode.dart';
import '../session/keyboard/combo_settings_page.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/dimens.dart';
import '../widgets/app_sheet.dart';

/// A selectable preset: the [value] persisted to [ConfigStore] and the [label]
/// shown to the user (plus an optional one-line [sub]title).
typedef _Option = ({String label, String value, String? sub});

/// "Settings" tab. Every control here is read back by a live session
/// ([SessionController] / [RemoteSessionPage]) — choices persist to
/// [ConfigStore] under a [ConfigKeys] key and apply to the next session opened.
/// See DESIGN.md §4.3.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.core});

  final NeodeskCore core;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ConfigStore get _cfg => widget.core.config;

  // Preset tables (the slider-driven pointer/scroll speeds are stored as raw
  // numbers; these remain pickers).
  static const _maxZooms = <_Option>[
    (label: '2×', value: '2.0', sub: null),
    (label: '3×', value: '3.0', sub: null),
    (label: '4×', value: '4.0', sub: null),
  ];
  static const _edgePans = <_Option>[
    (label: 'Slow', value: 'slow', sub: null),
    (label: 'Medium', value: 'medium', sub: null),
    (label: 'Fast', value: 'fast', sub: null),
  ];
  static const _keySizes = <_Option>[
    (label: 'Small', value: 'small', sub: null),
    (label: 'Medium', value: 'medium', sub: null),
    (label: 'Large', value: 'large', sub: null),
  ];
  // In-session quality-monitor overlay verbosity.
  static const _qualityDetails = <_Option>[
    (label: 'Simple', value: 'simple', sub: 'FPS and delay'),
    (
      label: 'Detailed',
      value: 'detailed',
      sub: 'FPS, delay, bitrate, speed, codec'
    ),
  ];
  // neodesk UI theme (engine dialogs keep the app-wide theme).
  static const _themes = <_Option>[
    (label: 'Follow system', value: 'system', sub: null),
    (label: 'Light', value: 'light', sub: null),
    (label: 'Dark', value: 'dark', sub: null),
  ];
  // Engine dialog language (the neodesk UI itself stays English).
  static const _languages = <_Option>[
    (label: 'Follow system', value: 'system', sub: null),
    (label: 'English', value: 'en', sub: null),
    (label: '中文', value: 'zh-cn', sub: null),
    (label: '日本語', value: 'ja', sub: null),
  ];
  // Per-volume-key actions. A quick press taps; holding holds (scroll repeats).
  static const _volumeActions = <_Option>[
    (label: 'System volume', value: 'off', sub: 'Default — changes volume'),
    (label: 'Scroll up', value: 'scrollUp', sub: 'Hold to keep scrolling'),
    (label: 'Scroll down', value: 'scrollDown', sub: 'Hold to keep scrolling'),
    (label: 'Left click', value: 'left', sub: 'Hold to drag'),
    (label: 'Right click', value: 'right', sub: null),
    (label: 'Ctrl', value: 'ctrl', sub: 'Hold to hold Ctrl'),
    (label: 'Shift', value: 'shift', sub: 'Hold to hold Shift'),
    (label: 'Alt', value: 'alt', sub: 'Hold to hold Alt'),
    (label: 'Win', value: 'meta', sub: 'Hold to hold Win'),
    (label: 'Esc', value: 'VK_ESCAPE', sub: null),
    (label: 'Enter', value: 'VK_ENTER', sub: null),
    (label: 'Tab', value: 'VK_TAB', sub: null),
    (label: 'Page Up', value: 'VK_PRIOR', sub: null),
    (label: 'Page Down', value: 'VK_NEXT', sub: null),
    (label: 'Arrow Up', value: 'VK_UP', sub: null),
    (label: 'Arrow Down', value: 'VK_DOWN', sub: null),
  ];

  // Slider bounds.
  static const _gainMin = 0.6, _gainMax = 3.0;
  static const _stepMin = 10.0, _stepMax = 48.0; // px per wheel notch

  late InteractionUiMode _mode;
  late double _pointerGain; // pointer.gainBase
  late double _scrollStep; // scroll.step (smaller = faster)
  late String _maxZoom;
  late String _edgePan;
  late bool _scrollInvert;
  late bool _hideCursor;
  late double _panelOpacity; // panel.opacity
  late String _keySize;
  late bool _keyCompact;
  late bool _keyWide;
  late String _volumeUp;
  late String _volumeDown;
  late String _language;
  late String _theme;
  late bool _appLock;
  late bool _autoPip;
  late bool _confirmDisconnect;
  late String _qualityDetail;

  /// Which slider row is currently expanded (accordion; null = all collapsed).
  /// Sliders are hidden behind a tap so the list stays compact.
  String? _openSlider;

  @override
  void initState() {
    super.initState();
    _mode = InteractionUiModeX.fromStorage(_cfg.get(ConfigKeys.defaultMode,
        defaultValue: InteractionUiModeX.defaultMode.storageKey));
    _pointerGain =
        (double.tryParse(_cfg.get(ConfigKeys.pointerGainBase)) ?? 1.4)
            .clamp(_gainMin, _gainMax);
    _scrollStep = (double.tryParse(_cfg.get(ConfigKeys.scrollStep)) ?? 24)
        .clamp(_stepMin, _stepMax);
    _maxZoom = _cfg.get(ConfigKeys.zoomMax, defaultValue: '3.0');
    _edgePan = _cfg.get(ConfigKeys.edgePanSpeed, defaultValue: 'medium');
    _scrollInvert = _cfg.getBool(ConfigKeys.scrollInvert);
    _hideCursor =
        _cfg.getBool(ConfigKeys.hideCursorInTouch, defaultValue: true);
    _panelOpacity = (double.tryParse(_cfg.get(ConfigKeys.panelOpacity)) ?? 0.9)
        .clamp(_opacityMin, _opacityMax);
    _keySize = _cfg.get(ConfigKeys.keySize, defaultValue: 'medium');
    _keyCompact = _cfg.getBool(ConfigKeys.keyCompact);
    _keyWide = _cfg.getBool(ConfigKeys.keyWide);
    _volumeUp = _cfg.get(ConfigKeys.volumeUp, defaultValue: 'off');
    _volumeDown = _cfg.get(ConfigKeys.volumeDown, defaultValue: 'off');
    _language = _cfg.get(ConfigKeys.language, defaultValue: 'system');
    _theme = _cfg.get(ConfigKeys.theme, defaultValue: 'dark');
    _appLock = _cfg.getBool(ConfigKeys.appLock);
    _autoPip = _cfg.getBool(ConfigKeys.autoPip);
    _confirmDisconnect =
        _cfg.getBool(ConfigKeys.confirmDisconnect, defaultValue: true);
    _qualityDetail =
        _cfg.get(ConfigKeys.qualityMonitorDetail, defaultValue: 'simple');
    // Show the real installed version (Android's versionName), not the
    // compile-time constant, which can drift from the built APK.
    _version = kNeodeskVersion;
    widget.core.appVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  late String _version;

  static const _opacityMin = 0.55, _opacityMax = 1.0;

  String _labelOf(List<_Option> opts, String value) =>
      opts.firstWhere((o) => o.value == value, orElse: () => opts.first).label;

  void _pickMode() => _pick<InteractionUiMode>(
        title: 'Default mode',
        items: {for (final m in InteractionUiMode.values) m.label: m},
        current: _mode.label,
        subtitleOf: (m) => m.description,
        onPick: (m) {
          setState(() => _mode = m);
          _cfg.set(ConfigKeys.defaultMode, m.storageKey);
        },
      );

  /// Generic preset chooser: persists [option].value under [key].
  void _pickOption(String title, List<_Option> options, String key,
          String current, ValueChanged<String> apply) =>
      _pick<String>(
        title: title,
        items: {for (final o in options) o.label: o.value},
        current: _labelOf(options, current),
        subtitleOf: (v) =>
            options.firstWhere((o) => o.value == v).sub ?? '',
        onPick: (v) {
          apply(v);
          _cfg.set(key, v);
        },
      );

  void _pick<T>({
    required String title,
    required Map<String, T> items,
    required String current,
    required void Function(T) onPick,
    String Function(T)? subtitleOf,
  }) {
    showAppSheet(
      context,
      (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Dimens.s16),
              child: Text(tr(title), style: AppTypography.title),
            ),
            ...items.entries.map((e) {
              final selected = e.key == current;
              final sub = subtitleOf == null ? '' : subtitleOf(e.value);
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                ),
                title: Text(tr(e.key), style: AppTypography.body),
                subtitle: sub.isEmpty
                    ? null
                    : Text(tr(sub), style: AppTypography.caption),
                onTap: () {
                  onPick(e.value);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: Dimens.s8),
          ],
        ),
    );
  }

  Future<void> _checkUpdate() async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Checking for updates…')),
        duration: const Duration(seconds: 1)));
    final info = await widget.core.checkForUpdate();
    if (!mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr("You're on the latest version"))));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.system_update, color: AppColors.accent),
          const SizedBox(width: Dimens.s12),
          Expanded(child: Text('${tr('Update')} · v${info.version}')),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Text(
                info.notes.isEmpty
                    ? tr('A newer version is available.')
                    : info.notes,
                style: AppTypography.body
                    .copyWith(color: AppColors.textSecondary)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Later'))),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadUpdate(info);
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(tr('Update')),
          ),
        ],
      ),
    );
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  /// Download the APK with a progress dialog, then hand it to the system
  /// installer. Falls back to opening the release in the browser on failure.
  Future<void> _downloadUpdate(UpdateInfo info) async {
    // (received, total) bytes. total == 0 ⇒ length unknown (indeterminate bar).
    final progress = ValueNotifier<(int, int)>((0, 0));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.download_rounded, color: AppColors.accent),
          const SizedBox(width: Dimens.s12),
          Expanded(child: Text('${tr('Update')} · v${info.version}')),
        ]),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, v, __) {
            final received = v.$1, total = v.$2;
            final ratio = total > 0 ? received / total : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Dimens.rPill),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: AppColors.bgInput,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: Dimens.s12),
                Text(
                  ratio == null
                      ? '${_mb(received)} MB'
                      : '${_mb(received)} / ${_mb(total)} MB   ·   ${(ratio * 100).toStringAsFixed(0)}%',
                  style: AppTypography.caption,
                ),
              ],
            );
          },
        ),
      ),
    );
    final ok = await widget.core.downloadAndInstall(info.url,
        onProgress: (r, t) => progress.value = (r, t));
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // close progress dialog
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Download failed — opening in browser'))));
        widget.core.openExternalUrl(info.url);
      }
    }
    progress.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Dimens.pageInset, Dimens.s16, Dimens.pageInset, 0),
            child: Text(tr('Settings'), style: AppTypography.display),
          ),
          // Two-level grouping: three big categories — Control (how you drive
          // the remote), Interface (how the app looks/reads), and Other (app-
          // level). Control is subdivided into Interaction, Pointer & scrolling,
          // and Keyboard. See DESIGN.md §4.3.
          _category('Control'),
          _subsection('Interaction', [
            _row(Icons.touch_app, 'Default mode',
                value: _mode.label, onTap: _pickMode),
            _row(Icons.gesture, 'Customize gestures', onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GestureSettingsPage(config: _cfg),
              ));
            }),
            _row(Icons.tune, 'Gesture sensitivity', onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GestureTuningPage(config: _cfg),
              ));
            }),
            _switchRow(
                Icons.mouse_outlined, 'Hide cursor in Touch mode', _hideCursor,
                (v) {
              setState(() => _hideCursor = v);
              _cfg.setBool(ConfigKeys.hideCursorInTouch, v);
            }),
          ]),
          _subsection('Pointer & scrolling', [
            _sliderRow(
                Icons.speed,
                'Pointer speed',
                '${_pointerGain.toStringAsFixed(1)}×',
                _pointerGain,
                _gainMin,
                _gainMax,
                (v) => setState(() => _pointerGain = v),
                () => _cfg.set(ConfigKeys.pointerGainBase,
                    _pointerGain.toStringAsFixed(2))),
            _row(Icons.zoom_in, 'Max zoom',
                value: _labelOf(_maxZooms, _maxZoom),
                onTap: () => _pickOption('Max zoom', _maxZooms,
                    ConfigKeys.zoomMax, _maxZoom,
                    (v) => setState(() => _maxZoom = v))),
            _row(Icons.open_in_full, 'Edge auto-pan speed',
                value: _labelOf(_edgePans, _edgePan),
                onTap: () => _pickOption('Edge auto-pan speed', _edgePans,
                    ConfigKeys.edgePanSpeed, _edgePan,
                    (v) => setState(() => _edgePan = v))),
            // Slider runs slow→fast; internally a smaller px-per-notch is faster.
            _sliderRow(Icons.swipe_vertical, 'Scroll speed', null,
                _stepMin + _stepMax - _scrollStep, _stepMin, _stepMax,
                (v) => setState(() => _scrollStep = _stepMin + _stepMax - v),
                () => _cfg.set(
                    ConfigKeys.scrollStep, _scrollStep.round().toString())),
            _switchRow(
                Icons.swap_vert, 'Invert scroll direction', _scrollInvert, (v) {
              setState(() => _scrollInvert = v);
              _cfg.setBool(ConfigKeys.scrollInvert, v);
            }),
          ]),
          // Keys here map input sent to the remote (Fn shortcuts, hardware
          // volume-key actions); how the on-screen keyboard *looks* lives under
          // Interface instead.
          _subsection('Keyboard & keys', [
            _row(Icons.keyboard_command_key, 'Shortcut combos', onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ComboSettingsPage(config: _cfg),
              ));
            }),
            _row(Icons.volume_up_outlined, 'Volume Up key',
                value: _labelOf(_volumeActions, _volumeUp),
                onTap: () => _pickOption('Volume Up key', _volumeActions,
                    ConfigKeys.volumeUp, _volumeUp,
                    (v) => setState(() => _volumeUp = v))),
            _row(Icons.volume_down_outlined, 'Volume Down key',
                value: _labelOf(_volumeActions, _volumeDown),
                onTap: () => _pickOption('Volume Down key', _volumeActions,
                    ConfigKeys.volumeDown, _volumeDown,
                    (v) => setState(() => _volumeDown = v))),
          ]),
          // Interface — how the app looks / reads. General display first, then
          // the on-screen keyboard's appearance (size / opacity / labels).
          _category('Interface'),
          _card([
            _row(Icons.palette_outlined, 'Theme',
                value: _labelOf(_themes, _theme),
                onTap: () => _pickOption('Theme', _themes,
                    ConfigKeys.theme, _theme, (v) {
                  setState(() => _theme = v);
                  applyThemeSetting(v); // re-theme the neodesk UI live
                })),
            _row(Icons.language, 'Language',
                value: _labelOf(_languages, _language),
                onTap: () => _pickOption('Language', _languages,
                    ConfigKeys.language, _language, (v) {
                  setState(() => _language = v);
                  widget.core.setLanguage(v); // engine dialogs
                  applyLocale(v); // neodesk's own UI (zh / ja), live
                })),
            _row(Icons.speed_outlined, 'Quality monitor',
                value: _labelOf(_qualityDetails, _qualityDetail),
                onTap: () => _pickOption(
                    'Quality monitor',
                    _qualityDetails,
                    ConfigKeys.qualityMonitorDetail,
                    _qualityDetail,
                    (v) => setState(() => _qualityDetail = v))),
          ]),
          _subsection('On-screen keyboard', [
            _row(Icons.format_size, 'Key size',
                value: _labelOf(_keySizes, _keySize),
                onTap: () => _pickOption('Key size', _keySizes,
                    ConfigKeys.keySize, _keySize,
                    (v) => setState(() => _keySize = v))),
            _sliderRow(
                Icons.opacity,
                'Panel opacity',
                '${(_panelOpacity * 100).round()}%',
                _panelOpacity,
                _opacityMin,
                _opacityMax,
                (v) => setState(() => _panelOpacity = v),
                () => _cfg.set(ConfigKeys.panelOpacity,
                    _panelOpacity.toStringAsFixed(2))),
            _switchRow(Icons.view_compact_alt, 'Compact layout (swipe rows)',
                _keyCompact, (v) {
              setState(() => _keyCompact = v);
              _cfg.setBool(ConfigKeys.keyCompact, v);
            }),
            _switchRow(Icons.width_normal, 'Wide keys (show full labels)',
                _keyWide, (v) {
              setState(() => _keyWide = v);
              _cfg.setBool(ConfigKeys.keyWide, v);
            }),
          ]),
          // Other — app-level behaviour and About.
          _category('Other'),
          _card([
            _switchRow(Icons.picture_in_picture_alt_outlined,
                'Auto small window in background', _autoPip, (v) {
              setState(() => _autoPip = v);
              _cfg.setBool(ConfigKeys.autoPip, v);
            }),
            _switchRow(Icons.logout, 'Confirm before disconnecting',
                _confirmDisconnect, (v) {
              setState(() => _confirmDisconnect = v);
              _cfg.setBool(ConfigKeys.confirmDisconnect, v);
            }),
            _switchRow(
                Icons.lock_outline, 'App lock (require unlock)', _appLock,
                (v) async {
              final messenger = ScaffoldMessenger.of(context);
              if (v) {
                // Confirm a device credential exists / the user can authenticate
                // before turning the lock on, so they can't lock themselves out.
                final ok = await widget.core.authenticateAppLock();
                if (!ok) {
                  messenger.showSnackBar(SnackBar(
                      content: Text(tr(
                          'Set a device screen lock first (or authentication was cancelled)'))));
                  return;
                }
              }
              if (!mounted) return;
              setState(() => _appLock = v);
              _cfg.setBool(ConfigKeys.appLock, v);
              widget.core.setAppLockSecure(v); // FLAG_SECURE follows the setting
            }),
          ]),
          _subsection('About', [
            _row(Icons.info_outline, 'Version', value: _version),
            _row(Icons.system_update, 'Check for updates', onTap: _checkUpdate),
          ]),
          const SizedBox(height: Dimens.s24),
        ],
      ),
    );
  }

  /// A big top-level category header (大类, e.g. Control / Interface / Other).
  /// Sits a rung above [_subsection]'s accent subheaders: larger, primary-text,
  /// mixed-case. The card(s) beneath it are emitted separately.
  Widget _category(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Dimens.pageInset + Dimens.s4, Dimens.s24, Dimens.pageInset, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(tr(title), style: AppTypography.title),
        ),
      );

  /// A labelled subsection: an accent uppercase subheader over a single [_card].
  Widget _subsection(String title, List<Widget> rows) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Dimens.pageInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Dimens.s4, Dimens.s16, 0, Dimens.s8),
              child: Text(tr(title).toUpperCase(),
                  style: AppTypography.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
            ),
            _cardBody(rows),
          ],
        ),
      );

  /// A card of rows with no subheader — for a category that needs only one
  /// group (Interface, Other's app-level toggles). Adds the top gap that a
  /// [_subsection]'s subheader would otherwise provide.
  Widget _card(List<Widget> rows) => Padding(
        padding: const EdgeInsets.fromLTRB(
            Dimens.pageInset, Dimens.s12, Dimens.pageInset, 0),
        child: _cardBody(rows),
      );

  /// The rounded container of [rows] with hairline separators — the modern
  /// grouped-settings look.
  Widget _cardBody(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgElevated1,
          borderRadius: BorderRadius.circular(Dimens.rCard),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    thickness: 1,
                    indent: 56,
                    color: AppColors.divider),
              rows[i],
            ],
          ],
        ),
      );

  Widget _row(IconData icon, String label,
          {String? value, VoidCallback? onTap}) =>
      ListTile(
        leading: Icon(icon, color: AppColors.textSecondary),
        title: Text(tr(label), style: AppTypography.body),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null) Text(tr(value), style: AppTypography.caption),
            const SizedBox(width: 4),
            if (onTap != null)
              Icon(Icons.chevron_right,
                  color: AppColors.textDisabled, size: 20),
          ],
        ),
        onTap: onTap,
      );

  Widget _switchRow(IconData icon, String label, bool value,
          ValueChanged<bool> onChanged) =>
      ListTile(
        leading: Icon(icon, color: AppColors.textSecondary),
        title: Text(tr(label), style: AppTypography.body),
        trailing: Switch(value: value, onChanged: onChanged),
        onTap: () => onChanged(!value),
      );

  /// A setting whose slider is hidden until the row is tapped (accordion).
  Widget _sliderRow(IconData icon, String label, String? valueText,
      double value, double min, double max,
      ValueChanged<double> onChanged, VoidCallback onCommit) {
    final open = _openSlider == label;
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: AppColors.textSecondary),
          title: Text(tr(label), style: AppTypography.body),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (valueText != null)
                Text(tr(valueText), style: AppTypography.caption),
              const SizedBox(width: 4),
              Icon(open ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.textDisabled, size: 20),
            ],
          ),
          onTap: () => setState(() => _openSlider = open ? null : label),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState:
              open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: Dimens.s16),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accent,
                thumbColor: AppColors.accent,
                inactiveTrackColor: AppColors.border,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: (_) => onCommit(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
