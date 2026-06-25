import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neodesk_core/neodesk_core.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/dimens.dart';
import 'key_capture.dart';
import 'key_combo.dart';

/// The remote keyboard: two separate, independently-summonable surfaces.
///
/// **System keyboard** ([systemActive]) — the phone's ordinary soft keyboard,
/// captured *invisibly* (no in-app text box) and forwarded as real key events,
/// the way a normal remote client works. Capture uses RustDesk's proven recipe:
/// a 0×0 multiline `TextField` holding a long filler buffer, whose `onChanged`
/// delta becomes key presses (and backspaces).
///
/// **Special keys** ([specialActive]) — a panel of the keys a soft keyboard
/// lacks: sticky modifiers, Esc/Tab/Enter/nav/F-keys and shortcut combos. It can
/// be shown on its own or stacked above the system keyboard.
///
/// Keys use the engine's `VK_*` names and modifiers are sent as engine flags via
/// [InputSink.setModifiers] (not as modifier key events) — the only thing the
/// prebuilt engine actually honours. See DESIGN.md §4.4.
class RemoteKeyboard extends StatefulWidget {
  const RemoteKeyboard({
    super.key,
    required this.input,
    required this.systemActive,
    required this.specialActive,
    required this.combosActive,
    required this.onToggleSystem,
    required this.onToggleSpecial,
    required this.onToggleCombos,
    required this.onHide,
    required this.combos,
    this.opacity = 0.9,
    this.keySize = 'medium',
    this.compact = false,
  });

  final InputSink input;
  final bool systemActive;
  final bool specialActive;
  final bool combosActive;
  final VoidCallback onToggleSystem;
  final VoidCallback onToggleSpecial;
  final VoidCallback onToggleCombos;
  final VoidCallback onHide;

  /// User-configured shortcut chords (see ComboSettingsPage / [ComboStore]).
  final List<KeyCombo> combos;

  /// Panel background opacity (0.55–1.0) — see-through to reduce occlusion.
  final double opacity;

  /// On-screen key size: `small` / `medium` / `large`.
  final String keySize;

  /// Compact layout: fewer, horizontally-scrollable rows instead of the grid.
  final bool compact;

  @override
  State<RemoteKeyboard> createState() => _RemoteKeyboardState();
}

class _RemoteKeyboardState extends State<RemoteKeyboard> {
  /// Long filler buffer so backspace works indefinitely and inserts have room;
  /// the field is 0×0 so the user never sees it. (Mirrors RustDesk mobile.)
  static const _base = '1111111111111111111111111111111111111111';

  /// Reset the filler buffer when it drifts outside this range, so backspace and
  /// insert never run out of room at either end.
  static const _bufferMin = 12;
  static const _bufferMax = 4000;

  /// How long a tapped key stays highlighted (visual tap feedback).
  static const _flashDuration = Duration(milliseconds: 150);

  final _capture = TextEditingController(text: _base);
  final _focus = FocusNode();
  String _value = _base;

  /// "Hold" mode: when armed, the next key tapped is held down (see [_held]).
  bool _holdArmed = false;

  /// Currently held-down keys (via the Hold key), as `VK_*`/`Meta`/char tokens —
  /// a real keydown was sent and the matching keyup is deferred until release.
  /// Modifiers are tracked here too as `mod:<id>` (the engine honours a sustained
  /// modifier keydown, so no flag bookkeeping is needed). Multiple may be held.
  final Set<String> _held = {};

  /// Label of the key currently flashing from a tap (visual feedback).
  String? _flashing;

