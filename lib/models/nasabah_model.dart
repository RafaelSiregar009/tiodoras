class NasabahModel {
  final String id;
  final String petugasId;
  final String nama;
  final String? alamat;
  final String? noHp;
  final int nominalPinjaman;
  final String jenisAgunan;
  final String? detailAgunan;
  final int jumlahPelunasan;
  final DateTime tanggalMasuk;
  final DateTime tanggalJatuhTempo;

  /// FIX (fitur baru): kapan pinjaman ini benar-benar disetujui LUNAS oleh
  /// admin — dipakai untuk mengelompokkan "Storting" per bulan di halaman
  /// detail petugas. Null kalau belum lunas. Untuk data yang sudah lunas
  /// SEBELUM kolom ini ada, nilainya diisi PERKIRAAN (lihat migrasi
  /// 20260910_add_monthly_report_support.sql).
  final DateTime? tanggalLunas;
  final String status;
  final String statusApproval;

  /// null | 'pengajuan_pelunasan' | 'pengajuan_perpanjangan' | 'selesai'
  final String? statusPelunasan;

  final String? fotoUrl;

  /// Foto nasabah (wajah/identitas), terpisah dari [fotoUrl] yang berisi
  /// foto agunan.
  final String? fotoNasabahUrl;
  final String? petugasNama;
  final String? kodeNasabah;
  final String? catatanPenolakan;

  /// FIX (fitur baru): berapa kali pinjaman ini SUDAH disetujui admin untuk
  /// diperpanjang (bukan berapa kali diajukan — pengajuan yang ditolak
  /// tidak dihitung). Diisi & di-increment otomatis oleh trigger di
  /// database setiap kali admin menyetujui perpanjangan (lihat migrasi
  /// 20260911d_add_jumlah_perpanjangan.sql) — Flutter tidak pernah
  /// mengirim/mengubah nilai ini secara langsung. Dipakai lewat getter
  /// [pinjamanKe] di bawah.
  final int jumlahPerpanjangan;

  NasabahModel({
    required this.id,
    required this.petugasId,
    required this.nama,
    this.alamat,
    this.noHp,
    required this.nominalPinjaman,
    required this.jenisAgunan,
    this.detailAgunan,
    required this.jumlahPelunasan,
    required this.tanggalMasuk,
    required this.tanggalJatuhTempo,
    this.tanggalLunas,
    required this.status,
    required this.statusApproval,
    this.statusPelunasan,
    this.fotoUrl,
    this.fotoNasabahUrl,
    this.petugasNama,
    this.kodeNasabah,
    this.catatanPenolakan,
    this.jumlahPerpanjangan = 0,
  });

  // ── HELPER PARSING AMAN ────────────────────────────────────────────────
  // FIX: Postgres numeric/bigint bisa datang sebagai double atau String.
  // Assign langsung ke int -> "type 'double' is not a subtype of type 'int'"
  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  // FIX: DateTime.parse(null) melempar exception dan mematikan seluruh list
  static DateTime _toDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString()) ?? DateTime.now();
  }

  /// FIX (fitur baru): versi nullable dari [_toDate] — dipakai untuk
  /// tanggal_lunas, yang MEMANG harus tetap null selagi nasabah belum lunas
  /// (beda dengan tanggal lain yang selalu ada nilainya).
  static DateTime? _toDateOrNull(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  // FIX: pada realtime .stream() tidak ada join profiles(nama),
  // jadi map['profiles'] bisa null ATAU berupa List (bukan Map)
  static String? _petugasNama(dynamic v) {
    if (v == null) return null;
    if (v is Map) return v['nama'] as String?;
    if (v is List && v.isNotEmpty && v.first is Map) {
      return (v.first as Map)['nama'] as String?;
    }
    return null;
  }

  factory NasabahModel.fromMap(Map<String, dynamic> map) => NasabahModel(
    id: map['id'].toString(),
    petugasId: map['petugas_id']?.toString() ?? '',
    nama: map['nama']?.toString() ?? '-',
    alamat: map['alamat'] as String?,
    noHp: map['no_hp'] as String?,
    nominalPinjaman: _toInt(map['nominal_pinjaman']),
    jenisAgunan: map['jenis_agunan']?.toString() ?? '-',
    detailAgunan: map['detail_agunan'] as String?,
    jumlahPelunasan: _toInt(map['jumlah_pelunasan']),
    tanggalMasuk: _toDate(map['tanggal_masuk']),
    tanggalJatuhTempo: _toDate(map['tanggal_jatuh_tempo']),
    tanggalLunas: _toDateOrNull(map['tanggal_lunas']),
    status: map['status']?.toString() ?? 'berjalan',
    statusApproval: map['status_approval']?.toString() ?? 'pending',
    statusPelunasan: map['status_pelunasan'] as String?,
    fotoUrl: map['foto_url'] as String?,
    fotoNasabahUrl: map['foto_nasabah_url'] as String?,
    petugasNama: _petugasNama(map['profiles']),
    kodeNasabah: map['kode_nasabah'] as String?,
    catatanPenolakan: map['catatan_penolakan'] as String?,
    jumlahPerpanjangan: _toInt(map['jumlah_perpanjangan']),
  );

  // FIX: pakai sentinel agar statusPelunasan BISA di-reset ke null
  static const _unset = Object();

  NasabahModel copyWith({
    String? status,
    String? statusApproval,
    Object? statusPelunasan = _unset,
    DateTime? tanggalJatuhTempo,
  }) => NasabahModel(
    id: id,
    petugasId: petugasId,
    nama: nama,
    alamat: alamat,
    noHp: noHp,
    nominalPinjaman: nominalPinjaman,
    jenisAgunan: jenisAgunan,
    detailAgunan: detailAgunan,
    jumlahPelunasan: jumlahPelunasan,
    tanggalMasuk: tanggalMasuk,
    tanggalJatuhTempo: tanggalJatuhTempo ?? this.tanggalJatuhTempo,
    tanggalLunas: tanggalLunas,
    status: status ?? this.status,
    statusApproval: statusApproval ?? this.statusApproval,
    statusPelunasan: identical(statusPelunasan, _unset)
        ? this.statusPelunasan
        : statusPelunasan as String?,
    fotoUrl: fotoUrl,
    fotoNasabahUrl: fotoNasabahUrl,
    petugasNama: petugasNama,
    kodeNasabah: kodeNasabah,
    catatanPenolakan: catatanPenolakan,
    jumlahPerpanjangan: jumlahPerpanjangan,
  );

  int get biayaPerpanjangan => (nominalPinjaman * 0.2).round();

  /// FIX (fitur baru): "Pinjaman ke berapa" — 1 kalau baru diajukan/belum
  /// pernah diperpanjang, otomatis naik jadi 2, 3, dst setiap kali admin
  /// menyetujui perpanjangan.
  int get pinjamanKe => jumlahPerpanjangan + 1;

  /// Jatuh tempo dihitung dari tanggal, bukan hanya kolom status.
  /// Berguna kalau trigger/cron di DB belum jalan.
  bool get isJatuhTempo =>
      status != 'lunas' &&
      DateTime.now().isAfter(
        DateTime(
          tanggalJatuhTempo.year,
          tanggalJatuhTempo.month,
          tanggalJatuhTempo.day,
          23,
          59,
          59,
        ),
      );

  int get hariTerlambat => DateTime.now().difference(tanggalJatuhTempo).inDays;

  /// Selisih hari ke tanggal jatuh tempo (0 = hari ini, negatif = sudah
  /// lewat). Dihitung dari tanggal kalender, bukan jam, supaya tidak
  /// meleset karena selisih waktu di hari yang sama.
  int get hariMenujuJatuhTempo {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(
      tanggalJatuhTempo.year,
      tanggalJatuhTempo.month,
      tanggalJatuhTempo.day,
    );
    return due.difference(today).inDays;
  }

  /// FIX (fitur baru): peringatan H-2 — nasabah yang jatuh temponya masih
  /// 0-2 hari lagi (belum lewat, jadi bukan [isJatuhTempo]) supaya petugas
  /// & admin bisa mengingatkan nasabah SEBELUM telat, bukan cuma setelah.
  bool get akanJatuhTempo =>
      status != 'lunas' &&
      !isJatuhTempo &&
      hariMenujuJatuhTempo >= 0 &&
      hariMenujuJatuhTempo <= 2;
}
