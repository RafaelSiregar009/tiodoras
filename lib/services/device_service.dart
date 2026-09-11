import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identitas perangkat lokal untuk aturan "1 akun 1 perangkat".
class DeviceService {
  static const _kDeviceIdKey = 'device_id_v1';
  static String? _cachedId;

  /// ID unik perangkat ini — dibuat sekali lalu disimpan permanen di HP.
  static Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceIdKey);
    if (id == null) {
      final rnd = Random.secure();
      final suffix = List.generate(
        8,
        (_) => rnd.nextInt(16).toRadixString(16),
      ).join();
      id = 'dev_${DateTime.now().millisecondsSinceEpoch}_$suffix';
      await prefs.setString(_kDeviceIdKey, id);
    }
    _cachedId = id;
    return id;
  }

  /// Label sederhana untuk ditampilkan ke user (mis. "android").
  static String get deviceLabel => kIsWeb ? 'web' : defaultTargetPlatform.name;
}
