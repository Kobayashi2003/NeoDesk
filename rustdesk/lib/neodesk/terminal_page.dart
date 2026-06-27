import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:xterm/xterm.dart';
import 'package:neodesk_core/neodesk_core.dart' show tr, ConfigKeys;
import 'package:neodesk_core/ui/theme/app_colors.dart';

import 'launcher.dart' show neodeskCore;
import '../models/model.dart' show FFI;
import '../models/terminal_model.dart';
import '../desktop/pages/terminal_connection_manager.dart';

/// Opens a neodesk-styled remote terminal for [id]. Reuses RustDesk's terminal
/// plumbing (a dedicated FFI via [TerminalConnectionManager], a [TerminalModel]
/// bound to an xterm `Terminal`). Launched by the adapter's
/// `RustdeskCore.openTerminal`.
Future<void> neodeskOpenTerminal(BuildContext context, String id,
        {String? password}) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _NeodeskTerminalPage(id: id, password: password)));

class _NeodeskTerminalPage extends StatefulWidget {
  const _NeodeskTerminalPage({required this.id, this.password});

  final String id;
  final String? password;

  @override
  State<_NeodeskTerminalPage> createState() => _NeodeskTerminalPageState();
}

class _NeodeskTerminalPageState extends State<_NeodeskTerminalPage> {
  static const _terminalId = 0;
  late final FFI _ffi;
  late final TerminalModel _model;
  final _focusNode = FocusNode();

  /// Sticky Ctrl: when armed, the next typed character is sent as its control
  /// code (so Ctrl+anything works from the soft keyboard, not just preset combos).
  bool _ctrlArmed = false;
  // Persisted so the A-/A+ choice and pinch-zoom carry across terminal sessions.
  late double _fontSize = (double.tryParse(
          neodeskCore.config.get(ConfigKeys.terminalFontSize)) ??
      14)
      .clamp(9.0, 26.0);
  bool _opened = false;
  Timer? _openPoll;

  void _saveFont() => neodeskCore.config
      .set(ConfigKeys.terminalFontSize, _fontSize.toStringAsFixed(1));

