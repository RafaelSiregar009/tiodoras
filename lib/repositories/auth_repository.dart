import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_model.dart';

class AuthRepository {
  final _supabase = Supabase.instance.client;

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

  /// FIX (fitur baru): admin mengganti foto profil MILIK SENDIRI. Update
  /// langsung ke tabel profiles (bukan lewat Edge Function manage-petugas
  /// — itu khusus mengelola akun PETUGAS) — diizinkan oleh RLS policy
  /// "Admin can update own profile" (lihat migrasi
  /// 20260909_add_avatar_support.sql) yang sengaja dibatasi hanya untuk
  /// baris admin milik sendiri, supaya petugas tidak bisa mengubah baris
  /// profil sendiri lewat jalur ini.
  Future<void> updateOwnAvatar(String avatarUrl) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) throw Exception('Belum login');
    await _supabase
        .from('profiles')
        .update({'avatar_url': avatarUrl})
        .eq('id', uid);
  }

  /// FIX (fitur baru): simpan FCM device token milik admin yang sedang
  /// login, dipakai server (Edge Function notify-admin-pengajuan) untuk
  /// mengirim push notification saat ada pengajuan pelunasan/perpanjangan.
  /// Sama seperti updateOwnAvatar() — hanya bisa update baris milik sendiri
  /// (dijaga RLS policy "Admin can update own profile"), jadi aman dipanggil
  /// dari sisi client tanpa service_role.
  Future<void> saveFcmToken(String token) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    await _supabase
        .from('profiles')
        .update({'fcm_token': token})
        .eq('id', uid);
  }
}
