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

  // Preset tables. Numeric settings are sliders (see [_sliderRow]); only the
  // genuinely enumerated ones remain pickers.
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
  static const _zoomMin = 1.5, _zoomMax = 6.0;
  static const _edgePanMin = 2.0, _edgePanMax = 12.0; // screen px per tick
  static const _opacityMin = 0.55, _opacityMax = 1.0;

  /// Renders a raw slider position as a percentage of its range — for settings
  /// whose absolute number means nothing to the user.
  static String Function(double) _percentOf(double min, double max) =>
      (v) => '${((v - min) / (max - min) * 100).round()}%';

  late InteractionUiMode _mode;
  late double _pointerGain; // pointer.gainBase
  late double _scrollStep; // scroll.step (smaller = faster)
  late double _maxZoom;
  late double _edgePan;
  late double _fontScale;
  late bool _scrollInvert;
  late bool _hideCursor;
  late double _panelOpacity; // panel.opacity
  late String _keySize;
  late bool _keyCompact;
  late bool _keyWide;
  late bool _keyMousePanel;
  late String _volumeUp;
  late String _volumeDown;
  late String _language;
  late String _theme;
  late bool _appLock;
  late bool _autoPip;
  late bool _confirmDisconnect;
  late String _qualityDetail;

  /// The label of the row currently being edited in place (null = none), and its
  /// uncommitted value. See [_sliderRow].
  String? _editing;
  double _draft = 0;

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
    _maxZoom = (double.tryParse(_cfg.get(ConfigKeys.zoomMax)) ?? 3.0)
        .clamp(_zoomMin, _zoomMax);
    _edgePan = edgePanSpeedFrom(_cfg.get(ConfigKeys.edgePanSpeed))
        .clamp(_edgePanMin, _edgePanMax);
    _fontScale = (double.tryParse(_cfg.get(ConfigKeys.fontScale)) ?? 1.0)
        .clamp(kTextScaleMin, kTextScaleMax);
    _scrollInvert = _cfg.getBool(ConfigKeys.scrollInvert);
    _hideCursor =
        _cfg.getBool(ConfigKeys.hideCursorInTouch, defaultValue: true);
    _panelOpacity = (double.tryParse(_cfg.get(ConfigKeys.panelOpacity)) ?? 0.9)
        .clamp(_opacityMin, _opacityMax);
    _keySize = _cfg.get(ConfigKeys.keySize, defaultValue: 'medium');
    _keyCompact = _cfg.getBool(ConfigKeys.keyCompact);
    _keyWide = _cfg.getBool(ConfigKeys.keyWide);
    _keyMousePanel =
        _cfg.getBool(ConfigKeys.keyMousePanel, defaultValue: true);
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
            _boolRow(Icons.mouse_outlined, 'Hide cursor in Touch mode',
                ConfigKeys.hideCursorInTouch, _hideCursor,
                (v) => _hideCursor = v),
          ]),
          _subsection('Pointer & scrolling', [
            _sliderRow(Icons.speed, 'Pointer speed',
                value: _pointerGain,
                min: _gainMin,
                max: _gainMax,
                format: (v) => '${v.toStringAsFixed(1)}×',
                commit: (v) {
                  setState(() => _pointerGain = v);
                  _cfg.set(ConfigKeys.pointerGainBase, v.toStringAsFixed(2));
                }),
            _sliderRow(Icons.zoom_in, 'Max zoom',
                value: _maxZoom,
                min: _zoomMin,
                max: _zoomMax,
                format: (v) => '${v.toStringAsFixed(1)}×',
                commit: (v) {
                  setState(() => _maxZoom = v);
                  _cfg.set(ConfigKeys.zoomMax, v.toStringAsFixed(1));
                }),
            _sliderRow(Icons.open_in_full, 'Edge auto-pan speed',
                value: _edgePan,
                min: _edgePanMin,
                max: _edgePanMax,
                format: (v) => v.toStringAsFixed(1),
                commit: (v) {
                  setState(() => _edgePan = v);
                  _cfg.set(ConfigKeys.edgePanSpeed, v.toStringAsFixed(1));
                }),
            // Shown slow→fast; internally a smaller px-per-notch is faster.
            _sliderRow(Icons.swipe_vertical, 'Scroll speed',
                value: _stepMin + _stepMax - _scrollStep,
                min: _stepMin,
                max: _stepMax,
                format: _percentOf(_stepMin, _stepMax),
                commit: (v) {
                  final step = _stepMin + _stepMax - v;
                  setState(() => _scrollStep = step);
                  _cfg.set(ConfigKeys.scrollStep, step.round().toString());
                }),
            _boolRow(Icons.swap_vert, 'Invert scroll direction',
                ConfigKeys.scrollInvert, _scrollInvert,
                (v) => _scrollInvert = v),
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
            _sliderRow(Icons.text_fields, 'Font size',
                value: _fontScale,
                min: kTextScaleMin,
                max: kTextScaleMax,
                format: (v) => '${(v * 100).round()}%',
                commit: (v) {
                  setState(() => _fontScale = v);
                  _cfg.set(ConfigKeys.fontScale, v.toStringAsFixed(2));
                  applyTextScale(v.toStringAsFixed(2)); // re-scale the UI live
                }),
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
            _sliderRow(Icons.opacity, 'Panel opacity',
                value: _panelOpacity,
                min: _opacityMin,
                max: _opacityMax,
                format: (v) => '${(v * 100).round()}%',
                commit: (v) {
                  setState(() => _panelOpacity = v);
                  _cfg.set(ConfigKeys.panelOpacity, v.toStringAsFixed(2));
                }),
            _boolRow(Icons.view_compact_alt, 'Compact layout (swipe rows)',
                ConfigKeys.keyCompact, _keyCompact, (v) => _keyCompact = v),
            _boolRow(Icons.width_normal, 'Wide keys (show full labels)',
                ConfigKeys.keyWide, _keyWide, (v) => _keyWide = v),
            _boolRow(Icons.mouse_outlined, 'Mouse buttons panel',
                ConfigKeys.keyMousePanel, _keyMousePanel,
                (v) => _keyMousePanel = v),
          ]),
          // Other — app-level behaviour and About.
          _category('Other'),
          _card([
            _boolRow(Icons.picture_in_picture_alt_outlined,
                'Auto small window in background', ConfigKeys.autoPip, _autoPip,
                (v) => _autoPip = v),
            _boolRow(Icons.logout, 'Confirm before disconnecting',
                ConfigKeys.confirmDisconnect, _confirmDisconnect,
                (v) => _confirmDisconnect = v),
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

  /// A switch wired straight to a [ConfigStore] bool: [assign] updates the local
  /// field, [key] receives the same value. Keeps the two from drifting apart.
  Widget _boolRow(IconData icon, String label, String key, bool value,
          ValueChanged<bool> assign) =>
      _switchRow(icon, label, value, (v) {
        setState(() => assign(v));
        _cfg.setBool(key, v);
      });

  /// A numeric setting edited **in place**: tapping the row turns it into a
  /// slider with confirm / cancel. Nothing opens, so it carries no chevron —
  /// only rows that push a page or a sheet do.
  ///
  /// The live value is a draft ([_draft]); [commit] runs on the green check and
  /// the red cross discards it, so dragging never half-applies a setting.
  Widget _sliderRow(
    IconData icon,
    String label, {
    required double value,
    required double min,
    required double max,
    required String Function(double) format,
    required ValueChanged<double> commit,
  }) {
    if (_editing != label) {
      return ListTile(
        leading: Icon(icon, color: AppColors.textSecondary),
        title: Text(tr(label), style: AppTypography.body),
        trailing: Text(format(value), style: AppTypography.caption),
        onTap: () => setState(() {
          _editing = label;
          _draft = value.clamp(min, max);
        }),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Dimens.s16, Dimens.s4, Dimens.s8, 0),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent),
          const SizedBox(width: Dimens.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(tr(label), style: AppTypography.body)),
                    Text(format(_draft),
                        style: AppTypography.caption
                            .copyWith(color: AppColors.accent)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.accent,
                    thumbColor: AppColors.accent,
                    inactiveTrackColor: AppColors.border,
                    trackHeight: 2,
                  ),
                  child: Slider(
                    value: _draft.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: (v) => setState(() => _draft = v),
                  ),
                ),
              ],
            ),
          ),
          // The palette's accent *is* the green; danger is the red.
          _editAction(Icons.check, AppColors.accent, () {
            commit(_draft);
            setState(() => _editing = null);
          }),
          _editAction(Icons.close, AppColors.danger,
              () => setState(() => _editing = null)),
        ],
      ),
    );
  }

  Widget _editAction(IconData icon, Color color, VoidCallback onTap) =>
      IconButton(
        icon: Icon(icon, color: color),
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      );
}
