import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/nasabah_provider.dart';

// FIX (fitur baru): admin mengganti foto profil MILIK SENDIRI dari header
// dashboard. Upload ke Storage lalu update baris profiles-nya sendiri lewat
// AuthRepository.updateOwnAvatar() (diizinkan RLS khusus baris admin
// sendiri), lalu refresh state lokal lewat
// profileProvider.notifier.updateAvatarLocally() supaya UI langsung
// ter-update tanpa perlu logout/login ulang.
Future<void> _pickAndUploadOwnAvatar(BuildContext context, WidgetRef ref) async {
  final picker = ImagePicker();
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Kamera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Galeri'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return;

  final img = await picker.pickImage(
    source: source,
    imageQuality: 70,
    maxWidth: 640,
  );
  if (img == null) return;

  final Uint8List bytes = await img.readAsBytes();
  final profile = ref.read(profileProvider);
  if (profile == null) return;

  try {
    final avatarUrl = await ref
        .read(nasabahRepoProvider)
        .uploadAvatar(bytes, profile.id);
    await ref.read(authRepoProvider).updateOwnAvatar(avatarUrl);
    ref.read(profileProvider.notifier).updateAvatarLocally(avatarUrl);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Foto profil diperbarui'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengunggah foto: $e')),
      );
    }
  }
}

