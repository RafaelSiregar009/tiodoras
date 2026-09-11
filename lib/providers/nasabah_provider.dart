import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nasabah_model.dart';
import '../models/profile_model.dart';
import '../repositories/nasabah_repository.dart';
import 'auth_provider.dart';

final nasabahRepoProvider = Provider((ref) => NasabahRepository());

// FIX BUG: seluruh provider di bawah ini memanggil
// `_supabase.auth.currentUser!.id` DI DALAM repository, tapi Riverpod tidak
// tahu provider ini "bergantung" pada siapa yang sedang login — karena
// dependency-nya cuma nasabahRepoProvider yang tidak pernah berubah.
// Akibatnya kalau ganti akun (logout lalu login akun lain) TANPA full
// restart aplikasi, data lama milik akun sebelumnya masih ke-cache dan
// tetap ditampilkan (atau sebaliknya, data baru belum muncul). Ini
// penyebab: (1) dashboard petugas tampak kosong padahal py sudah punya
// nasabah, dan (3) antrean "menunggu persetujuan" milik satu petugas malah
// muncul di dashboard petugas lain.
//
// Perbaikan: setiap provider yang datanya bergantung pada user yang sedang
// login WAJIB `ref.watch(profileProvider)` supaya Riverpod otomatis
// membuang cache & mengambil ulang data setiap kali status login berubah
// (login/logout/ganti akun).

// ── REALTIME ──────────────────────────────────────────────────────────────

/// Admin: nasabah baru menunggu persetujuan (status 'pending')
final antreianAdminStreamProvider = StreamProvider<List<NasabahModel>>((ref) {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).streamAntreianAdmin();
});

/// Admin: pelunasan menunggu persetujuan (status 'pengajuan_pelunasan')
final pelunasanAdminStreamProvider = StreamProvider<List<NasabahModel>>((ref) {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).streamPelunasanAdmin();
});

/// Admin: perpanjangan menunggu persetujuan
final perpanjanganAdminStreamProvider = StreamProvider<List<NasabahModel>>((
  ref,
) {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).streamPerpanjanganAdmin();
});

/// Legacy (gudang dihapus) — dibiarkan ada agar screens/gudang lama tetap
/// bisa kompilasi, tidak lagi dipakai di alur utama.
final antreianGudangStreamProvider = StreamProvider<List<NasabahModel>>((ref) {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).streamAntreianGudang();
});

final pelunasanGudangStreamProvider = StreamProvider<List<NasabahModel>>((ref) {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).streamPelunasanGudang();
});

// ── FUTURE (one-shot + invalidate) ───────────────────────────────────────

/// FIX: sekarang realtime (StreamProvider) — lihat
/// streamNasabahAktifPetugas() di repository untuk alasannya. Tipe yang
/// dikembalikan (AsyncValue<List<NasabahModel>>) tetap sama seperti
/// FutureProvider sebelumnya, jadi semua ref.watch()/ref.invalidate() yang
/// sudah ada tetap kompatibel tanpa perlu diubah.
final nasabahPetugasProvider = StreamProvider<List<NasabahModel>>((ref) {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).streamNasabahAktifPetugas();
});

/// FIX: sekarang realtime (StreamProvider) — lihat streamAntreianPetugas()
/// di repository. Sebelumnya FutureProvider + ref.invalidate() manual:
/// status 'rejected' hasil tolak admin baru terlihat di dashboard/halaman
/// status petugas setelah refresh manual.
final antreianNasabahProvider = StreamProvider<List<NasabahModel>>((ref) {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).streamAntreianPetugas();
});

/// FIX: sekarang realtime (StreamProvider) — lihat streamAllNasabahAktif()
/// di repository. Sebelumnya admin approve nasabah baru/pelunasan/
/// perpanjangan butuh refresh manual supaya dashboard admin, "Semua
/// Nasabah", dan "Nasabah per Petugas" ter-update.
final allNasabahProvider = StreamProvider<List<NasabahModel>>((ref) {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).streamAllNasabahAktif();
});

/// Riwayat pelunasan yang sudah final disetujui admin — realtime, lihat
/// streamNasabahLunas() di repository.
final nasabahLunasProvider = StreamProvider<List<NasabahModel>>((ref) {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).streamNasabahLunas();
});

final antreianAdminProvider = FutureProvider<List<NasabahModel>>((ref) async {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).getAntreianAdmin();
});

final antreianGudangProvider = FutureProvider<List<NasabahModel>>((ref) async {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).getAntreianGudang();
});

