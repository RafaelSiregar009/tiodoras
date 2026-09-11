import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/nasabah_model.dart';
import '../models/profile_model.dart';

class NasabahRepository {
  final _supabase = Supabase.instance.client;

  // ── REALTIME STREAMS ─────────────────────────────────────────────────────

  /// Subscribe ke seluruh perubahan pada tabel `nasabah`, kemudian saring di
  /// klien. Filter `.eq()` pada stream Supabase hanya dipakai saat query awal
  /// pada beberapa konfigurasi Realtime, sehingga sebuah item yang statusnya
  /// berubah bisa tetap tertinggal di antrean UI. Penyaringan di sini membuat
  /// item langsung keluar dari antrean saat statusnya diperbarui.
  Stream<List<NasabahModel>> _streamNasabah() {
    return _supabase
        .from('nasabah')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(NasabahModel.fromMap).toList());
  }

  /// FIX: alur gudang dihapus — pengajuan nasabah baru dari petugas kini
  /// langsung masuk antrean persetujuan admin (status 'pending'), tanpa
  /// menunggu konfirmasi gudang lagi.
  Stream<List<NasabahModel>> streamAntreianAdmin() {
    return _streamNasabah().map(
      (list) => list.where((n) => n.statusApproval == 'pending').toList(),
    );
  }

  Stream<List<NasabahModel>> streamPelunasanGudang() {
    return _streamNasabah().map(
      (list) => list
          .where((n) => n.statusPelunasan == 'pengajuan_pelunasan')
          .toList(),
    );
  }

  /// FIX: alur gudang dihapus — pengajuan pelunasan (tebus) dari petugas
  /// kini langsung masuk antrean persetujuan admin (status
  /// 'pengajuan_pelunasan'), tanpa menunggu konfirmasi barang keluar gudang.
  Stream<List<NasabahModel>> streamPelunasanAdmin() {
    return _streamNasabah().map(
      (list) => list
          .where((n) => n.statusPelunasan == 'pengajuan_pelunasan')
          .toList(),
    );
  }

  Stream<List<NasabahModel>> streamPerpanjanganAdmin() {
    return _streamNasabah().map(
      (list) => list
          .where((n) => n.statusPelunasan == 'pengajuan_perpanjangan')
          .toList(),
    );
  }

  /// ADMIN: seluruh nasabah yang sudah aktif (approved_admin) — realtime.
  ///
  /// FIX: dulu getAllNasabah() (Future) dipakai oleh dashboard admin, daftar
  /// semua nasabah, dan riwayat lunas — semuanya hanya ter-update lewat
  /// ref.invalidate() manual. Begitu admin approve nasabah baru / pelunasan
  /// / perpanjangan dari tab Persetujuan, ketiga layar ini TIDAK tahu ada
  /// perubahan sampai widget-nya di-refresh manual (tarik ke bawah / pindah
  /// tab lalu kembali). Sekarang realtime, sama seperti antrean admin.
  Stream<List<NasabahModel>> streamAllNasabahAktif() {
    return _streamNasabah().map(
      (list) =>
          list.where((n) => n.statusApproval == 'approved_admin').toList(),
    );
  }

  /// ADMIN: riwayat pelunasan final — realtime (lihat streamAllNasabahAktif
  /// untuk alasan kenapa ini perlu jadi stream).
  Stream<List<NasabahModel>> streamNasabahLunas() {
    return _streamNasabah().map(
      (list) => list
          .where(
            (n) => n.statusApproval == 'approved_admin' && n.status == 'lunas',
          )
          .toList(),
    );
  }

  /// ADMIN: nasabah milik satu petugas tertentu (halaman detail per
  /// petugas) — realtime. FIX: sebelumnya nasabahByPetugasProvider adalah
  /// FutureProvider.family TERPISAH dari allNasabahProvider — meng-invalidate
  /// allNasabahProvider di layar Persetujuan sama sekali tidak berpengaruh
  /// ke provider ini, sehingga nasabah baru yang baru saja disetujui admin
  /// tidak pernah muncul di halaman "Nasabah: <petugas>" tanpa refresh manual
  /// (dan bahkan setelah refresh manual pun baru ter-update).
  Stream<List<NasabahModel>> streamNasabahByPetugas(String petugasId) {
    return _streamNasabah().map(
      (list) => list
          .where(
            (n) =>
                n.petugasId == petugasId &&
                n.statusApproval == 'approved_admin',
          )
          .toList(),
    );
  }

  /// PETUGAS: status pengajuan nasabah baru miliknya sendiri (pending /
  /// approved_gudang legacy / rejected) — realtime.
  ///
  /// FIX: sebelumnya getAntreianNasabah() (Future) hanya ter-update lewat
  /// ref.invalidate() manual. Akibatnya begitu admin menekan "Tolak", status
  /// 'rejected' baru terlihat di dashboard/halaman status petugas setelah
  /// refresh manual — kadang malah tidak pernah terlihat sama sekali kalau
  /// petugas tidak sempat me-refresh.
  Stream<List<NasabahModel>> streamAntreianPetugas() {
    // FIX (Round F): sebelumnya `currentUser!.id` — kalau stream ini
    // di-recreate TEPAT saat/tepat setelah logout (profileProvider yang
    // di-watch provider ini berubah jadi null, memicu rebuild, sementara
    // widget dashboard masih sempat sekali render sebelum benar-benar
    // pindah ke halaman login), currentUser sudah null duluan dan `!`
    // melempar "Null check operator used on a null value" — muncul di
    // layar sebagai "Error: Unexpected null value." tepat saat menekan
    // tombol logout. Kembalikan stream kosong kalau belum/sudah tidak ada
    // user login, alih-alih crash.
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return Stream.value(const []);
    return _streamNasabah().map(
      (list) => list
          .where(
            (n) =>
                n.petugasId == uid &&
                (n.statusApproval == 'pending' ||
                    n.statusApproval == 'approved_gudang' ||
                    n.statusApproval == 'rejected'),
          )
          .toList(),
    );
  }

  // ── MAINTENANCE ──────────────────────────────────────────────────────────

  /// Tandai nasabah yang jatuh temponya sudah lewat sebagai 'jatuh_tempo'.
  ///
  /// FIX: sebelumnya tidak ada satupun kode yang mengubah status ke
  /// 'jatuh_tempo', padahal getNasabahJatuhTempo() memfilter status ini —
  /// akibatnya halaman Jatuh Tempo & badge di dashboard selalu kosong.
  /// Panggil method ini di provider sebelum query jatuh tempo / daftar utama,
  /// supaya status selalu ter-update sebelum ditampilkan.
  Future<void> refreshStatusJatuhTempo() async {
    final hariIni = DateTime.now().toIso8601String().split('T')[0];
    await _supabase
        .from('nasabah')
        .update({'status': 'jatuh_tempo'})
        .eq('status_approval', 'approved_admin')
        .eq('status', 'berjalan')
        .lt('tanggal_jatuh_tempo', hariIni);
  }

  // ── PETUGAS ──────────────────────────────────────────────────────────────

  /// FIX: dulu "Nasabah Aktif" milik petugas diambil sekali pakai
  /// getNasabahPetugas() (Future) — begitu admin approve dari sesi/browser
  /// lain, dashboard petugas tidak pernah tahu sampai di-refresh manual.
  /// Sekarang pakai realtime stream (sama seperti antrean admin) supaya
  /// otomatis update begitu status_approval berubah jadi approved_admin.
  Stream<List<NasabahModel>> streamNasabahAktifPetugas() {
    // FIX (Round F): lihat komentar di streamAntreianPetugas() — sama
    // persis, jaga-jaga terhadap currentUser null saat logout supaya
    // tidak crash "Unexpected null value".
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return Stream.value(const []);
    return _streamNasabah().map(
      (list) => list
          .where(
            (n) => n.petugasId == uid && n.statusApproval == 'approved_admin',
          )
          .toList(),
    );
  }

  Future<List<NasabahModel>> getNasabahPetugas() async {
    final uid = _supabase.auth.currentUser!.id;
    final data = await _supabase
        .from('nasabah')
        .select('*, profiles(nama)')
        .eq('petugas_id', uid)
        .eq('status_approval', 'approved_admin')
        .order('created_at', ascending: false);
    return (data as List).map((e) => NasabahModel.fromMap(e)).toList();
  }

  /// Hanya nasabah jatuh tempo milik petugas yang login
  Future<List<NasabahModel>> getNasabahJatuhTempoPetugas() async {
    final uid = _supabase.auth.currentUser!.id;
    final data = await _supabase
        .from('nasabah')
        .select('*, profiles(nama)')
        .eq('petugas_id', uid)
        .eq('status_approval', 'approved_admin')
        .eq('status', 'jatuh_tempo')
        .order('tanggal_jatuh_tempo');
    return (data as List).map((e) => NasabahModel.fromMap(e)).toList();
  }

  Future<List<NasabahModel>> getAntreianNasabah() async {
    final uid = _supabase.auth.currentUser!.id;
    final data = await _supabase
        .from('nasabah')
        .select()
        .eq('petugas_id', uid)
        .inFilter('status_approval', ['pending', 'approved_gudang', 'rejected'])
        .order('created_at', ascending: false);
    return (data as List).map((e) => NasabahModel.fromMap(e)).toList();
  }

  // ── ADMIN ────────────────────────────────────────────────────────────────

  Future<List<NasabahModel>> getAllNasabah() async {
    final data = await _supabase
        .from('nasabah')
        .select('*, profiles(nama)')
        .eq('status_approval', 'approved_admin')
        .order('created_at', ascending: false);
    return (data as List).map((e) => NasabahModel.fromMap(e)).toList();
  }

  /// Riwayat khusus nasabah yang pelunasannya telah disetujui admin.
  Future<List<NasabahModel>> getNasabahLunas() async {
    final data = await _supabase
        .from('nasabah')
        .select('*, profiles(nama)')
        .eq('status_approval', 'approved_admin')
        .eq('status', 'lunas')
        .order('created_at', ascending: false);
    return (data as List).map((e) => NasabahModel.fromMap(e)).toList();
  }

  /// FIX: alur gudang dihapus — dulu method ini memfilter 'approved_gudang'
  /// (status yang sudah tidak pernah dipakai lagi), sehingga selalu
  /// mengembalikan list kosong. Disamakan dengan streamAntreianAdmin().
  Future<List<NasabahModel>> getAntreianAdmin() async {
    final data = await _supabase
        .from('nasabah')
        .select('*, profiles(nama)')
        .eq('status_approval', 'pending')
        .order('created_at', ascending: false);
    return (data as List).map((e) => NasabahModel.fromMap(e)).toList();
  }

  Future<List<ProfileModel>> getAllPetugas() async {
    final data = await _supabase
        .from('profiles')
        .select()
        .eq('role', 'petugas');
    return (data as List).map((e) => ProfileModel.fromMap(e)).toList();
  }

  /// Semua nasabah jatuh tempo (untuk admin)
  Future<List<NasabahModel>> getNasabahJatuhTempo() async {
    final data = await _supabase
        .from('nasabah')
        .select('*, profiles(nama)')
        .eq('status', 'jatuh_tempo')
        .eq('status_approval', 'approved_admin')
        .order('tanggal_jatuh_tempo');
    return (data as List).map((e) => NasabahModel.fromMap(e)).toList();
  }

  // ── GUDANG ───────────────────────────────────────────────────────────────

  /// Cari agunan aktif di gudang berdasarkan kode unik.
  /// Hanya mengembalikan agunan yang masih berjalan (bukan lunas).
  Future<NasabahModel?> cariAgunanByKode(String kode) async {
    final data = await _supabase
        .from('nasabah')
        .select('*, profiles(nama)')
        .eq('kode_nasabah', kode.toUpperCase())
        .eq('status_approval', 'approved_admin')
        .neq('status', 'lunas')
        .maybeSingle();
    if (data == null) return null;
    return NasabahModel.fromMap(data);
  }

  // ── AKSI ─────────────────────────────────────────────────────────────────

  Future<void> tambahNasabah({
    required String nama,
    String? alamat,
    String? noHp,
    required int nominalPinjaman,
    required String jenisAgunan,
    String? detailAgunan,
    required int jumlahPelunasan,
    required DateTime tanggalMasuk,
    required DateTime tanggalJatuhTempo,
    Uint8List? foto,
    Uint8List? fotoNasabah,
  }) async {
    final uid = _supabase.auth.currentUser!.id;
    final ts = DateTime.now().millisecondsSinceEpoch;

    Future<String?> upload(Uint8List? bytes, String label) async {
      if (bytes == null) return null;
      final fileName = '${uid}_${label}_$ts.jpg';
      // FIX: percobaan pertama upload ke Storage kadang gagal dengan 403
      // "row-level security policy" tepat setelah petugas baru saja login
      // (terutama akun yang baru dibuat admin) — sesi/token belum
      // sepenuhnya "siap" dipakai request Storage yang pertama walau UI
      // sudah terlihat login. Percobaan berikutnya (beberapa ratus ms
      // kemudian) biasanya langsung berhasil begitu token sudah terpasang,
      // jadi retry singkat di sini membuat pengguna tidak perlu klik ulang
      // secara manual.
      const maxAttempts = 3;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          await _supabase.storage
              .from('agunan-photos')
              .uploadBinary(
                fileName,
                bytes,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          return _supabase.storage.from('agunan-photos').getPublicUrl(fileName);
        } on StorageException catch (e) {
          final isAuthGlitch =
              e.statusCode == '403' ||
              e.message.toLowerCase().contains('row-level security');
          if (!isAuthGlitch || attempt == maxAttempts) rethrow;
          await Future.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
      return null; // tidak pernah tercapai
    }

    // Dua foto terpisah: foto agunan (barang jaminan) dan foto nasabah
    // (identitas/wajah peminjam).
    final fotoUrl = await upload(foto, 'agunan');
    final fotoNasabahUrl = await upload(fotoNasabah, 'nasabah');

    final payload = {
      'petugas_id': uid,
      'nama': nama,
      'alamat': alamat,
      'no_hp': noHp,
      'nominal_pinjaman': nominalPinjaman,
      'jenis_agunan': jenisAgunan,
      'detail_agunan': detailAgunan,
      'jumlah_pelunasan': jumlahPelunasan,
      'tanggal_masuk': tanggalMasuk.toIso8601String().split('T')[0],
      'tanggal_jatuh_tempo': tanggalJatuhTempo.toIso8601String().split('T')[0],
      'foto_url': fotoUrl,
      'foto_nasabah_url': fotoNasabahUrl,
    };

    // FIX (Round C): `kode_nasabah` dibuat OTOMATIS oleh trigger di
    // database, bukan oleh Flutter — kolom ini sengaja tidak dikirim di
    // atas. Ini BUKAN masalah khusus akun yang dibuat lewat dashboard
    // admin: trigger lama menghitung nomor kode berikutnya dengan query
    // yang ikut disaring oleh Row Level Security, sehingga akun petugas
    // MANAPUN — dibuat lewat dashboard ataupun SQL editor — bisa
    // bertabrakan kode persis di nasabah PERTAMA yang dia tambahkan
    // (lihat migrasi supabase/migrations/*_fix_kode_nasabah*.sql untuk
    // perbaikan di sisi database). Sebagai jaring pengaman tambahan di
    // sisi app, kalau insert gagal spesifik karena kode_nasabah bentrok
    // (unique_violation / kode Postgres 23505), coba lagi otomatis
    // beberapa kali — trigger akan menghasilkan kode baru setiap kali.
    // FIX (Round D): dinaikkan dari 5 ke 10 — pernah kejadian klik pertama
    // tetap gagal karena ada beberapa baris nasabah "penghalang" berurutan
    // (biasanya bekas data testing lewat SQL Editor) sebelum sequence-nya
    // berhasil lewat semuanya. Lihat juga migrasi
    // 20260911c_reseed_kode_nasabah_seq.sql untuk perbaikan akar masalahnya
    // di sisi database.
    const maxAttempts = 10;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _supabase.from('nasabah').insert(payload);
        return;
      } on PostgrestException catch (e) {
        final isKodeCollision =
            e.code == '23505' && e.message.contains('kode_nasabah');
        if (!isKodeCollision || attempt == maxAttempts) rethrow;
        // lanjut ke percobaan berikutnya — trigger akan generate kode baru
      }
    }
  }

  Future<void> konfirmasiGudang(String nasabahId) async {
    await _supabase
        .from('nasabah')
        .update({
          'status_approval': 'approved_gudang',
          'dikonfirmasi_gudang_at': DateTime.now().toIso8601String(),
        })
        .eq('id', nasabahId);
  }

  Future<void> approveAdmin(String nasabahId) async {
    await _supabase
        .from('nasabah')
        .update({
          'status_approval': 'approved_admin',
          'disetujui_admin_at': DateTime.now().toIso8601String(),
          'status': 'berjalan',
        })
        .eq('id', nasabahId);
  }

  Future<void> tolakNasabah(String nasabahId, String catatan) async {
    await _supabase
        .from('nasabah')
        .update({'status_approval': 'rejected', 'catatan_penolakan': catatan})
        .eq('id', nasabahId);
  }

  /// Admin: tolak pengajuan pelunasan (tebus). Nasabah kembali ke kondisi
  /// normal (masih 'berjalan', bukan lunas) dan catatan alasan disimpan
  /// supaya petugas tahu kenapa ditolak — tampil sebagai banner merah di
  /// dashboard petugas. Petugas bisa mengajukan lagi kapan saja setelahnya.
  Future<void> tolakPelunasan(String nasabahId, String catatan) async {
    await _supabase
        .from('nasabah')
        .update({
          'status_pelunasan': 'ditolak_pelunasan',
          'catatan_penolakan': catatan,
        })
        .eq('id', nasabahId);
  }

  /// Admin: tolak pengajuan perpanjangan. Baris 'pending' di tabel
  /// perpanjangan ikut ditandai 'rejected' supaya riwayat tetap konsisten,
  /// dan nasabah.tanggal_jatuh_tempo TIDAK berubah.
  Future<void> tolakPerpanjangan(String nasabahId, String catatan) async {
    await _supabase
        .from('perpanjangan')
        .update({'status': 'rejected'})
        .eq('nasabah_id', nasabahId)
        .eq('status', 'pending');
    await _supabase
        .from('nasabah')
        .update({
          'status_pelunasan': 'ditolak_perpanjangan',
          'catatan_penolakan': catatan,
        })
        .eq('id', nasabahId);
  }

  /// Petugas: ajukan pelunasan → nunggu gudang konfirmasi barang keluar
  Future<void> ajukanPelunasan(String nasabahId) async {
    await _supabase
        .from('nasabah')
        .update({'status_pelunasan': 'pengajuan_pelunasan'})
        .eq('id', nasabahId);
  }

  /// Gudang: konfirmasi barang keluar → lanjut ke admin
  /// Admin: setujui pelunasan → status lunas
  Future<void> approveAdminPelunasan(String nasabahId) async {
    await _supabase
        .from('nasabah')
        .update({
          'status': 'lunas',
          'status_pelunasan': 'selesai',
          // FIX (fitur baru): catat KAPAN benar-benar lunas — dipakai untuk
          // mengelompokkan "Storting" per bulan di halaman detail petugas
          // (lihat migrasi 20260910_add_monthly_report_support.sql).
          'tanggal_lunas': DateTime.now().toIso8601String(),
        })
        .eq('id', nasabahId);
  }

  /// Petugas: ajukan perpanjangan → tunggu admin
  Future<void> ajukanPerpanjangan({
    required String nasabahId,
    required int nominalPinjaman,
    required DateTime jatuhTempoBaru,
  }) async {
    final biaya = (nominalPinjaman * 0.2).round();
    await _supabase.from('perpanjangan').insert({
      'nasabah_id': nasabahId,
      'biaya_perpanjangan': biaya,
      'jatuh_tempo_baru': jatuhTempoBaru.toIso8601String().split('T')[0],
      'status': 'pending',
    });
    await _supabase
        .from('nasabah')
        .update({'status_pelunasan': 'pengajuan_perpanjangan'})
        .eq('id', nasabahId);
  }

  /// Admin: setujui perpanjangan
  ///
  /// FIX: sebelumnya pakai `.single()` yang MELEMPAR EXCEPTION kalau hasil
  /// query kosong (0 baris) — misalnya karena admin menekan tombol dua kali
  /// (double-tap) sehingga baris 'pending' sudah keburu diubah jadi
  /// 'approved' oleh request pertama. `.maybeSingle()` mengembalikan null
  /// alih-alih melempar exception, sehingga bisa ditangani dengan rapi.
  Future<void> approveAdminPerpanjangan(String nasabahId) async {
    final data = await _supabase
        .from('perpanjangan')
        .select()
        .eq('nasabah_id', nasabahId)
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) {
      throw Exception(
        'Data perpanjangan tidak ditemukan. '
        'Kemungkinan sudah disetujui sebelumnya.',
      );
    }

    final jatuhTempoBaru = data['jatuh_tempo_baru'];

    await _supabase
        .from('perpanjangan')
        .update({
          'status': 'approved',
          // FIX (fitur baru): catat KAPAN perpanjangan ini disetujui —
          // dipakai untuk mengelompokkan biaya perpanjangan ke "Storting"
          // bulan yang tepat di halaman detail petugas (lihat migrasi
          // 20260910_add_monthly_report_support.sql).
          'approved_at': DateTime.now().toIso8601String(),
        })
        .eq('nasabah_id', nasabahId)
        .eq('status', 'pending');

    await _supabase
        .from('nasabah')
        .update({
          'tanggal_jatuh_tempo': jatuhTempoBaru,
          'status': 'berjalan',
          'status_pelunasan': null,
        })
        .eq('id', nasabahId);
  }

  /// FIX (fitur baru): seluruh biaya perpanjangan yang SUDAH disetujui admin
  /// milik nasabah-nasabah seorang petugas — dipakai untuk menghitung
  /// "Storting" per bulan di halaman detail petugas (Ringkasan). Filter
  /// tanggal (bulan mana yang dihitung) dilakukan di sisi Flutter, bukan di
  /// query ini, supaya berpindah bulan di UI tidak perlu roundtrip ke server
  /// setiap kali.
  Future<List<({String nasabahId, int biaya, DateTime approvedAt})>>
  getBiayaPerpanjanganApproved(String petugasId) async {
    final data = await _supabase
        .from('perpanjangan')
        .select(
          'nasabah_id, biaya_perpanjangan, approved_at, nasabah!inner(petugas_id)',
        )
        .eq('status', 'approved')
        .eq('nasabah.petugas_id', petugasId);

    int toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return (data as List)
        .where((row) => row['approved_at'] != null)
        .map(
          (row) => (
            nasabahId: row['nasabah_id'].toString(),
            biaya: toInt(row['biaya_perpanjangan']),
            approvedAt: DateTime.parse(row['approved_at'].toString()),
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> buatSuratJalan(String nasabahId) async {
    final uid = _supabase.auth.currentUser!.id;
    final result = await _supabase
        .from('surat_jalan')
        .insert({'nasabah_id': nasabahId, 'dikonfirmasi_oleh': uid})
        .select()
        .single();
    return result;
  }

  Future<NasabahModel> getNasabahById(String id) async {
    final data = await _supabase
        .from('nasabah')
        .select('*, profiles(nama)')
        .eq('id', id)
        .single();
    return NasabahModel.fromMap(data);
  }

  /// Cari nasabah berdasarkan kode unik (dipakai petugas — semua status).
  ///
  /// FIX: sebelumnya TIDAK difilter per petugas sama sekali — petugas mana
  /// pun bisa menemukan & melihat detail lengkap nasabah milik petugas lain
  /// asal tahu/menebak kodenya. Sesuai aturan "petugas hanya boleh melihat
  /// nasabah yang dia ajukan sendiri", pencarian ini sekarang dibatasi ke
  /// nasabah miliknya sendiri saja.
  Future<NasabahModel?> cariByKode(String kode) async {
    final uid = _supabase.auth.currentUser!.id;
    final data = await _supabase
        .from('nasabah')
        .select('*, profiles(nama)')
        .eq('kode_nasabah', kode.toUpperCase())
        .eq('petugas_id', uid)
        .maybeSingle();
    if (data == null) return null;
    return NasabahModel.fromMap(data);
  }

  // ── KELOLA AKUN PETUGAS (via Edge Function 'manage-petugas') ─────────────
  //
  // FIX: sebelumnya method ini memanggil `_supabase.auth.admin.createUser`
  // langsung dari aplikasi Flutter — ini TIDAK PERNAH bisa berhasil karena
  // operasi admin Supabase Auth wajib pakai service_role key, sementara
  // aplikasi hanya membawa anon key (dan memang tidak boleh membawa
  // service_role key, apalagi di build web, karena siapa pun bisa
  // membacanya dan mendapat akses penuh ke database).
  //
  // Sekarang operasi create/update/delete akun petugas dikirim ke Edge
  // Function `manage-petugas` (lihat supabase/functions/manage-petugas),
  // yang berjalan di server Supabase dan memverifikasi bahwa pemanggilnya
  // benar-benar admin sebelum memakai service_role key di sana.
  Future<Map<String, dynamic>> _callManagePetugas(
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _supabase.functions.invoke(
        'manage-petugas',
        body: body,
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception(
        'Gagal menghubungi server (status ${e.status}). '
        'Pastikan Edge Function "manage-petugas" sudah di-deploy.',
      );
    }
  }

  /// Admin: buat akun petugas baru (login + profil). Return id user baru.
  ///
  /// FIX (fitur baru): `avatarUrl` opsional — kalau admin sudah memilih
  /// foto saat membuat akun, foto itu di-upload dulu ke Storage (lihat
  /// [uploadAvatar]) lalu URL-nya dikirim ke sini supaya langsung tersimpan
  /// di baris profil yang baru dibuat, tidak perlu edit lagi setelahnya.
  Future<String> tambahPetugas({
    required String email,
    required String password,
    required String nama,
    String? avatarUrl,
    // FIX (fitur baru): field profil tambahan petugas — opsional.
    String? noHp,
    String? nik,
  }) async {
    final data = await _callManagePetugas({
      'action': 'create',
      'nama': nama,
      'email': email,
      'password': password,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (noHp != null) 'no_hp': noHp,
      if (nik != null) 'nik': nik,
    });
    return data['id'] as String;
  }

  /// Admin: ubah nama, dan opsional email/password/foto profil/No. HP/NIK
  /// petugas.
  ///
  /// FIX (fitur baru): `noHp` dan `nik` SENGAJA selalu dikirim ke Edge
  /// Function (bukan cuma kalau tidak null seperti email/password/avatar)
  /// — supaya admin bisa mengosongkan field itu kalau memang mau, bukan
  /// cuma bisa mengisi. Edge Function membedakan "field dikirim tapi
  /// kosong" (dikosongkan) dari "field tidak dikirim sama sekali" (tidak
  /// diubah) lewat keberadaan key-nya di body request.
  Future<void> updatePetugas({
    required String id,
    required String nama,
    String? email,
    String? password,
    String? avatarUrl,
    String? noHp,
    String? nik,
  }) async {
    await _callManagePetugas({
      'action': 'update',
      'id': id,
      'nama': nama,
      if (email != null && email.isNotEmpty) 'email': email,
      if (password != null && password.isNotEmpty) 'password': password,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      'no_hp': noHp ?? '',
      'nik': nik ?? '',
    });
  }

  /// FIX (fitur baru): upload foto profil (petugas ATAU admin) ke bucket
  /// Storage 'avatars', return URL publiknya. Dipakai oleh admin baik saat
  /// mengatur foto petugas (lewat dialog Kelola Petugas) maupun foto
  /// dirinya sendiri (lewat avatar di dashboard admin) — upload-nya sendiri
  /// selalu berjalan di sesi admin yang sedang login, jadi tidak butuh
  /// service_role; hanya PENYIMPANAN URL ke baris profil petugas yang tetap
  /// lewat Edge Function manage-petugas (lihat updatePetugas/tambahPetugas),
  /// konsisten dengan alasan kenapa akun petugas dikelola lewat sana.
  Future<String> uploadAvatar(Uint8List bytes, String labelForFileName) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeLabel = labelForFileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final fileName = 'avatar_${safeLabel}_$ts.jpg';
    // FIX: sama seperti retry di tambahNasabah() — percobaan pertama upload
    // Storage kadang gagal 403 RLS tepat setelah sesi baru login.
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _supabase.storage
            .from('avatars')
            .uploadBinary(
              fileName,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        return _supabase.storage.from('avatars').getPublicUrl(fileName);
      } on StorageException catch (e) {
        final isAuthGlitch =
            e.statusCode == '403' ||
            e.message.toLowerCase().contains('row-level security');
        if (!isAuthGlitch || attempt == maxAttempts) rethrow;
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    throw Exception('Gagal mengunggah foto setelah beberapa percobaan');
  }

  /// Admin: hapus akun petugas. Ditolak oleh server bila petugas masih
  /// memiliki data nasabah, supaya riwayat data nasabah tidak pernah
  /// kehilangan jejak petugas yang menanganinya.
  Future<void> hapusPetugas(String id) async {
    await _callManagePetugas({'action': 'delete', 'id': id});
  }
}
