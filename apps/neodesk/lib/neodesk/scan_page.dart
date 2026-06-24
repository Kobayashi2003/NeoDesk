import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:neodesk_core/ui/theme/app_colors.dart';

/// Opens a full-screen camera QR scanner and returns the first decoded text
/// (typically a device ID / address), or null if the user backs out. Used by
/// the adapter's `RustdeskCore.scanQrCode`.
Future<String?> neodeskScanQr(BuildContext context) =>
    Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _NeodeskScanPage()));

class _NeodeskScanPage extends StatefulWidget {
  const _NeodeskScanPage();

  @override
  State<_NeodeskScanPage> createState() => _NeodeskScanPageState();
}

class _NeodeskScanPageState extends State<_NeodeskScanPage> {
  final _qrKey = GlobalKey(debugLabel: 'neodesk-qr');
  QRViewController? _controller;
  bool _done = false;

  // Hot-reload safety for the platform camera view (per qr_code_scanner docs).
  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      _controller?.pauseCamera();
    }
    _controller?.resumeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onCreated(QRViewController c) {
    _controller = c;
    c.scannedDataStream.listen((data) {
      final code = data.code;
      if (!_done && code != null && code.isNotEmpty) {
        _done = true;
        c.pauseCamera();
        if (mounted) Navigator.of(context).pop(code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan device QR')),
      body: QRView(
        key: _qrKey,
        onQRViewCreated: _onCreated,
        overlay: QrScannerOverlayShape(
          borderColor: AppColors.accent,
          borderRadius: 16,
          borderLength: 28,
          borderWidth: 8,
          cutOutSize: 240,
        ),
      ),
    );
  }
}
