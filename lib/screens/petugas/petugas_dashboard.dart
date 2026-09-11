import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/nasabah_provider.dart';
import '../../widgets/nasabah_card.dart';
import '../../models/nasabah_model.dart';
import '../../screens/nasabah_detail_screen.dart';

class PetugasDashboard extends ConsumerWidget {
  const PetugasDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final nasabahAsync = ref.watch(nasabahPetugasProvider);
    final antreianAsync = ref.watch(antreianNasabahProvider);
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

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
            final totalAgunan = list.length;
            // FIX (Round C): dihitung dari getter isJatuhTempo/akanJatuhTempo
            // (client, berbasis tanggal) bukan kolom status di DB — supaya
            // selalu akurat detik itu juga, tidak tergantung kapan job
            // refreshStatusJatuhTempo() terakhir jalan.
            final jatuhTempo = list.where((n) => n.isJatuhTempo).length;
            final akanJatuhTempo = list.where((n) => n.akanJatuhTempo).length;

            // Antrian: pending & approved_gudang & rejected.
            // FIX: sebelumnya 'rejected' difilter KELUAR di sini walau
            // repository sudah mengambilnya — akibatnya nasabah yang
            // ditolak admin tidak pernah terlihat di ringkasan dashboard
            // petugas (baru terlihat kalau buka halaman "Status Pengajuan"
            // secara manual). Sekarang rejected ikut ditampilkan dengan
            // gaya merah, dan providernya sendiri sudah realtime.
            final antreianList = antreianAsync.valueOrNull ?? [];
            final menunggu = antreianList
                .where(
                  (n) =>
                      n.statusApproval == 'pending' ||
                      n.statusApproval == 'approved_gudang' ||
                      n.statusApproval == 'rejected',
                )
                .toList();

            // FIX: pengajuan lunas/perpanjangan yang masih menunggu admin
            // (atau baru saja ditolak) sebelumnya cuma kelihatan lewat
            // badge kecil di tiap kartu nasabah — sekarang ditampilkan juga
            // sebagai banner ringkasan, model serupa "Menunggu Konfirmasi"
            // di atas. 'selesai' (pelunasan yang sudah kelar) sengaja
            // dikecualikan supaya tidak nyangkut selamanya di sini.
            const statusProses = {
              'pengajuan_pelunasan',
              'konfirmasi_gudang',
              'pengajuan_perpanjangan',
              'ditolak_pelunasan',
              'ditolak_perpanjangan',
            };
            final sedangProses = list
                .where((n) => statusProses.contains(n.statusPelunasan))
                .toList();

