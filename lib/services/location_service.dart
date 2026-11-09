import 'package:geolocator/geolocator.dart';
import 'package:safe_device/safe_device.dart';

class LocationService {
  Future<Map<String, dynamic>> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception(
        'Turn on location services before recording field activity.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required for field activity.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    final isMocked = position.isMocked || await SafeDevice.isMockLocation;
    final isRooted = await SafeDevice.isJailBroken;
    final isEmulator = !await SafeDevice.isRealDevice;

    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'captured_at': position.timestamp.toUtc().toIso8601String(),
      'is_mocked': isMocked,
      'is_rooted': isRooted,
      'is_emulator': isEmulator,
    };
  }
}
