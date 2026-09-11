import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_model.dart';
import '../services/device_service.dart';

class AuthRepository {
  final _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<ProfileModel> login(String email, String password) async {
    final res = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final uid = res.user!.id;
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('id', uid)
        .single();
    return ProfileModel.fromMap(data);
  }

  Future<void> logout() async {
    await _supabase.auth.signOut();
  }

  Future<ProfileModel?> getCurrentProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .single();
    return ProfileModel.fromMap(data);
  }

  Future<void> updateOwnAvatar(String avatarUrl) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Belum login');
    await _supabase
        .from('profiles')
        .update({'avatar_url': avatarUrl})
        .eq('id', uid);
  }

  Future<void> saveFcmToken(String token) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    await _supabase.from('profiles').update({'fcm_token': token}).eq('id', uid);
  }

  // ── 1 AKUN 1 PERANGKAT ─────────────────────────────────────────────────

  /// Ikat perangkat ini, atau minta verifikasi. Return: 'bound'|'need_verification'.
  Future<String> bindOrRequestDevice() async {
    final deviceId = await DeviceService.getDeviceId();
    final res = await _supabase.rpc(
      'bind_or_request_device',
      params: {'p_device_id': deviceId, 'p_label': DeviceService.deviceLabel},
    );
    return res.toString();
  }

  /// Perangkat baru verifikasi kode. Return: 'ok'|'wrong_code'|'expired'|'not_found'.
  Future<String> verifyDeviceTakeover(String code) async {
    final deviceId = await DeviceService.getDeviceId();
    final res = await _supabase.rpc(
      'verify_device_takeover',
      params: {'p_new_device_id': deviceId, 'p_code': code.trim()},
    );
    return res.toString();
  }

  /// Perangkat lama ambil kode utk ditunjukkan ke perangkat baru.
  Future<Map<String, dynamic>?> getTakeoverCode() async {
    final deviceId = await DeviceService.getDeviceId();
    final res = await _supabase.rpc(
      'get_takeover_code',
      params: {'p_device_id': deviceId},
    );
    if (res is List && res.isNotEmpty) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    return null;
  }

  /// Apakah perangkat INI masih terikat ke akun (dipakai saat buka app).
  Future<bool> isThisDeviceBound() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;
    final deviceId = await DeviceService.getDeviceId();
    final data = await _supabase
        .from('profiles')
        .select('device_id')
        .eq('id', uid)
        .maybeSingle();
    final bound = data?['device_id'] as String?;
    if (bound == null) {
      // Akun belum pernah diikat (mis. data lama / habis di-reset admin) → ikat.
      await bindOrRequestDevice();
      return true;
    }
    return bound == deviceId;
  }

  /// Lepas ikatan perangkat saat logout normal.
  Future<void> releaseDevice() async {
    await _supabase.rpc('release_device');
  }

  /// Admin mereset perangkat sebuah akun (HP hilang).
  Future<void> adminResetDevice(String userId) async {
    await _supabase.rpc('admin_reset_device', params: {'p_user_id': userId});
  }

  /// Realtime baris profil sendiri — utk deteksi takeover / ditendang.
  Stream<List<Map<String, dynamic>>> watchOwnProfile(String uid) {
    return _supabase.from('profiles').stream(primaryKey: ['id']).eq('id', uid);
  }
}
