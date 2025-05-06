// ble_mtu.dart  – one-shot MTU negotiation with fallback to 185 B (iOS cap)
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'dart:io' show Platform;

class MtuNegotiator {
  static const int _desiredMtu = 240;     // what we’d *like*
  static const int _iosSafeMtu  = 185;    // Data Length Extension disabled
  final Logger _log = Logger();

  Future<int> negotiate(BluetoothDevice d) async {
    try {
      final mtu = await d.requestMtu(_desiredMtu);
      _log.i('MTU negotiated → $mtu B');
      return mtu;
    } catch (e) {
      // iOS will throw if we ask for > 185 and DLE is off
      final fallback = Platform.isIOS ? _iosSafeMtu : 185;
      _log.w('MTU request failed ($e). Falling back to $fallback B');
      try {
        final mtu = await d.requestMtu(fallback);
        _log.i('Fallback MTU → $mtu B');
        return mtu;
      } catch (_) {
        _log.e('Even fallback MTU failed – returning default (23 B).');
        return 23;                          // BLE default
      }
    }
  }
}
