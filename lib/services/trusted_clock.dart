import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef ClockReading = ({
  DateTime recordedAt,
  DateTime deviceTime,
  String timeSource,
});

class TrustedClock {
  TrustedClock._();

  static final TrustedClock instance = TrustedClock._();
  static const MethodChannel _channel = MethodChannel('attendance/clock');
  static const _serverKey = 'field_clock_server_anchor';
  static const _monoKey = 'field_clock_monotonic_anchor';
  final Stopwatch _fallback = Stopwatch()..start();
  DateTime? _serverAnchor;
  int? _monotonicAnchor;
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final preferences = await SharedPreferences.getInstance();
    final storedServer = preferences.getString(_serverKey);
    final storedMono = preferences.getInt(_monoKey);
    if (storedServer != null && storedMono != null) {
      _serverAnchor = DateTime.tryParse(storedServer);
      _monotonicAnchor = storedMono;
    }
  }

  Future<void> observeDateHeader(String? value) async {
    if (value == null || value.isEmpty) return;
    try {
      final serverTime = HttpDate.parse(value).toUtc();
      await anchor(serverTime);
    } on FormatException {
      return;
    }
  }

  Future<void> anchor(DateTime serverTime) async {
    await _load();
    final monotonic = await _monotonicMilliseconds();
    _serverAnchor = serverTime.toUtc();
    _monotonicAnchor = monotonic;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_serverKey, _serverAnchor!.toIso8601String());
    await preferences.setInt(_monoKey, monotonic);
  }

  Future<ClockReading> now() async {
    await _load();
    final deviceTime = DateTime.now();
    final anchorServer = _serverAnchor;
    final anchorMono = _monotonicAnchor;
    if (anchorServer == null || anchorMono == null) {
      return (
        recordedAt: deviceTime.toUtc(),
        deviceTime: deviceTime.toUtc(),
        timeSource: 'device',
      );
    }

    final monotonic = await _monotonicMilliseconds();
    if (monotonic < anchorMono) {
      return (
        recordedAt: deviceTime.toUtc(),
        deviceTime: deviceTime.toUtc(),
        timeSource: 'device',
      );
    }

    return (
      recordedAt: anchorServer.add(
        Duration(milliseconds: monotonic - anchorMono),
      ),
      deviceTime: deviceTime.toUtc(),
      timeSource: 'trusted',
    );
  }

  Future<int> _monotonicMilliseconds() async {
    try {
      return await _channel.invokeMethod<int>('elapsedRealtime') ??
          _fallback.elapsedMilliseconds;
    } on PlatformException {
      return _fallback.elapsedMilliseconds;
    } on MissingPluginException {
      return _fallback.elapsedMilliseconds;
    }
  }
}
