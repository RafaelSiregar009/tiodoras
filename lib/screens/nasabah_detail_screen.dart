import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/nasabah_model.dart';
import '../providers/nasabah_provider.dart';
import 'petugas/petugas_perpanjang.dart';

class NasabahDetailScreen extends ConsumerWidget {
  final NasabahModel nasabah;

  /// FIX: parameter ini sempat hilang saat file ini ditulis ulang, padahal
  /// dipakai petugas_dashboard.dart & petugas_jatuh_tempo.dart (compile
  /// error "No named parameter with the name 'showAksi'"). Kalau true,
  /// tampilkan tombol "Ajukan Lunas" / "Perpanjang" di bawah halaman detail
  /// — dipakai saat petugas membuka detail nasabah miliknya sendiri,
  /// supaya tidak perlu balik ke dashboard dulu untuk mengajukan.
  final bool showAksi;

  const NasabahDetailScreen({
    super.key,
    required this.nasabah,
    this.showAksi = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final fmtDate = DateFormat('dd MMM yyyy');

    // FIX: nasabah yang dilempar ke sini kadang berasal dari stream
    // realtime tanpa join profiles(nama) (mis. dari kartu di layar
    // Persetujuan), jadi nasabah.petugasNama bisa null. Fallback: cari
    // manual dari allPetugasProvider berdasarkan petugasId.
    final petugasAsync = ref.watch(allPetugasProvider);
    String? petugasNama = nasabah.petugasNama;
    if (petugasNama == null || petugasNama.isEmpty) {
      final list = petugasAsync.valueOrNull;
      if (list != null) {
        for (final p in list) {
          if (p.id == nasabah.petugasId) {
            petugasNama = p.nama;
            break;
          }
        }
      }
    }

    // FIX (Round C): pakai getter isJatuhTempo (client, berbasis tanggal)
    // bukan kolom status di DB, supaya badge selalu akurat walau job
    // refreshStatusJatuhTempo() belum sempat jalan.
    Color statusColor = nasabah.status == 'lunas'
        ? Colors.green
        : nasabah.isJatuhTempo
        ? Colors.red
        : const Color(0xFF1565C0);
    String statusLabel = nasabah.status == 'lunas'
        ? 'Lunas'
        : nasabah.isJatuhTempo
        ? 'Jatuh Tempo'
        : 'Berjalan';

    // Sama seperti NasabahCard: tentukan apakah sedang ada pengajuan
    // lunas/perpanjangan berjalan, atau baru saja ditolak (boleh ajukan
    // ulang), supaya tombol aksi di bawah konsisten dengan yang ada di
    // dashboard.
    final sedangPelunasan =
        nasabah.statusPelunasan == 'pengajuan_pelunasan' ||
        nasabah.statusPelunasan == 'konfirmasi_gudang';
    final sedangPerpanjangan =
        nasabah.statusPelunasan == 'pengajuan_perpanjangan';
    final ditolakPelunasan = nasabah.statusPelunasan == 'ditolak_pelunasan';
    final ditolakPerpanjangan =
        nasabah.statusPelunasan == 'ditolak_perpanjangan';
    final bisaAjukanUlang =
        nasabah.statusPelunasan == null ||
        ditolakPelunasan ||
        ditolakPerpanjangan;
    final bisaAjukanAksi =
        showAksi &&
        nasabah.status != 'lunas' &&
        !sedangPelunasan &&
        !sedangPerpanjangan;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        title: const Text('Detail Nasabah'),
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Foto & header
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: nasabah.fotoUrl != null
                      ? () => _openImageViewer(
                          context,
                          nasabah.fotoUrl!,
                          'Foto Agunan',
                        )
                      : null,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: nasabah.fotoUrl != null
                            ? Image.network(
                                nasabah.fotoUrl!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _avatarBox(statusColor),
                              )
                            : _avatarBox(statusColor),
                      ),
                      if (nasabah.fotoUrl != null)
                        Positioned(right: 4, bottom: 4, child: _zoomBadge()),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  nasabah.nama,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (nasabah.kodeNasabah != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B4F72).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      nasabah.kodeNasabah!,
                      style: const TextStyle(
                        color: Color(0xFF1B4F72),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Informasi Pribadi
          _sectionCard(
            title: 'Informasi Nasabah',
            icon: Icons.person,
            children: [
              _row('Nama', nasabah.nama),
              if (nasabah.alamat != null && nasabah.alamat!.isNotEmpty)
                _row('Alamat', nasabah.alamat!),
              if (nasabah.noHp != null && nasabah.noHp!.isNotEmpty)
                _row('No. HP', nasabah.noHp!),
              if (petugasNama != null) _row('Petugas', petugasNama),
              if (nasabah.fotoNasabahUrl != null) ...[
                const SizedBox(height: 10),
                const Text(
                  'Foto Nasabah',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _openImageViewer(
                    context,
                    nasabah.fotoNasabahUrl!,
                    'Foto Nasabah',
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          nasabah.fotoNasabahUrl!,
                          height: 140,
                          width: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        ),
                      ),
                      Positioned(right: 4, bottom: 4, child: _zoomBadge()),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // ── Informasi Agunan
          _sectionCard(
            title: 'Informasi Agunan',
            icon: Icons.inventory_2,
            children: [
              _row('Jenis Agunan', nasabah.jenisAgunan),
              if (nasabah.detailAgunan != null &&
                  nasabah.detailAgunan!.isNotEmpty)
                _row('Detail Agunan', nasabah.detailAgunan!),
            ],
          ),

          const SizedBox(height: 12),

          // ── Informasi Keuangan
          _sectionCard(
            title: 'Informasi Keuangan',
            icon: Icons.payments,
            children: [
              // FIX (fitur baru): "Pinjaman ke berapa" — 1 kalau baru
              // diajukan, otomatis naik tiap kali admin menyetujui
              // perpanjangan (lihat NasabahModel.pinjamanKe).
              _row(
                'Pinjaman Ke',
                'Ke-${nasabah.pinjamanKe}',
                valueColor: nasabah.pinjamanKe > 1
                    ? const Color(0xFFB8860B)
                    : null,
              ),
              _row('Nominal Pinjaman', fmt.format(nasabah.nominalPinjaman)),
              _row('Jumlah Pelunasan', fmt.format(nasabah.jumlahPelunasan)),
              _row(
                'Biaya Perpanjangan (20%)',
                fmt.format(nasabah.biayaPerpanjangan),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Informasi Tanggal
          _sectionCard(
            title: 'Tanggal',
            icon: Icons.calendar_today,
            children: [
              _row('Tanggal Masuk', fmtDate.format(nasabah.tanggalMasuk)),
              _row('Jatuh Tempo', fmtDate.format(nasabah.tanggalJatuhTempo)),
              // FIX (Round C): dihitung dari getter isJatuhTempo/hariTerlambat
              // (client, berbasis tanggal) supaya selalu akurat, bukan dari
              // kolom status di DB yang bisa telat ter-update.
              if (nasabah.isJatuhTempo)
                _row(
                  'Terlambat',
                  '${nasabah.hariTerlambat} hari',
                  valueColor: Colors.red,
                ),
              // ── Peringatan H-2: belum jatuh tempo, tapi tinggal 0-2 hari
              // lagi. FIX (fitur baru).
              if (nasabah.akanJatuhTempo)
                _row(
                  'Peringatan',
                  nasabah.hariMenujuJatuhTempo == 0
                      ? 'Jatuh tempo hari ini'
                      : 'Jatuh tempo ${nasabah.hariMenujuJatuhTempo} hari lagi',
                  valueColor: const Color(0xFFB8860B),
                ),
            ],
          ),

          if (nasabah.catatanPenolakan != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Catatan Penolakan',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nasabah.catatanPenolakan!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (bisaAjukanAksi) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: bisaAjukanUlang
                        ? () => _ajukanPelunasan(context, ref)
                        : null,
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Ajukan Lunas'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: const BorderSide(color: Colors.green),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => PerpanjangDialog(nasabah: nasabah),
                    ),
                    icon: const Icon(Icons.update, size: 16),
                    label: const Text('Perpanjang'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _ajukanPelunasan(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ajukan Pelunasan'),
        content: Text(
          'Ajukan pelunasan untuk nasabah ${nasabah.nama}?\n\n'
          'Pengajuan akan langsung dikirim ke admin untuk disetujui.',
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
    if (confirm != true) return;
    await ref.read(nasabahRepoProvider).ajukanPelunasan(nasabah.id);
    // FIX (Round E): providernya sudah realtime, tapi event UPDATE dari
    // Supabase Realtime tidak selalu sampai secepat itu ke sesi yang sama
    // yang baru saja menulis. Invalidate provider milik dashboard petugas
    // tepat setelah aksi kita sendiri berhasil, supaya banner "Menunggu
    // Persetujuan" langsung ter-update begitu petugas kembali ke dashboard.
    ref.invalidate(nasabahPetugasProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pengajuan pelunasan dikirim! Menunggu persetujuan admin.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// FIX (fitur baru): foto agunan & foto nasabah sekarang bisa diperbesar
  /// dengan tap — dipakai bersama admin & petugas karena keduanya memakai
  /// layar detail ini yang sama. Full-screen viewer mendukung
  /// pinch-to-zoom lewat InteractiveViewer.
  void _openImageViewer(BuildContext context, String url, String judul) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullImageViewer(url: url, judul: judul),
      ),
    );
  }

  /// Ikon kaca pembesar kecil di pojok thumbnail, sekadar penanda visual
  /// bahwa foto ini bisa di-tap untuk diperbesar.
  Widget _zoomBadge() => Container(
    padding: const EdgeInsets.all(4),
    decoration: const BoxDecoration(
      color: Colors.black54,
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.zoom_in, color: Colors.white, size: 14),
  );

  Widget _avatarBox(Color color) => Container(
    width: 120,
    height: 120,
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(Icons.inventory_2, color: color, size: 48),
  );

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF1B4F72), size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF1B4F72),
              ),
            ),
          ],
        ),
        const Divider(height: 16),
        ...children,
      ],
    ),
  );

  Widget _row(String label, String val, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            val,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: valueColor,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    ),
  );
}

/// Halaman full-screen untuk memperbesar foto agunan / foto nasabah.
/// Cubit (pinch) untuk zoom in/out, tombol X atau tombol back untuk tutup.
class _FullImageViewer extends StatelessWidget {
  final String url;
  final String judul;

  const _FullImageViewer({required this.url, required this.judul});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(judul),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: Colors.white54, size: 64),
                SizedBox(height: 12),
                Text(
                  'Gagal memuat foto',
                  style: TextStyle(color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