// FIX (redesign): sapaan dinamis sesuai jam saat ini, dipakai di header
// dashboard supaya terasa lebih personal.
String _sapaan() {
  final hour = DateTime.now().hour;
  if (hour < 11) return 'Selamat Pagi';
  if (hour < 15) return 'Selamat Siang';
  if (hour < 18) return 'Selamat Sore';
  return 'Selamat Malam';
}

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final nasabahAsync = ref.watch(allNasabahProvider);
    final petugasAsync = ref.watch(allPetugasProvider);

    // Realtime streams
    final antreianBaru = ref.watch(antreianAdminStreamProvider);
    final antreianPelunasan = ref.watch(pelunasanAdminStreamProvider);
    final antreianPerpanjangan = ref.watch(perpanjanganAdminStreamProvider);

    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final fmtTanggal = DateFormat('EEEE, d MMMM yyyy', 'id_ID');

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      body: SafeArea(
        child: nasabahAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) {
            final totalDrop = list.fold<int>(
              0,
              (s, n) => s + n.nominalPinjaman,
            );
            final totalPelunasan = list
                .where((n) => n.status == 'lunas')
                .fold<int>(0, (s, n) => s + n.jumlahPelunasan);
            final laba = totalPelunasan - totalDrop;
            // FIX (Round C): dihitung dari getter isJatuhTempo/akanJatuhTempo
            // (client, berbasis tanggal) bukan kolom status di DB — supaya
            // selalu akurat detik itu juga, tidak tergantung kapan job
            // refreshStatusJatuhTempo() terakhir jalan.
            final jatuhTempo = list.where((n) => n.isJatuhTempo).length;
            final akanJatuhTempo = list.where((n) => n.akanJatuhTempo).length;
            final berjalan = list.where((n) => n.status == 'berjalan').length;
            final lunas = list.where((n) => n.status == 'lunas').length;

            final countBaru = antreianBaru.value?.length ?? 0;
            final countPelunasan = antreianPelunasan.value?.length ?? 0;
            final countPerpanjangan = antreianPerpanjangan.value?.length ?? 0;
            final totalNotif = countBaru + countPelunasan + countPerpanjangan;

            return RefreshIndicator(
              onRefresh: () async {
                // FIX: allNasabahProvider sekarang realtime — jangan
                // invalidate (lihat streamAllNasabahAktif() di repository).
                ref.invalidate(allPetugasProvider);
              },
              child: CustomScrollView(
                slivers: [
                  // ── Sliver App Bar
                  SliverAppBar(
                    expandedHeight: 210,
                    pinned: true,
                    elevation: 0,
                    backgroundColor: const Color(0xFF0F2D4A),
                    actions: [
                      if (totalNotif > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _HeaderIconButton(
                                icon: Icons.notifications_outlined,
                                onTap: () => context.push('/admin/approval'),
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: Container(
                                  width: 17,
                                  height: 17,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE05252),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF0F2D4A),
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$totalNotif',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _HeaderIconButton(
                        icon: Icons.logout_rounded,
                        onTap: () async {
                          await ref.read(profileProvider.notifier).logout();
                          if (context.mounted) context.go('/login');
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(32),
                          bottomRight: Radius.circular(32),
                        ),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0F2D4A), Color(0xFF1B4F72)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Stack(
                            children: [
                              // ── Aksen dekoratif emas, samar-samar di
                              // pojok, supaya header tidak terasa polos.
                              Positioned(
                                right: -30,
                                top: -30,
                                child: Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(
                                      0xFFC9A84C,
                                    ).withOpacity(0.10),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: -20,
                                bottom: -40,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withOpacity(0.04),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  56,
                                  20,
                                  28,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        GestureDetector(
                                          onTap: () =>
                                              _pickAndUploadOwnAvatar(
                                                context,
                                                ref,
                                              ),
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Container(
                                                width: 52,
                                                height: 52,
                                                padding: const EdgeInsets.all(
                                                  2,
                                                ),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFC9A84C,
                                                    ).withOpacity(0.6),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient:
                                                        profile?.avatarUrl ==
                                                            null
                                                        ? const LinearGradient(
                                                            colors: [
                                                              Color(
                                                                0xFFC9A84C,
                                                              ),
                                                              Color(
                                                                0xFFF0D080,
                                                              ),
                                                            ],
                                                          )
                                                        : null,
                                                    image:
                                                        profile?.avatarUrl !=
                                                            null
                                                        ? DecorationImage(
                                                            image: NetworkImage(
                                                              profile!
                                                                  .avatarUrl!,
                                                            ),
                                                            fit: BoxFit.cover,
                                                          )
                                                        : null,
                                                  ),
                                                  child:
                                                      profile?.avatarUrl !=
                                                          null
                                                      ? null
                                                      : Center(
                                                          child: Text(
                                                            profile?.nama
                                                                        .isNotEmpty ==
                                                                    true
                                                                ? profile!
                                                                      .nama[0]
                                                                      .toUpperCase()
                                                                : 'A',
                                                            style: const TextStyle(
                                                              color: Colors
                                                                  .white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 18,
                                                            ),
                                                          ),
                                                        ),
                                                ),
                                              ),
                                              Positioned(
                                                right: -2,
                                                bottom: -2,
                                                child: Container(
                                                  padding: const EdgeInsets.all(
                                                    3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF0F2D4A,
                                                    ),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.white
                                                          .withOpacity(0.9),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.camera_alt,
                                                    size: 10,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${_sapaan()}, ${profile?.nama ?? 'Admin'}',
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                fmtTanggal.format(
                                                  DateTime.now(),
                                                ),
                                                style: const TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // ── KARTU RINGKASAN UTAMA — sengaja "mengambang"
                        // menumpuk sedikit ke atas header gradient, gaya
                        // dashboard modern, menonjolkan dua angka paling
                        // penting bagi admin.
                        Transform.translate(
                          offset: const Offset(0, -26),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 18,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0F2D4A,
                                  ).withOpacity(0.14),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _HeroMetric(
                                    label: 'Total Drop',
                                    value: fmt.format(totalDrop),
                                    icon: Icons.arrow_downward_rounded,
                                    color: const Color(0xFF1565C0),
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 42,
                                  color: const Color(0xFFEAEEF3),
                                ),
                                Expanded(
                                  child: _HeroMetric(
                                    label: 'Laba Bersih',
                                    value: laba >= 0
                                        ? fmt.format(laba)
                                        : '-${fmt.format(laba.abs())}',
                                    icon: Icons.trending_up_rounded,
                                    color: laba >= 0
                                        ? const Color(0xFF2E8B57)
                                        : const Color(0xFFC0392B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── BANNER PERSETUJUAN (Realtime)
                        if (totalNotif > 0) ...[
                          Transform.translate(
                            offset: const Offset(0, -12),
                            child: _buildBannerApproval(
                              context,
                              countBaru: countBaru,
                              countPelunasan: countPelunasan,
                              countPerpanjangan: countPerpanjangan,
                            ),
                          ),
                        ],

                        // ── STAT GRID 2x2
                        Transform.translate(
                          offset: const Offset(0, -12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  petugasAsync.when(
                                    data: (p) => _StatCard(
                                      'Jumlah Petugas',
                                      '${p.length} orang',
                                      Icons.badge_outlined,
                                      Colors.purple,
                                      onTap: () =>
                                          context.push('/admin/petugas'),
                                    ),
                                    loading: () => const _StatCardLoading(),
                                    error: (_, __) => const SizedBox(),
                                  ),
                                  const SizedBox(width: 10),
                                  _StatCard(
                                    'Nasabah Aktif',
                                    '$berjalan orang',
                                    Icons.people_alt_outlined,
                                    Colors.teal,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _StatCard(
                                    'Sudah Lunas',
                                    '$lunas orang',
                                    Icons.check_circle_outline,
                                    const Color(0xFF2E8B57),
                                    onTap: () =>
                                        context.push('/admin/nasabah-lunas'),
                                  ),
                                  const SizedBox(width: 10),
                                  _StatCard(
                                    'Jatuh Tempo',
                                    '$jatuhTempo orang',
                                    Icons.warning_amber_rounded,
                                    jatuhTempo > 0
                                        ? const Color(0xFFC0392B)
                                        : Colors.grey,
                                    onTap: jatuhTempo > 0
                                        ? () =>
                                              context.push('/admin/jatuh-tempo')
                                        : null,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ── BANNER JATUH TEMPO
                        if (jatuhTempo > 0) ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => context.push('/admin/jatuh-tempo'),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.red.shade700,
                                    Colors.red.shade500,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$jatuhTempo Nasabah Jatuh Tempo!',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Text(
                                          'Tap untuk lihat detail',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // ── BANNER H-2 (akan jatuh tempo)
                        // FIX (fitur baru): peringatan SEBELUM telat, bukan
                        // cuma setelah — nasabah yang jatuh temponya 0-2
                        // hari lagi.
                        if (akanJatuhTempo > 0) ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => context.push('/admin/jatuh-tempo'),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.amber[50],
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.amber.withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.notifications_active,
                                    color: Color(0xFFB8860B),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$akanJatuhTempo Nasabah Akan Jatuh Tempo (H-2)',
                                          style: const TextStyle(
                                            color: Color(0xFFB8860B),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Text(
                                          'Tap untuk lihat detail',
                                          style: TextStyle(
                                            color: Color(0x99B8860B),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFFB8860B),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        // ── NASABAH PER PETUGAS
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const _SectionTitle(
                              icon: Icons.groups_outlined,
                              title: 'Nasabah per Petugas',
                            ),
                            TextButton(
                              onPressed: () => context.push('/admin/nasabah'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF1B4F72),
                              ),
                              child: const Text(
                                'Lihat Semua',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        petugasAsync.when(
                          data: (petugas) => Column(
                            children: petugas.map((p) {
                              final milik = list
                                  .where((n) => n.petugasId == p.id)
                                  .toList();
                              final berjalan = milik
                                  .where((n) => n.status == 'berjalan')
                                  .length;
                              final jt = milik
                                  .where((n) => n.isJatuhTempo)
                                  .length;
                              final lunas = milik
                                  .where((n) => n.status == 'lunas')
                                  .length;
                              final totalDrop = milik.fold<int>(
                                0,
                                (s, n) => s + n.nominalPinjaman,
                              );

                              final accentColor = jt > 0
                                  ? const Color(0xFFC0392B)
                                  : const Color(0xFF2E8B57);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => context.push(
                                    '/admin/nasabah-petugas/${p.id}',
                                  ),
                                  child: IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // FIX (redesign): aksen warna tipis
                                        // di sisi kiri — hijau kalau tidak
                                        // ada yang jatuh tempo, merah kalau
                                        // ada, supaya status petugas
                                        // terlihat sekilas dari daftar.
                                        Container(
                                          width: 4,
                                          color: accentColor,
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.all(14),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 44,
                                                  height: 44,
                                                  decoration: const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Color(0xFF1B4F72),
                                                        Color(0xFF0F2D4A),
                                                      ],
                                                      begin:
                                                          Alignment.topLeft,
                                                      end: Alignment
                                                          .bottomRight,
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      p.nama[0].toUpperCase(),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        p.nama,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 4,
                                                      ),
                                                      Text(
                                                        fmt.format(totalDrop),
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFF1565C0,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 6,
                                                      ),
                                                      Row(
                                                        children: [
                                                          _MiniChip(
                                                            '$berjalan Aktif',
                                                            Colors.blue,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          if (jt > 0)
                                                            _MiniChip(
                                                              '$jt JT',
                                                              Colors.red,
                                                            ),
                                                          if (jt > 0)
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                          _MiniChip(
                                                            '$lunas Lunas',
                                                            Colors.green,
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const Icon(
                                                  Icons.chevron_right,
                                                  color: Colors.grey,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text('Error: $e'),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBannerApproval(
    BuildContext context, {
    required int countBaru,
    required int countPelunasan,
    required int countPerpanjangan,
  }) {
    final total = countBaru + countPelunasan + countPerpanjangan;
    return GestureDetector(
      onTap: () => context.push('/admin/approval'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8C00), Color(0xFFFFAB40)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.pending_actions,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$total Pengajuan Menunggu Persetujuan',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const Text(
                        'Tap untuk review sekarang',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (countBaru > 0)
                  _BannerChip('$countBaru Nasabah Baru', Colors.blue.shade700),
                if (countBaru > 0 && countPelunasan > 0)
                  const SizedBox(width: 6),
                if (countPelunasan > 0)
                  _BannerChip(
                    '$countPelunasan Pelunasan',
                    Colors.green.shade700,
                  ),
                if (countPelunasan > 0 && countPerpanjangan > 0)
                  const SizedBox(width: 6),
                if (countPerpanjangan > 0)
                  _BannerChip(
                    '$countPerpanjangan Perpanjangan',
                    Colors.purple.shade700,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerChip extends StatelessWidget {
  final String label;
  final Color color;
  const _BannerChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// FIX (redesign): tombol ikon di header (notifikasi, logout) dengan latar
// translucent bulat, supaya konsisten dan lebih "premium" dibanding
// IconButton polos di atas gradient gelap.
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// FIX (redesign): judul seksi dengan aksen bar emas kecil di depan teks,
// dipakai berulang supaya tiap seksi dashboard punya penanda visual yang
// konsisten.
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFFC9A84C),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 17, color: const Color(0xFF1B4F72)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F2D4A),
          ),
        ),
      ],
    );
  }
}

// FIX (redesign): dipakai di kartu ringkasan utama yang "mengambang" di
// bawah header (Total Drop & Laba Bersih).
class _HeroMetric extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 15),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: color,
            fontSize: 15.5,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _StatCard(
    this.label,
    this.value,
    this.icon,
    this.color, {
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: color, width: 3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCardLoading extends StatelessWidget {
  const _StatCardLoading();
  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