  @override
  void initState() {
    super.initState();
    // A terminal uses its own FFI (not the global gFFI), started with
    // isTerminal:true; the engine calls model.onReady() once it connects.
    _ffi = TerminalConnectionManager.getConnection(
      peerId: widget.id,
      password: widget.password,
      isSharedPassword: null,
      forceRelay: null,
      connToken: null,
    );
    _model = TerminalModel(_ffi, _terminalId);
    _ffi.registerTerminalModel(_terminalId, _model);

    // Wrap the terminal's input so a sticky Ctrl can transform the next char.
    final original = _model.terminal.onOutput;
    _model.terminal.onOutput = (data) {
      if (_ctrlArmed) {
        _ctrlArmed = false;
        // Un-highlight the Ctrl chip after this frame (we're mid-input here).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
        if (data.length == 1) data = _toCtrl(data);
      }
      original?.call(data);
    };

    // Surface a "Connecting…" bar until the remote shell is open (give up after
    // ~12s so a failed connect doesn't leave the bar — and the timer — running).
    var polls = 0;
    _openPoll = Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (_model.terminalOpened || ++polls > 40) {
        t.cancel();
        if (mounted) setState(() => _opened = true);
      }
    });
  }

  @override
  void dispose() {
    _openPoll?.cancel();
    _focusNode.dispose();
    _ffi.unregisterTerminalModel(_terminalId);
    _model.dispose();
    TerminalConnectionManager.releaseConnection(widget.id);
    super.dispose();
  }

  /// Map a printable char to its control code (Ctrl+C → 0x03, etc.).
  String _toCtrl(String ch) {
    final c = ch.codeUnitAt(0);
    if (c >= 0x40 && c < 0x80) return String.fromCharCode(c & 0x1f);
    return ch;
  }

  void _toggleKeyboard() {
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isNotEmpty) _model.sendVirtualKey(text);
  }

  void _setFont(double delta) {
    setState(() => _fontSize = (_fontSize + delta).clamp(9.0, 26.0));
    _saveFont();
  }

  /// Copy the current terminal selection to the clipboard (if any).
  Future<void> _copySelection() async {
    final sel = _model.terminalController.selection;
    final text = sel == null ? '' : _model.terminal.buffer.getText(sel);
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Select text first')),
            duration: const Duration(seconds: 1)));
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Copied')), duration: const Duration(seconds: 1)));
    }
  }

  // Pinch-to-zoom: track raw pointers via a passive Listener (which never enters
  // the gesture arena, so it can't swallow TerminalView's tap/selection). While
  // two fingers are down, scale the font by the change in finger distance.
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double _pinchStartFont = 14;

  double _pointerDistance() {
    final pts = _pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _pinchStartDist = _pointerDistance();
      _pinchStartFont = _fontSize;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final start = _pinchStartDist;
    if (_pointers.length == 2 && start != null && start > 0) {
      final next = (_pinchStartFont * _pointerDistance() / start).clamp(9.0, 26.0);
      if (next != _fontSize) setState(() => _fontSize = next);
    }
  }

  void _onPointerUp(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.length < 2) {
      if (_pinchStartDist != null) _saveFont(); // a pinch just ended
      _pinchStartDist = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: Text('${tr('Terminal')} · ${widget.id}'),
        actions: [
          IconButton(
              tooltip: 'A-',
              onPressed: () => _setFont(-1),
              icon: const Icon(Icons.text_decrease)),
          IconButton(
              tooltip: 'A+',
              onPressed: () => _setFont(1),
              icon: const Icon(Icons.text_increase)),
          IconButton(
              tooltip: tr('Copy'),
              onPressed: _copySelection,
              icon: const Icon(Icons.copy)),
          IconButton(
              tooltip: tr('Paste'),
              onPressed: _paste,
              icon: const Icon(Icons.content_paste)),
          IconButton(
              tooltip: tr('Keyboard'),
              onPressed: _toggleKeyboard,
              icon: const Icon(Icons.keyboard)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_opened)
              LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: AppColors.bgElevated1,
                  color: AppColors.accent),
            Expanded(
              // TerminalView handles its own tap (focus + cursor/selection); the
              // keyboard button covers explicit show/hide. We wrap it in a passive
              // Listener (not a GestureDetector) for pinch-zoom so we never
              // compete in the gesture arena and swallow taps.
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: (e) => _onPointerUp(e.pointer),
                onPointerCancel: (e) => _onPointerUp(e.pointer),
                child: TerminalView(
                  _model.terminal,
                  controller: _model.terminalController,
                  focusNode: _focusNode,
                  autofocus: true,
                  backgroundOpacity: 0, // show the neodesk scaffold colour
                  textStyle: TerminalStyle(fontSize: _fontSize),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
            _extraKeys(),
          ],
        ),
      ),
    );
  }

  // The keys a phone keyboard lacks but a terminal needs, as raw escape
  // sequences (the recipe RustDesk's own mobile terminal uses).
  static const _keys = <(String, String)>[
    ('Esc', '\x1B'),
    ('Tab', '\t'),
    ('^C', '\x03'),
    ('←', '\x1B[D'),
    ('↑', '\x1B[A'),
    ('↓', '\x1B[B'),
    ('→', '\x1B[C'),
    ('Home', '\x1B[H'),
    ('End', '\x1B[F'),
    ('PgUp', '\x1B[5~'),
    ('PgDn', '\x1B[6~'),
  ];

  Widget _extraKeys() => Container(
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.bgElevated1,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          children: [
            // Sticky Ctrl: arm, then type a letter (or use the keys below).
            _key('Ctrl', () => setState(() => _ctrlArmed = !_ctrlArmed),
                active: _ctrlArmed),
            for (final (label, seq) in _keys) ...[
              const SizedBox(width: 6),
              _key(label, () => _model.sendVirtualKey(seq)),
            ],
          ],
        ),
      );

  Widget _key(String label, VoidCallback onTap, {bool active = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.bgElevated2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? AppColors.textOnAccent : AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      );
}
