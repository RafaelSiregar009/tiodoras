import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/nasabah_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/nasabah_provider.dart';
import '../../widgets/search_agunan_dialog.dart';

class GudangDashboard extends ConsumerWidget {
  const GudangDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final antreianAsync = ref.watch(antreianGudangStreamProvider);
    final pelunasanAsync = ref.watch(pelunasanGudangStreamProvider);
    final agunanAsync = ref.watch(allAgunanProvider);

    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        title: Text('Gudang: ${profile?.nama ?? ''}'),
        backgroundColor: const Color(0xFF1B5E3B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Cari Agunan',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const SearchAgunanDialog(),
            ),
          ),
          // FIX: tombol logout sebelumnya hilang dari dashboard gudang
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Keluar',
            onPressed: () async {
              await ref.read(profileProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        // FIX: JANGAN invalidate StreamProvider di sini.
        // Stream realtime Supabase sudah push update sendiri; invalidate
        // memutus koneksi websocket lalu subscribe ulang -> layar berkedip
        // dan data sempat kosong. Cukup refresh provider Future saja.
        onRefresh: () async => ref.invalidate(allAgunanProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Ringkasan
            Row(
              children: [
                _statCard(
                  'Antrean Masuk',
                  '${antreianAsync.value?.length ?? 0}',
                  Icons.pending_actions,
                  Colors.orange,
                ),
                const SizedBox(width: 10),
                _statCard(
                  'Barang Keluar',
                  '${pelunasanAsync.value?.length ?? 0}',
                  Icons.output,
                  Colors.red,
                ),
                const SizedBox(width: 10),
                _statCard(
                  'Agunan Aktif',
                  '${agunanAsync.value?.length ?? 0}',
                  Icons.inventory_2,
                  const Color(0xFF1B5E3B),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── ANTREAN BARANG MASUK (realtime)
            const Text(
              'Antrean Barang Masuk',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            antreianAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Tidak ada antrean barang masuk',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return Column(
                  children: list
                      .map(
                        (n) => _GudangCard(
                          nasabah: n,
                          fmt: fmt,
                          accent: Colors.orange,
                          buttonLabel: 'Konfirmasi Barang Masuk',
                          onAksi: () => _konfirmasiMasuk(context, ref, n),
                        ),
                      )
                      .toList(),
                );
              },
            ),

            const SizedBox(height: 28),

            // ── BARANG KELUAR (realtime)
            const Text(
              'Permintaan Pengeluaran Agunan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            pelunasanAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Tidak ada permintaan barang keluar',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return Column(
                  children: list
                      .map(
                        (n) => _GudangCard(
                          nasabah: n,
                          fmt: fmt,
                          accent: Colors.red,
                          buttonLabel: 'Keluarkan Agunan',
                          onAksi: () => _keluarkanAgunan(context, ref, n),
                        ),
                      )
                      .toList(),
                );
              },
            ),

            const SizedBox(height: 28),

            // ── DAFTAR AGUNAN AKTIF
            const Text(
              'Daftar Agunan Aktif',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            agunanAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Belum ada agunan aktif',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return Column(
                  children: list
                      .map(
                        (n) => _GudangCard(
                          nasabah: n,
                          fmt: fmt,
                          accent: const Color(0xFF1B5E3B),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Aksi: konfirmasi barang masuk ────────────────────────────────────
  Future<void> _konfirmasiMasuk(
    BuildContext context,
    WidgetRef ref,
    NasabahModel n,
  ) async {
    final ok = await _confirm(
      context,
      title: 'Konfirmasi Barang Masuk',
      body:
          'Konfirmasi barang masuk untuk ${n.nama}?\n'
          'Pengajuan akan diteruskan ke Admin.',
      warna: const Color(0xFF1B5E3B),
    );
    if (ok != true) return;

    try {
      await ref.read(nasabahRepoProvider).konfirmasiGudang(n.id);
      // Stream realtime otomatis menghapus item ini dari daftar.
      // Hanya provider Future yang perlu di-invalidate.
      ref.invalidate(allAgunanProvider);
      if (context.mounted) {
        _snack(
          context,
          'Barang masuk dikonfirmasi, diteruskan ke Admin',
          Colors.green,
        );
      }
    } catch (e) {
      // FIX: sebelumnya error dari Supabase tidak ditangkap sama sekali,
      // sehingga kegagalan RLS tampak seperti "tombol tidak berfungsi"
      if (context.mounted) _snack(context, 'Gagal: $e', Colors.red);
    }
  }

  // ── Aksi: keluarkan agunan + surat jalan ─────────────────────────────
  Future<void> _keluarkanAgunan(
    BuildContext context,
    WidgetRef ref,
    NasabahModel n,
  ) async {
    final ok = await _confirm(
      context,
      title: 'Keluarkan Agunan',
      body:
          'Keluarkan agunan ${n.jenisAgunan} milik ${n.nama}?\n'
          'Surat jalan akan dibuat dan diteruskan ke Admin.',
      warna: Colors.red,
    );
    if (ok != true) return;

    try {
      final repo = ref.read(nasabahRepoProvider);
      await repo.konfirmasiPelunasanGudang(n.id);
      await repo.buatSuratJalan(n.id);
      ref.invalidate(allAgunanProvider);
      if (context.mounted) {
        _snack(
          context,
          'Agunan dikeluarkan, diteruskan ke Admin',
          Colors.green,
        );
        _showSuratJalan(context, n);
      }
    } catch (e) {
      if (context.mounted) _snack(context, 'Gagal: $e', Colors.red);
    }
  }

  // ── Surat jalan ──────────────────────────────────────────────────────
  void _showSuratJalan(BuildContext context, NasabahModel n) {
    final fmtDate = DateFormat('dd MMMM yyyy', 'id_ID');
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    const Text(
                      'PT TIODORAS L.',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'SURAT JALAN BARANG KELUAR',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Tanggal: ${fmtDate.format(DateTime.now())}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24, thickness: 2),
              _sjRow('Nama Nasabah', n.nama),
              if (n.kodeNasabah != null) _sjRow('Kode', n.kodeNasabah!),
              if (n.alamat != null && n.alamat!.isNotEmpty)
                _sjRow('Alamat', n.alamat!),
              if (n.noHp != null && n.noHp!.isNotEmpty)
                _sjRow('No. HP', n.noHp!),
              _sjRow('Jenis Agunan', n.jenisAgunan),
              if (n.detailAgunan != null)
                _sjRow('Detail Agunan', n.detailAgunan!),
              _sjRow('Jumlah Pelunasan', fmt.format(n.jumlahPelunasan)),
              _sjRow('Petugas', n.petugasNama ?? '-'),
              const Divider(height: 24),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Ttd('Petugas\nGudang'),
                  _Ttd('Nasabah'),
                  _Ttd('Admin'),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E3B),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Tutup'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper ───────────────────────────────────────────────────────────
  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required Color warna,
  }) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: warna,
            foregroundColor: Colors.white,
          ),
          child: const Text('Lanjut'),
        ),
      ],
    ),
  );

  void _snack(BuildContext context, String msg, Color warna) =>
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: warna));

  Widget _statCard(String label, String value, IconData icon, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
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
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      );

  Widget _sjRow(String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        const Text(': ', style: TextStyle(color: Colors.grey, fontSize: 12)),
        Expanded(
          child: Text(
            val,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════
class _Ttd extends StatelessWidget {
  final String label;
  const _Ttd(this.label);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 80,
        height: 60,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════
class _GudangCard extends StatelessWidget {
  final NasabahModel nasabah;
  final NumberFormat fmt;
  final Color accent;
  final String? buttonLabel;
  final VoidCallback? onAksi;

  const _GudangCard({
    required this.nasabah,
    required this.fmt,
    required this.accent,
    this.buttonLabel,
    this.onAksi,
  });

  @override
  Widget build(BuildContext context) {
    final n = nasabah;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetail(context, n),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // FIX: foto sebelumnya tidak ditampilkan sama sekali
                  GestureDetector(
                    onTap: () => _fotoFullscreen(context, n),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: n.fotoUrl != null
                          ? Image.network(
                              n.fotoUrl!,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _avatar(),
                            )
                          : _avatar(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.nama,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '${n.kodeNasabah ?? '-'} • ${n.jenisAgunan}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        if (n.petugasNama != null)
                          Text(
                            'Petugas: ${n.petugasNama}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: accent),
                ],
              ),
              if (n.detailAgunan != null && n.detailAgunan!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Detail: ${n.detailAgunan}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              if (buttonLabel != null && onAksi != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onAksi,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(buttonLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, NasabahModel n) {
    final fmtDate = DateFormat('dd MMM yyyy');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (n.fotoUrl != null) ...[
                GestureDetector(
                  onTap: () => _fotoFullscreen(context, n),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      n.fotoUrl!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Tap foto untuk perbesar',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                n.nama,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Divider(height: 24),
              _dRow('Kode', n.kodeNasabah ?? '-'),
              _dRow('Petugas', n.petugasNama ?? '-'),
              _dRow('Jenis Agunan', n.jenisAgunan),
              if (n.detailAgunan != null)
                _dRow('Detail Agunan', n.detailAgunan!),
              if (n.alamat != null && n.alamat!.isNotEmpty)
                _dRow('Alamat', n.alamat!),
              if (n.noHp != null && n.noHp!.isNotEmpty)
                _dRow('No. HP', n.noHp!),
              _dRow('Pinjaman', fmt.format(n.nominalPinjaman)),
              _dRow('Pelunasan', fmt.format(n.jumlahPelunasan)),
              _dRow('Tgl Masuk', fmtDate.format(n.tanggalMasuk)),
              _dRow('Jatuh Tempo', fmtDate.format(n.tanggalJatuhTempo)),
              _dRow('Status', n.status),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _fotoFullscreen(BuildContext context, NasabahModel n) {
    if (n.fotoUrl == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(n.nama),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(n.fotoUrl!, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar() => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: accent.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(Icons.inventory_2, color: accent),
  );

  Widget _dRow(String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            val,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
