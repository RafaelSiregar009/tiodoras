import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile_model.dart';
import '../repositories/auth_repository.dart';
import '../services/fcm_service.dart';

final authRepoProvider = Provider((ref) => AuthRepository());

// FIX (fitur baru): dipakai SplashScreen untuk tahu kapan pengecekan sesi
// yang tersimpan (ProfileNotifier._init()) selesai, supaya app bisa
// langsung diarahkan ke dashboard yang benar tanpa perlu login ulang setiap
// kali dibuka — sebelumnya app SELALU mulai dari halaman login walau sesi
// Supabase-nya sendiri sebenarnya sudah otomatis tersimpan.
final authInitializingProvider = StateProvider<bool>((ref) => true);

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileModel?>(
  (ref) => ProfileNotifier(ref, ref.read(authRepoProvider)),
);

class ProfileNotifier extends StateNotifier<ProfileModel?> {
  final Ref _ref;
  final AuthRepository _repo;
  // FIX (Round G): tombol logout di dashboard tidak dijaga dari tap
  // berulang — tap 2-3x sebelum layar sempat pindah ke halaman login
  // memicu beberapa panggilan signOut() BERSAMAAN (terlihat di log:
  // "Signing out user..." muncul 3x berturut-turut), yang di Windows
  // desktop membuat aplikasi crash total ("Lost connection to device").
  // Flag ini membuat tap kedua/ketiga selagi logout masih berjalan
  // menjadi no-op.
  bool _loggingOut = false;

  ProfileNotifier(this._ref, this._repo) : super(null) {
    _init();
  }

  Future<void> _init() async {
    try {
      state = await _repo.getCurrentProfile();
      // FIX (fitur baru): sesi admin yang masih tersimpan dari sebelumnya
      // (buka app lagi tanpa logout) tetap harus daftar ulang FCM token —
      // bukan cuma saat login manual — supaya notifikasi tetap jalan.
      _registerFcmIfAdmin();
    } catch (_) {
      // FIX: kalau pengecekan sesi tersimpan gagal (mis. token sudah tidak
      // valid lagi, atau baris profil-nya sudah dihapus) — anggap saja
      // belum login, jangan sampai app macet selamanya di splash screen.
      state = null;
    } finally {
      // FIX (fitur baru): apa pun hasilnya (ada sesi tersimpan atau tidak),
      // SplashScreen menunggu flag ini sebelum memutuskan mau diarahkan ke
      // halaman login atau langsung ke dashboard.
      _ref.read(authInitializingProvider.notifier).state = false;
    }
  }

  Future<String> login(String email, String password) async {
    final profile = await _repo.login(email, password);
    state = profile;
    _registerFcmIfAdmin();
    return profile.role;
  }

  /// FIX (fitur baru): push notification pengajuan pelunasan/perpanjangan
  /// hanya relevan untuk admin (yang menyetujui pengajuan), jadi hanya
  /// admin yang device token-nya didaftarkan. Tidak di-await dari
  /// pemanggilnya (login/_init) supaya proses login tidak ikut lambat
  /// menunggu setup notifikasi.
  void _registerFcmIfAdmin() {
    final profile = state;
    if (profile != null && profile.role == 'admin') {
      FcmService.registerForAdmin(_repo);
    }
  }

  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      await _repo.logout();
      state = null;
    } finally {
      _loggingOut = false;
    }
  }

  /// FIX (fitur baru): dipanggil setelah admin/petugas mengganti foto
  /// profil sendiri, supaya tampilan langsung ter-update tanpa perlu
  /// logout-login ulang.
  void updateAvatarLocally(String? avatarUrl) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(avatarUrl: avatarUrl);
  }
}