            return RefreshIndicator(
              // FIX: nasabahPetugasProvider & antreianNasabahProvider
              // sekarang realtime — jangan invalidate (lihat komentar di
              // nasabah_provider.dart).
              onRefresh: () async {},
              child: CustomScrollView(
                slivers: [
                  // ── App Bar
                  SliverAppBar(
                    expandedHeight: 140,
                    pinned: true,
                    backgroundColor: const Color(0xFF1B4F72),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF0F2D4A), Color(0xFF1B4F72)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Halo, ${profile?.nama ?? ''}! 👋',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat(
                                'EEEE, dd MMMM yyyy',
                                'id_ID',
                              ).format(DateTime.now()),
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      // ← Tombol cari nasabah by kode
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.white),
                        tooltip: 'Cari Nasabah',
                        onPressed: () => _showCariKodeDialog(context, ref),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white),
                        onPressed: () async {
                          await ref.read(profileProvider.notifier).logout();
                          if (context.mounted) context.go('/login');
                        },
                      ),
                    ],
                  ),

                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // ── Stat Cards
                        Row(
                          children: [
                            _StatCard(
                              'Jumlah Drop',
                              fmt.format(totalDrop),
                              Icons.arrow_downward,
                              const Color(0xFF1565C0),
                            ),
                            const SizedBox(width: 10),
                            _StatCard(
                              'Pelunasan',
                              fmt.format(totalPelunasan),
                              Icons.check_circle,
                              Colors.green,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _StatCard(
                          'Total Agunan',
                          '$totalAgunan item',
                          Icons.inventory_2,
                          Colors.orange,
                          fullWidth: true,
                        ),

                        // ── Alert jatuh tempo
                        if (jatuhTempo > 0) ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => context.push('/petugas/jatuh-tempo'),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '$jatuhTempo nasabah sudah jatuh tempo!',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Colors.red,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // ── Alert H-2 (akan jatuh tempo)
                        // FIX (fitur baru): peringatan SEBELUM telat, bukan
                        // cuma setelah — nasabah yang jatuh temponya 0-2
                        // hari lagi.
                        if (akanJatuhTempo > 0) ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => context.push('/petugas/jatuh-tempo'),
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
                                    child: Text(
                                      '$akanJatuhTempo nasabah akan jatuh tempo dalam 2 hari',
                                      style: const TextStyle(
                                        color: Color(0xFFB8860B),
                                        fontWeight: FontWeight.w600,
                                      ),
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

                        // ── List Menunggu Konfirmasi
                        if (menunggu.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Menunggu Konfirmasi',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${menunggu.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              TextButton(
                                onPressed: () =>
                                    context.push('/petugas/antreian'),
                                child: const Text('Lihat Semua'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...menunggu
                              .take(3)
                              .map((n) => _AntreianItem(nasabah: n)),
                        ],

                        // ── List Menunggu Persetujuan (Pelunasan/Perpanjangan)
                        if (sedangProses.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const Text(
                            'Menunggu Persetujuan',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...sedangProses.map(
                            (n) => _ProsesItem(
                              nasabah: n,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => NasabahDetailScreen(
                                    nasabah: n,
                                    showAksi: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],

                        // ── Nasabah Terbaru
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Nasabah Aktif',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.push('/petugas/nasabah'),
                              child: const Text('Lihat Semua'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (list.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'Belum ada nasabah aktif',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),

                        ...list
                            .take(5)
                            .map(
                              (n) => NasabahCard(
                                nasabah: n,
                                onLunas: () =>
                                    _ajukanPelunasan(context, ref, n),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NasabahDetailScreen(
                                      nasabah: n,
                                      showAksi: true,
                                    ),
                                  ),
                                ),
                              ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/petugas/tambah'),
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Nasabah'),
      ),
    );
  }

  // ── Dialog cari nasabah by kode unik ────────────────────────────────────
  Future<void> _showCariKodeDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cari Nasabah'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Masukkan kode unik nasabah',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Contoh: NBS-001',
                prefixIcon: const Icon(Icons.qr_code),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: const Color(0xFFF2F5F9),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await _cariNasabah(context, ref, ctrl.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B4F72),
              foregroundColor: Colors.white,
            ),
            child: const Text('Cari'),
          ),
        ],
      ),
    );
  }

  Future<void> _cariNasabah(
    BuildContext context,
    WidgetRef ref,
    String kode,
  ) async {
    // Tampilkan loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final nasabah = await ref.read(nasabahRepoProvider).cariByKode(kode);
      if (!context.mounted) return;
      Navigator.pop(context); // tutup loading
      if (nasabah == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nasabah dengan kode "$kode" tidak ditemukan'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // Buka detail
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NasabahDetailScreen(nasabah: nasabah),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ── Ajukan pelunasan (bukan langsung lunas, tapi pengajuan ke gudang) ───
  Future<void> _ajukanPelunasan(
    BuildContext context,
    WidgetRef ref,
    NasabahModel n,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ajukan Pelunasan'),
        content: Text(
          'Ajukan pelunasan untuk nasabah ${n.nama}?\n\n'
          'Agunan akan dikeluarkan setelah disetujui admin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B4F72),
              foregroundColor: Colors.white,
            ),
            child: const Text('Ajukan'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(nasabahRepoProvider).ajukanPelunasan(n.id);
      // FIX (Round E): nasabahPetugasProvider sudah realtime, tapi event
      // UPDATE dari Supabase Realtime tidak selalu sampai secepat itu ke
      // SESI YANG SAMA yang baru saja menulis — akibatnya banner "Menunggu
      // Persetujuan" di dashboard kadang belum langsung muncul sampai
      // di-refresh manual. Invalidate provider milik dashboard ini sendiri
      // tepat setelah aksi kita sendiri berhasil memastikan itu langsung
      // ter-update.
      ref.invalidate(nasabahPetugasProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ Pengajuan pelunasan dikirim! Menunggu persetujuan admin.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
}

// ── Item antrian menunggu konfirmasi ────────────────────────────────────────
class _AntreianItem extends StatelessWidget {
  final NasabahModel nasabah;
  const _AntreianItem({required this.nasabah});

  @override
  Widget build(BuildContext context) {
    // FIX: 'rejected' sekarang ikut ditampilkan (lihat filter `menunggu`
    // di PetugasDashboard) supaya penolakan admin langsung terlihat tanpa
    // harus buka halaman "Status Pengajuan" terpisah.
    final ditolak = nasabah.statusApproval == 'rejected';
    final color = ditolak ? Colors.red : Colors.blue;
    final label = ditolak ? 'Ditolak' : 'Menunggu Admin';
    final icon = ditolak ? Icons.cancel : Icons.admin_panel_settings;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nasabah.nama,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  nasabah.jenisAgunan,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Item pengajuan lunas/perpanjangan menunggu admin ────────────────────────
class _ProsesItem extends StatelessWidget {
  final NasabahModel nasabah;
  final VoidCallback onTap;
  const _ProsesItem({required this.nasabah, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // FIX: dulu hanya ada 2 kemungkinan label (lunas/perpanjangan,
    // keduanya selalu "menunggu") — sekarang status ditolak punya
    // tampilan sendiri (merah, bukan hijau/oranye) supaya tidak terbaca
    // seolah masih diproses.
    late final Color color;
    late final String label;
    late final IconData icon;
    switch (nasabah.statusPelunasan) {
      case 'pengajuan_pelunasan':
      case 'konfirmasi_gudang':
        color = Colors.green;
        label = 'Menunggu Persetujuan Lunas';
        icon = Icons.price_check;
        break;
      case 'pengajuan_perpanjangan':
        color = Colors.orange;
        label = 'Menunggu Persetujuan Perpanjangan';
        icon = Icons.update;
        break;
      case 'ditolak_pelunasan':
        color = Colors.red;
        label = 'Pengajuan Lunas Ditolak';
        icon = Icons.cancel;
        break;
      case 'ditolak_perpanjangan':
        color = Colors.red;
        label = 'Pengajuan Perpanjangan Ditolak';
        icon = Icons.cancel;
        break;
      default:
        color = Colors.grey;
        label = '-';
        icon = Icons.info_outline;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nasabah.nama,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

// ── Stat card ────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool fullWidth;

  const _StatCard(
    this.label,
    this.value,
    this.icon,
    this.color, {
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
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
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return fullWidth ? card : Expanded(child: card);
  }
}