final allAgunanProvider = FutureProvider<List<NasabahModel>>((ref) async {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).getAllAgunan();
});

final allPetugasProvider = FutureProvider<List<ProfileModel>>((ref) async {
  ref.watch(profileProvider);
  return ref.watch(nasabahRepoProvider).getAllPetugas();
});

/// FIX (fitur baru): biaya perpanjangan yang sudah disetujui admin milik
/// nasabah-nasabah seorang petugas — dipakai menghitung "Storting" per
/// bulan di halaman detail petugas (Ringkasan). FutureProvider biasa
/// (bukan realtime) karena perpanjangan yang sudah 'approved' bersifat
/// riwayat/final, cukup di-refresh lewat pull-to-refresh atau saat admin
/// baru saja menyetujui perpanjangan (lihat ref.invalidate() di
/// admin_approval.dart).
final biayaPerpanjanganApprovedProvider =
    FutureProvider.family<
      List<({String nasabahId, int biaya, DateTime approvedAt})>,
      String
    >((ref, petugasId) async {
      ref.watch(profileProvider);
      return ref
          .watch(nasabahRepoProvider)
          .getBiayaPerpanjanganApproved(petugasId);
    });

// ── JATUH TEMPO ───────────────────────────────────────────────────────────
//
// FIX (Round C): kedua provider di bawah dulu FutureProvider SEKALI-JALAN —
// dipanggil sekali saat halaman dibuka lalu tidak pernah tahu ada
// perubahan lagi. Di web/debug ini "tersamar" karena ctrl+r (hot
// restart) tanpa sadar sering dipakai buat lihat perubahan, tapi begitu
// aplikasi dibuild jadi APK Android tidak ada lagi ctrl+r — halaman
// "Nasabah Jatuh Tempo" jadi kelihatan macet/basi sampai aplikasi
// ditutup-buka ulang.
//
// Sekarang diturunkan langsung dari stream realtime yang sudah ada
// (allNasabahProvider utk admin, nasabahPetugasProvider utk petugas) dan
// disaring di client memakai getter isJatuhTempo/akanJatuhTempo di
// NasabahModel — jadi otomatis ter-update kapan pun ada nasabah
// baru/berubah/lunas, TANPA perlu refresh manual sama sekali, sama
// seperti layar-layar lain yang sudah realtime.
//
// refreshStatusJatuhTempo() (update kolom `status` di DB) tetap dipanggil
// sekali secara fire-and-forget (tidak diawait, tidak memblokir UI) lewat
// _refreshStatusJatuhTempoOnceProvider supaya kolom itu tetap berguna utk
// kebutuhan lain (laporan/SQL manual) — tapi UI di app ini TIDAK lagi
// bergantung padanya; status jatuh-tempo/H-2 100% dihitung di client dari
// tanggal, jadi selalu akurat detik itu juga.
final _refreshStatusJatuhTempoOnceProvider = Provider<void>((ref) {
  // ignore: discarded_futures
  ref.watch(nasabahRepoProvider).refreshStatusJatuhTempo();
});

/// ADMIN: semua nasabah jatuh tempo ATAU akan jatuh tempo (H-2) — realtime,
/// diturunkan dari allNasabahProvider.
final nasabahJatuhTempoProvider = Provider<AsyncValue<List<NasabahModel>>>((
  ref,
) {
  ref.watch(_refreshStatusJatuhTempoOnceProvider);
  final async = ref.watch(allNasabahProvider);
  return async.whenData(
    (list) =>
        list.where((n) => n.isJatuhTempo || n.akanJatuhTempo).toList()
          ..sort((a, b) => a.tanggalJatuhTempo.compareTo(b.tanggalJatuhTempo)),
  );
});

/// PETUGAS: hanya miliknya yg jatuh tempo ATAU akan jatuh tempo (H-2) —
/// realtime, diturunkan dari nasabahPetugasProvider.
final nasabahJatuhTempoPetugasProvider =
    Provider<AsyncValue<List<NasabahModel>>>((ref) {
      ref.watch(_refreshStatusJatuhTempoOnceProvider);
      final async = ref.watch(nasabahPetugasProvider);
      return async.whenData(
        (list) =>
            list.where((n) => n.isJatuhTempo || n.akanJatuhTempo).toList()
              ..sort(
                (a, b) => a.tanggalJatuhTempo.compareTo(b.tanggalJatuhTempo),
              ),
      );
    });
