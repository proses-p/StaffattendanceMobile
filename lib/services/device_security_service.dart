import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceSecurityService {
  static const MethodChannel _channel = MethodChannel(
    'staff_attendance/secure_signing',
  );

  Future<bool> canSign() async {
    try {
      return await _channel.invokeMethod<bool>('canSign') ?? false;
    } on PlatformException catch (error, stackTrace) {
      _logFailure('canSign', error.code, stackTrace);
      return false;
    } on MissingPluginException catch (error, stackTrace) {
      _logFailure('canSign', error.runtimeType.toString(), stackTrace);
      return false;
    }
  }

  Future<String> createKey({bool replaceExisting = false}) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'createKey',
        {'replaceExisting': replaceExisting},
      );
      final publicKey = result?['publicKey'];
      if (publicKey is! String || publicKey.isEmpty) {
        throw PlatformException(
          code: 'KEY_CREATION_FAILED',
          message: 'A device signing key could not be created.',
        );
      }
      return publicKey;
    } on PlatformException catch (error, stackTrace) {
      _logFailure('createKey', error.code, stackTrace);
      throw Exception(_messageFor(error));
    } on MissingPluginException catch (error, stackTrace) {
      _logFailure('createKey', error.runtimeType.toString(), stackTrace);
      throw Exception(
        'Secure device signing is unavailable. Restart the app and try again.',
      );
    }
  }

  Future<String> sign(String message) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('sign', {
        'message': message,
      });
      final signature = result?['signature'];
      if (signature is! String || signature.isEmpty) {
        throw PlatformException(
          code: 'SIGNING_FAILED',
          message: 'Biometric signing did not complete.',
        );
      }
      return signature;
    } on PlatformException catch (error, stackTrace) {
      _logFailure('sign', error.code, stackTrace);
      throw Exception(_messageFor(error));
    } on MissingPluginException catch (error, stackTrace) {
      _logFailure('sign', error.runtimeType.toString(), stackTrace);
      throw Exception(
        'Secure biometric signing is unavailable. Restart the app and try again.',
      );
    }
  }

  void _logFailure(String operation, String code, StackTrace stackTrace) {
    if (!kDebugMode) return;
    developer.log(
      '$operation failed ($code).',
      name: 'DeviceSecurityService',
      stackTrace: stackTrace,
    );
  }

  String _messageFor(PlatformException error) {
    return switch (error.code) {
      'BIOMETRIC_CANCELLED' => 'Biometric confirmation was cancelled. No secure request was submitted.',
      'BIOMETRIC_NOT_ENROLLED' => 'Set up a strong fingerprint or face biometric in Android Settings, then try again.',
      'BIOMETRIC_UNAVAILABLE' => 'Strong biometric authentication is unavailable. Try again later or use a supported device.',
      'BIOMETRIC_LOCKOUT' =>
        'Biometric authentication is temporarily locked. Wait and try again.',
      'BIOMETRIC_LOCKOUT_PERMANENT' => 'Biometric authentication is locked. Unlock the device with its screen lock, then try again.',
      'DEVICE_NOT_ENROLLED' => 'This device has no secure signing key. Open Profile > Settings > Device Security to register it or contact your administrator for recovery.',
      'KEY_INVALIDATED' => 'The device signing key is no longer available. Contact your administrator for secure device recovery.',
      'BIOMETRIC_FAILED' =>
        'Biometric authentication could not be completed. Try again.',
      'KEY_CREATION_FAILED' => 'A secure signing key could not be created. Check your biometric setup and try again.',
      'INVALID_MESSAGE' => 'The secure request could not be signed. Try again.',
      _ => 'Secure device signing failed. No request was submitted. Try again; if it continues, contact your administrator.',
    };
  }
}
