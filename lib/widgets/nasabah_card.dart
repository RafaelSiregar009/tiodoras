import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/nasabah_model.dart';
import 'status_badge.dart';
import '../screens/petugas/petugas_perpanjang.dart';

class NasabahCard extends ConsumerWidget {
  final NasabahModel nasabah;
  final VoidCallback? onTap;
  final VoidCallback? onLunas;
  final bool showPerpanjang;

  const NasabahCard({
    super.key,
    required this.nasabah,
    this.onTap,
    this.onLunas,
    this.showPerpanjang = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final fmtDate = DateFormat('dd MMM yyyy');

    // FIX (Round C): pakai getter isJatuhTempo (client, berbasis tanggal)
    // bukan kolom status di DB, supaya kartu selalu akurat walau job
    // refreshStatusJatuhTempo() belum sempat jalan.
    Color statusColor = nasabah.status == 'lunas'
        ? Colors.green
        : nasabah.isJatuhTempo
        ? Colors.red
        : const Color(0xFF1565C0);

    // BUG FIX: cek statusPelunasan dengan benar
    // FIX: alur gudang dihapus — 'konfirmasi_gudang' tidak pernah dipakai
    // lagi untuk pengajuan baru, tapi tetap dicek untuk kompatibilitas data
    // lama yang mungkin masih berstatus itu.
    final sedangPelunasan =
        nasabah.statusPelunasan == 'pengajuan_pelunasan' ||
        nasabah.statusPelunasan == 'konfirmasi_gudang';
    final sedangPerpanjangan =
        nasabah.statusPelunasan == 'pengajuan_perpanjangan';
    // FIX: pengajuan lunas/perpanjangan yang ditolak admin sekarang punya
    // status tersendiri (bukan lagi 'menunggu') supaya petugas tahu
    // pengajuannya DITOLAK, bukan masih diproses — dan supaya tombol
    // "Ajukan Lunas"/"Perpanjang" aktif lagi untuk mengajukan ulang.
    final ditolakPelunasan = nasabah.statusPelunasan == 'ditolak_pelunasan';
    final ditolakPerpanjangan =
        nasabah.statusPelunasan == 'ditolak_perpanjangan';
    final bisaAjukanUlang =
        nasabah.statusPelunasan == null ||
        ditolakPelunasan ||
        ditolakPerpanjangan;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: nasabah.isJatuhTempo
            ? const BorderSide(color: Colors.red, width: 1)
            : BorderSide.none,
      ),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: foto + nama + badge
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: nasabah.fotoUrl != null
                        ? Image.network(
                            nasabah.fotoUrl!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _avatar(statusColor),
                          )
                        : _avatar(statusColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nasabah.nama,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (nasabah.kodeNasabah != null)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B4F72).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              nasabah.kodeNasabah!,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF1B4F72),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Text(
                          nasabah.jenisAgunan,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(status: nasabah.status),
                ],
              ),

              const Divider(height: 18),

              // ── Info keuangan
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _info('Pinjaman', fmt.format(nasabah.nominalPinjaman)),
                  _info('Pelunasan', fmt.format(nasabah.jumlahPelunasan)),
                  _info(
                    'Jatuh Tempo',
                    fmtDate.format(nasabah.tanggalJatuhTempo),
                  ),
                ],
              ),

              // ── Warning jatuh tempo
              // FIX (Round C): pakai getter isJatuhTempo/hariTerlambat
              // (client, berbasis tanggal) bukan kolom status di DB.
              if (nasabah.isJatuhTempo) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        size: 14,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Terlambat ${nasabah.hariTerlambat} hari',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Peringatan H-2: belum jatuh tempo, tapi tinggal 0-2 hari
              // lagi. FIX (fitur baru): supaya petugas/admin bisa
              // mengingatkan nasabah SEBELUM telat.
              if (nasabah.akanJatuhTempo) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active,
                        size: 14,
                        color: Color(0xFFB8860B),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        nasabah.hariMenujuJatuhTempo == 0
                            ? 'Jatuh tempo hari ini'
                            : 'Jatuh tempo ${nasabah.hariMenujuJatuhTempo} hari lagi',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFB8860B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Banner status proses (menunggu admin)
              if (sedangPelunasan || sedangPerpanjangan) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: sedangPelunasan
                        ? Colors.green.withOpacity(0.08)
                        : Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sedangPelunasan
                          ? Colors.green.withOpacity(0.3)
                          : Colors.orange.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty,
                        size: 14,
                        color: sedangPelunasan ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sedangPelunasan
                              ? 'Menunggu persetujuan admin...'
                              : 'Perpanjangan menunggu persetujuan admin...',
                          style: TextStyle(
                            fontSize: 12,
                            color: sedangPelunasan
                                ? Colors.green[700]
                                : Colors.orange[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Banner ditolak admin
              // FIX: sebelumnya penolakan pelunasan/perpanjangan tidak
              // pernah terlihat sama sekali di kartu nasabah petugas.
              if (ditolakPelunasan || ditolakPerpanjangan) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.cancel, size: 14, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          [
                            ditolakPelunasan
                                ? 'Pengajuan lunas ditolak admin.'
                                : 'Pengajuan perpanjangan ditolak admin.',
                            if (nasabah.catatanPenolakan != null &&
                                nasabah.catatanPenolakan!.isNotEmpty)
                              'Alasan: ${nasabah.catatanPenolakan}',
                          ].join(' '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Tombol aksi (hanya jika tidak ada proses berjalan dan belum lunas)
              // BUG FIX: onLunas aktif jika belum ada pengajuan / pengajuan
              // sebelumnya sudah ditolak (boleh ajukan ulang).
              if (nasabah.status != 'lunas' &&
                  !sedangPelunasan &&
                  !sedangPerpanjangan) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (onLunas != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: bisaAjukanUlang ? onLunas : null,
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: const Text('Ajukan Lunas'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    if (onLunas != null && showPerpanjang)
                      const SizedBox(width: 8),
                    if (showPerpanjang)
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
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(Color color) => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(Icons.inventory_2, color: color),
  );

  Widget _info(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      Text(
        value,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ],
  );
}
