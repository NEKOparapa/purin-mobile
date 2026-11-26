import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../l10n/app_language.dart';

import '../data/agent_api.dart';

class PairingScanner extends StatefulWidget {
  const PairingScanner({super.key});
  @override
  State<PairingScanner> createState() => _PairingScannerState();
}

class _PairingScannerState extends State<PairingScanner> {
  bool _complete = false;
  String _hint = '将管理页的配对二维码放入画面';

  void _detect(BarcodeCapture capture) {
    if (_complete || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (barcode.format == BarcodeFormat.qrCode &&
          value != null &&
          pairingAddress(value) != null) {
        _complete = true;
        Navigator.of(context).pop(value.trim());
        return;
      }
    }
    const invalid = '请扫描 Purin 管理页生成的配对二维码';
    if (_hint != invalid) setState(() => _hint = invalid);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('扫码配对'))),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: _detect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? context.tr('需要相机权限才能扫码。也可以返回粘贴配对链接。')
                        : context.tr('相机暂时不可用，可以返回粘贴配对链接。'),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.tr(_hint)),
          ),
        ],
      ),
    ),
  );
}
