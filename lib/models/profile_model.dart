class ProfileModel {
  final String id;
  final String nama;
  final String role;

  /// FIX (fitur baru): foto profil — diisi admin lewat Kelola Petugas
  /// (untuk petugas) atau lewat avatar di dashboard admin (untuk admin
  /// sendiri). Null kalau belum pernah diisi.
  final String? avatarUrl;

  /// FIX (fitur baru): field profil tambahan untuk petugas, diisi admin
  /// lewat dialog Tambah/Ubah Petugas. Null kalau belum diisi.
  final String? noHp;
  final String? nik;

  ProfileModel({
    required this.id,
    required this.nama,
    required this.role,
    this.avatarUrl,
    this.noHp,
    this.nik,
  });

  factory ProfileModel.fromMap(Map<String, dynamic> map) => ProfileModel(
    id: map['id'],
    nama: map['nama'],
    role: map['role'],
    avatarUrl: map['avatar_url'] as String?,
    noHp: map['no_hp'] as String?,
    nik: map['nik'] as String?,
  );

  ProfileModel copyWith({
    String? nama,
    Object? avatarUrl = _unset,
    Object? noHp = _unset,
    Object? nik = _unset,
  }) => ProfileModel(
    id: id,
    nama: nama ?? this.nama,
    role: role,
    avatarUrl: identical(avatarUrl, _unset)
        ? this.avatarUrl
        : avatarUrl as String?,
    noHp: identical(noHp, _unset) ? this.noHp : noHp as String?,
    nik: identical(nik, _unset) ? this.nik : nik as String?,
  );

  static const _unset = Object();
}
