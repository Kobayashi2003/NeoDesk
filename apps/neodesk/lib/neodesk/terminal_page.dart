import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:neodesk_core/ui/theme/app_colors.dart';

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
  }

  @override
  void dispose() {
    _ffi.unregisterTerminalModel(_terminalId);
    _model.dispose();
    TerminalConnectionManager.releaseConnection(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: Text('Terminal · ${widget.id}')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: TerminalView(
                _model.terminal,
                controller: _model.terminalController,
                autofocus: true,
                backgroundOpacity: 0, // show the neodesk scaffold colour
                textStyle: const TerminalStyle(fontSize: 13),
                padding: const EdgeInsets.all(8),
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
    ('^D', '\x04'),
    ('^Z', '\x1A'),
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
        decoration: const BoxDecoration(
          color: AppColors.bgElevated1,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          itemCount: _keys.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final (label, seq) = _keys[i];
            return GestureDetector(
              onTap: () => _model.sendVirtualKey(seq),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            );
          },
        ),
      );
}