  /// Whether the soft keyboard was up last time we checked the view insets.
  bool _softKbWasOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.systemActive) _focusSoon();
  }

  /// Detect the soft keyboard being dismissed by Android's back gesture/button.
  /// Back only *hides* the IME — the capture field keeps focus — so a FocusNode
  /// listener never fires; the reliable signal is the keyboard inset dropping to
  /// 0. Reading MediaQuery here registers the dependency, so this re-runs on every
  /// inset change. When the ABC surface is active and the keyboard goes away, sync
  /// the ABC chip off.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final open = MediaQuery.of(context).viewInsets.bottom > 0;
    if (!widget.systemActive) {
      _softKbWasOpen = open;
      return;
    }
    if (open) {
      _softKbWasOpen = true;
    } else if (_softKbWasOpen) {
      _softKbWasOpen = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.systemActive &&
            MediaQuery.of(context).viewInsets.bottom == 0) {
          widget.onToggleSystem();
        }
      });
    }
  }

  @override
  void didUpdateWidget(RemoteKeyboard old) {
    super.didUpdateWidget(old);
    if (widget.systemActive && !old.systemActive) {
      _focusSoon();
    } else if (!widget.systemActive && old.systemActive) {
      _focus.unfocus();
    }
  }

  @override
  void dispose() {
    // Release any held keys (clean keyup, press:false) and clear modifier flags
    // so nothing leaks into gesture clicks once the keyboard closes.
    for (final t in _held) {
      final vk = t.startsWith('mod:') ? _modVk[t.substring(4)]! : t;
      widget.input.key(vk, down: false, press: false);
    }
    widget.input.setModifiers(ctrl: false, alt: false, shift: false, meta: false);
    _capture.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _focusSoon() {
    _reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.systemActive) _focus.requestFocus();
    });
  }

  void _reset() {
    _value = _base;
    _capture.value = const TextEditingValue(
      text: _base,
      selection: TextSelection.collapsed(offset: _base.length),
    );
  }

  // ---- Hold key + key sending -----------------------------------------------
  //
  // Hold lets you hold several keys at once, one arm per key. Tap Hold (it
  // highlights), tap a key → that key holds and Hold de-arms; tap Hold again and
  // another key to add it (Ctrl+Shift held = Hold,Ctrl, Hold,Shift). A held key
  // releases when you tap it again.
  //
  // KEY SEMANTICS: the engine's `key()` defaults `press` to true (a down+up tap).
  // A true *hold* must pass `press: false` with `down: true` (keydown only) and
  // release with `down: false, press: false` (keyup only) — otherwise "hold"
  // silently degrades to a tap (Win would open Start instantly, and nothing
  // reads as held). The prebuilt engine honours a sustained modifier keydown, so
  // held Ctrl/Shift/etc. ride along with whatever key you press next — no
  // modifier-flag bookkeeping needed. (Flags are only used for one-shot Combos.)

  static const _modVk = {
    'ctrl': 'VK_CONTROL',
    'alt': 'VK_MENU',
    'shift': 'VK_SHIFT',
    'meta': 'Meta',
  };

  void _tapHold() => setState(() => _holdArmed = !_holdArmed);

  /// Tap of a `VK_*` key, routed through the Hold state machine.
  void _tapVk(String vk) => _tapKey(vk, vk);

  /// Shared hold/press logic for non-modifier keys. [token] is the held-set key;
  /// [vk] the engine key.
  void _tapKey(String token, String vk) {
    if (_holdArmed) {
      widget.input.key(vk, down: true, press: false); // sustained keydown
      setState(() {
        _held.add(token);
        _holdArmed = false;
      });
    } else if (_held.contains(token)) {
      widget.input.key(vk, down: false, press: false); // re-tap releases (keyup)
      setState(() => _held.remove(token));
    } else {
      widget.input.key(vk, press: true); // momentary tap (held modifiers apply)
    }
  }

  /// Tap of a modifier key. A held modifier sends BOTH a real sustained keydown
  /// (so it reads as held and chords with Fn keys) AND sets the engine flag — the
  /// flag is what makes it ride on the *letters* the system keyboard sends, since
  /// those go out as char/text events that only combine with a modifier via the
  /// flag, not via a separately-held key.
  void _tapMod(String m) {
    final token = 'mod:$m';
    if (_holdArmed) {
      widget.input.key(_modVk[m]!, down: true, press: false);
      setState(() {
        _held.add(token);
        _holdArmed = false;
      });
      _applyHeldMods();
    } else if (_held.contains(token)) {
      widget.input.key(_modVk[m]!, down: false, press: false);
      setState(() => _held.remove(token));
      _applyHeldMods();
    } else {
      widget.input.key(_modVk[m]!, press: true); // momentary tap
    }
  }

  /// Re-assert the engine modifier flags from the currently-held modifiers.
  void _applyHeldMods() => widget.input.setModifiers(
        ctrl: _held.contains('mod:ctrl'),
        alt: _held.contains('mod:alt'),
        shift: _held.contains('mod:shift'),
        meta: _held.contains('mod:meta'),
      );

  /// One-shot chord via engine modifier flags: set them, tap the key, then
  /// restore the flags of any modifiers still held.
  void _combo(KeyCombo c) {
    widget.input
        .setModifiers(ctrl: c.ctrl, alt: c.alt, shift: c.shift, meta: c.meta);
    widget.input.key(c.key, press: true);
    _applyHeldMods();
    HapticFeedback.selectionClick();
  }

  /// Map a typed character to the engine and send it.
  void _char(String ch) {
    switch (ch) {
      case '\n':
        widget.input.key('VK_RETURN', press: true);
      case ' ':
        widget.input.key('VK_SPACE', press: true);
      case '\t':
        widget.input.key('VK_TAB', press: true);
      default:
        widget.input.key(ch, press: true);
    }
  }

  /// Invisible system-keyboard capture: forward the edit delta as key events.
  /// The decision logic is in [computeCaptureDelta] (pure + unit-tested); this
  /// just extracts the composing region and dispatches the result to the engine.
  void _onCapture(String v) {
    final composing = _capture.value.composing;
    final composingText = composing.isValid && !composing.isCollapsed
        ? composing.textInside(v)
        : '';
    final delta = computeCaptureDelta(_value, v, composingText);
    if (delta.deferred) return; // IME composing CJK — keep the buffer, send later
    _value = v;
    for (var i = 0; i < delta.backspaces; i++) {
      widget.input.key('VK_BACK', press: true);
    }
    if (delta.committed.isNotEmpty) _commitText(delta.committed);
    // Keep the buffer comfortably mid-range so backspace/insert never run out.
    if (_value.length < _bufferMin || _value.length > _bufferMax) _reset();
  }

  /// Forward committed text: a single ASCII char as a key event, anything longer
  /// or non-ASCII (CJK, emoji) as one string so character order is preserved.
  void _commitText(String s) {
    if (s.isEmpty) return;
    if (isSingleAsciiChar(s)) {
      _char(s);
    } else {
      widget.input.text(s);
    }
  }

  // ---- layout & sizing ------------------------------------------------------

  double get _keyHeight => switch (widget.keySize) {
        'small' => 34,
        'large' => 50,
        _ => 42,
      };

  double get _keyWidth => switch (widget.keySize) {
        'small' => 48,
        'large' => 66,
        _ => 56,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // User-tunable opacity over the dark panel, so the remote shows through.
        color: const Color(0xFF181818).withOpacity(widget.opacity.clamp(0.4, 1)),
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Dimens.rSheet)),
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.specialActive) _specialPanel(),
            if (widget.combosActive) _combosPanel(),
            _controlStrip(),
            // Invisible capture for the system keyboard (RustDesk's 0×0 trick).
            SizedBox(
              width: 0,
              height: 0,
              child: TextField(
                controller: _capture,
                focusNode: _focus,
                // multiline + maxLines:null is RustDesk's trick to make the soft
                // keyboard's Backspace fire reliably. `enableSuggestions:false` is
                // intentionally omitted — on Android it can force a secure
                // (password) keyboard.
                keyboardType: TextInputType.multiline,
                maxLines: null,
                autocorrect: false,
                onChanged: _onCapture,
                decoration: const InputDecoration.collapsed(hintText: ''),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlStrip() => Padding(
        padding: const EdgeInsets.fromLTRB(Dimens.s8, Dimens.s8, Dimens.s8, 0),
        child: Row(
          children: [
            _chip('ABC', widget.onToggleSystem,
                active: widget.systemActive, icon: Icons.keyboard),
            const SizedBox(width: Dimens.s8),
            _chip('Fn', widget.onToggleSpecial,
                active: widget.specialActive, icon: Icons.functions),
            const SizedBox(width: Dimens.s8),
            _chip('Combos', widget.onToggleCombos,
                active: widget.combosActive, icon: Icons.bolt),
            const Spacer(),
            _tapButton(Icons.keyboard_hide, widget.onHide),
          ],
        ),
      );

  // Grid mode: fixed rows whose keys flex to equal width and fill the row.
  // Compact mode: fewer, horizontally-scrollable rows (a much shorter panel).
  Widget _specialPanel() {
    final mods = [
      _button('Hold', _tapHold, active: _holdArmed),
      _modKey('Ctrl', 'ctrl'),
      _modKey('Alt', 'alt'),
      _modKey('Shift', 'shift'),
      // Win is a real key (tap opens Start); Win+key chords live in Combos.
      _vk('Win', 'Meta'),
      _vk('Caps', 'VK_CAPITAL'),
    ];
    final edit = [
      _vk('Esc', 'VK_ESCAPE'),
      _vk('Tab', 'VK_TAB'),
      _vk('Enter', 'VK_ENTER'),
      _vk('⌫', 'VK_BACK'),
      _vk('Del', 'VK_DELETE'),
      _vk('Ins', 'VK_INSERT'),
      _vk('PrtSc', 'VK_SNAPSHOT'),
    ];
    final nav = [
      _vk('←', 'VK_LEFT'),
      _vk('↑', 'VK_UP'),
      _vk('↓', 'VK_DOWN'),
      _vk('→', 'VK_RIGHT'),
      _vk('Home', 'VK_HOME'),
      _vk('End', 'VK_END'),
      _vk('PgUp', 'VK_PRIOR'),
      _vk('PgDn', 'VK_NEXT'),
    ];
    final fns = [for (var i = 1; i <= 12; i++) _vk('F$i', 'VK_F$i')];

    if (widget.compact) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        _scrollRow([...mods, ...edit, ...nav]),
        _scrollRow(fns),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _keyRow(mods),
      _keyRow(edit),
      _keyRow(nav),
      _keyRow(fns.sublist(0, 6)),
      _keyRow(fns.sublist(6)),
    ]);
  }

  /// Standalone shortcut-combos surface (toggled by the Combos chip / toolbar).
  Widget _combosPanel() {
    final keys = [
      for (final c in widget.combos) _button(c.label, () => _combo(c)),
    ];
    if (keys.isEmpty) return const SizedBox.shrink();
    if (widget.compact) return _scrollRow(keys);
    final rows = <Widget>[];
    for (var i = 0; i < keys.length; i += 3) {
      final chunk = keys.skip(i).take(3).toList();
      while (chunk.length < 3) {
        chunk.add(const SizedBox());
      }
      rows.add(_keyRow(chunk));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  /// A row of equal-width keys filling the available width (grid mode).
  Widget _keyRow(List<Widget> keys) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Dimens.s4, vertical: 3),
        child: Row(children: [for (final k in keys) Expanded(child: k)]),
      );

  /// A horizontally-scrollable row of fixed-width keys (compact mode).
  Widget _scrollRow(List<Widget> keys) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Dimens.s4, vertical: 3),
        child: Row(
          children: [
            for (final k in keys) SizedBox(width: _keyWidth, child: k),
          ],
        ),
      );

  Widget _vk(String label, String name) =>
      _button(label, () => _tapVk(name), active: _held.contains(name));

  Widget _modKey(String label, String m) =>
      _button(label, () => _tapMod(m), active: _held.contains('mod:$m'));

  /// Briefly flash a key on tap (visual + haptic feedback), keyed by its label.
  void _flashTap(String id) {
    HapticFeedback.selectionClick();
    setState(() => _flashing = id);
    Future.delayed(_flashDuration, () {
      if (mounted && _flashing == id) setState(() => _flashing = null);
    });
  }

  Widget _button(String label, VoidCallback onTap, {bool active = false}) {
    final on = active || _flashing == label;
    return Padding(
      padding: const EdgeInsets.all(2.5),
      // GestureDetector (not InkWell/IconButton) so tapping a key never steals
      // focus from the capture field and dismisses the system keyboard.
      child: GestureDetector(
        onTap: () {
          _flashTap(label);
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: _keyHeight,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.accent : AppColors.bgElevated2,
            borderRadius: BorderRadius.circular(Dimens.rChip),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(
              color: on ? AppColors.textOnAccent : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap,
          {required bool active, required IconData icon}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: Dimens.s12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.bgElevated2,
            borderRadius: BorderRadius.circular(Dimens.rChip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color:
                      active ? AppColors.textOnAccent : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: AppTypography.caption.copyWith(
                    color: active
                        ? AppColors.textOnAccent
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      );

  Widget _tapButton(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Dimens.s8),
          child: Icon(icon, color: AppColors.textSecondary),
        ),
      );
}
