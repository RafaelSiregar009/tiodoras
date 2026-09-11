import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/nasabah_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/nasabah_provider.dart';
import '../../screens/nasabah_detail_screen.dart';

// FIX: dulu FutureProvider.family yang TERPISAH dari allNasabahProvider —
// meng-invalidate allNasabahProvider di layar Persetujuan tidak berpengaruh
// sama sekali ke provider ini (identitas provider berbeda), sehingga nasabah
// yang baru disetujui admin tidak pernah muncul di sini tanpa refresh
// manual. Sekarang realtime (StreamProvider.family), lihat
// streamNasabahByPetugas() di repository.
final nasabahByPetugasProvider =
    StreamProvider.family<List<NasabahModel>, String>((ref, petugasId) {
      ref.watch(profileProvider);
      return ref.watch(nasabahRepoProvider).streamNasabahByPetugas(petugasId);
    });

// FIX (fitur baru): Ringkasan sekarang bisa dilihat per bulan (dengan
// navigasi mundur/maju), jadi widget ini butuh state lokal (_selectedMonth)
// — diubah dari ConsumerWidget jadi ConsumerStatefulWidget.
class AdminNasabahPetugas extends ConsumerStatefulWidget {
  final String petugasId;
  const AdminNasabahPetugas({super.key, required this.petugasId});

  @override
  ConsumerState<AdminNasabahPetugas> createState() =>
      _AdminNasabahPetugasState();
}

class _AdminNasabahPetugasState extends ConsumerState<AdminNasabahPetugas> {
  // Bulan yang sedang ditampilkan di Ringkasan. Default = bulan berjalan
  // (perilakunya identik dengan sebelum fitur ini ada — data live/real-time).
  // Admin bisa mundur untuk melihat snapshot bulan-bulan lalu, tapi tidak
  // bisa maju melewati bulan berjalan.
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedMonth.year == now.year &&
        _selectedMonth.month == now.month;
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    if (_isCurrentMonth) return; // tidak boleh melihat bulan yang belum terjadi
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final petugasId = widget.petugasId;
    final nasabahAsync = ref.watch(nasabahByPetugasProvider(petugasId));
    final feeAsync = ref.watch(biayaPerpanjanganApprovedProvider(petugasId));
    final allPetugas = ref.watch(allPetugasProvider);
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final fmtDate = DateFormat('dd MMM yyyy');
    final fmtMonth = DateFormat('MMMM yyyy');

    // FIX (Round C): `.firstOrNull` butuh `package:collection` yang tidak
    // di-import di file ini (berisiko gagal compile tergantung apakah
    // paket itu kebetulan ter-resolve transitif atau tidak). Diganti loop
    // manual yang tidak butuh import tambahan — pola sama seperti
    // _resolvePetugasNama() di admin_approval.dart.
    final petugasNama = allPetugas.when(
      data: (list) {
        for (final p in list) {
          if (p.id == petugasId) return p.nama;
        }
        return 'Petugas';
      },
      loading: () => 'Petugas',
      error: (_, __) => 'Petugas',
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        title: Text('Nasabah: $petugasNama'),
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
      ),
      body: nasabahAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'Belum ada nasabah untuk petugas ini',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Biaya perpanjangan yang sudah disetujui admin (dari
          // FutureProvider terpisah). Selagi masih loading/error, dianggap
          // kosong dulu — begitu selesai dimuat, Storting otomatis
          // ter-update (FutureProvider akan rebuild widget ini).
          final fees = feeAsync.maybeWhen(
            data: (v) => v,
            orElse: () => const <({String nasabahId, int biaya, DateTime approvedAt})>[],
          );

          final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
          final monthEndExclusive = DateTime(
            _selectedMonth.year,
            _selectedMonth.month + 1,
            1,
          );
          bool inMonth(DateTime d) =>
              !d.isBefore(monthStart) && d.isBefore(monthEndExclusive);

          // ── Total Drop (bulan terpilih): total pinjaman yang DICAIRKAN
          // (tanggal_masuk) di bulan itu — bukan akumulasi sepanjang masa,
          // supaya benar-benar mencerminkan "bulan ini" seperti yang
          // diminta.
          final totalDrop = list
              .where((n) => inMonth(n.tanggalMasuk))
              .fold<int>(0, (s, n) => s + n.nominalPinjaman);

          // ── Nasabah berjalan "sebagaimana pada" bulan terpilih:
          // - Bulan berjalan (live): sama seperti sekarang — status belum
          //   lunas, apa adanya.
          // - Bulan lalu (snapshot historis): nasabah yang sudah dicairkan
          //   pada/sebelum akhir bulan itu, DAN belum lunas pada saat itu
          //   (tanggal_lunas null, atau baru lunas SETELAH bulan itu
          //   berakhir). Nasabah yang lunas di bulan-bulan sebelumnya
          //   otomatis tidak lagi terhitung — sesuai yang diminta.
          final berjalanList = _isCurrentMonth
              ? list.where((n) => n.status != 'lunas').toList()
              : list.where((n) {
                  final sudahDicairkan = n.tanggalMasuk.isBefore(monthEndExclusive);
                  final belumLunasSaatItu =
                      n.tanggalLunas == null ||
                      !n.tanggalLunas!.isBefore(monthEndExclusive);
                  return sudahDicairkan && belumLunasSaatItu;
                }).toList();
          final jumlahBerjalan = berjalanList.length;

          // ── Saldo (bulan terpilih) = drop + bunga 20%, HANYA yang masih
          // berjalan — dipakai field jumlah_pelunasan yang memang berisi
          // pokok + bunga.
          final saldo = berjalanList.fold<int>(
            0,
            (s, n) => s + n.jumlahPelunasan,
          );

          // ── Storting (bulan terpilih) = total pelunasan penuh (nasabah
          // yang LUNAS di bulan itu) + biaya perpanjangan yang DISETUJUI di
          // bulan itu (20% saja, tanpa pokok).
          final totalPelunasanBulanIni = list
              .where((n) => n.tanggalLunas != null && inMonth(n.tanggalLunas!))
              .fold<int>(0, (s, n) => s + n.jumlahPelunasan);
          final totalBiayaPerpanjanganBulanIni = fees
              .where((f) => inMonth(f.approvedAt))
              .fold<int>(0, (s, f) => s + f.biaya);
          final storting = totalPelunasanBulanIni + totalBiayaPerpanjanganBulanIni;

          return RefreshIndicator(
            // FIX (Round C): JANGAN invalidate StreamProvider nasabah —
            // realtime sudah auto-update; invalidate justru memutus &
            // membangun ulang koneksi Supabase realtime. Tapi allPetugas
            // (nama petugas di header) masih dari allPetugasProvider
            // (FutureProvider sekali-jalan), jadi tarik ke bawah tetap
            // menyegarkan itu — penting di APK yang tidak ada ctrl+r.
            // biayaPerpanjanganApprovedProvider juga FutureProvider biasa,
            // jadi ikut ditarik ulang di sini.
            onRefresh: () async {
              ref.invalidate(allPetugasProvider);
              ref.invalidate(biayaPerpanjanganApprovedProvider(petugasId));
            },
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // ── Navigasi bulan
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Bulan sebelumnya',
                        onPressed: _prevMonth,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            fmtMonth.format(_selectedMonth),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _isCurrentMonth ? 'Bulan berjalan' : 'Data bulan lalu',
                            style: TextStyle(
                              fontSize: 10,
                              color: _isCurrentMonth
                                  ? Colors.grey[600]
                                  : Colors.orange[800],
                              fontWeight: _isCurrentMonth
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Bulan berikutnya',
                        onPressed: _isCurrentMonth ? null : _nextMonth,
                      ),
                    ],
                  ),
                ),

                // ── Summary card
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ringkasan',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryChip(
                              'Total Drop',
                              fmt.format(totalDrop),
                              const Color(0xFF1565C0),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SummaryChip(
                              'Nasabah Berjalan',
                              '$jumlahBerjalan',
                              Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryChip(
                              'Saldo',
                              fmt.format(saldo),
                              Colors.purple,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SummaryChip(
                              'Storting',
                              fmt.format(storting),
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Saldo = pinjaman berjalan + bunga 20%. '
                        'Storting = pelunasan + biaya perpanjangan bulan ini.',
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),

                // ── List nasabah dengan badge tappable
                ...list.map(
                  (n) => _NasabahItem(nasabah: n, fmt: fmt, fmtDate: fmtDate),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Item card nasabah dengan badge yang bisa di-tap ─────────────────────────
class _NasabahItem extends StatelessWidget {
  final NasabahModel nasabah;
  final NumberFormat fmt;
  final DateFormat fmtDate;

  const _NasabahItem({
    required this.nasabah,
    required this.fmt,
    required this.fmtDate,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor = nasabah.status == 'lunas'
        ? Colors.green
        : nasabah.status == 'jatuh_tempo'
        ? Colors.red
        : const Color(0xFF1565C0);
    String statusLabel = nasabah.status == 'lunas'
        ? 'Lunas'
        : nasabah.status == 'jatuh_tempo'
        ? 'Jatuh Tempo'
        : 'Berjalan';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NasabahDetailScreen(nasabah: nasabah),
          ),
        ),
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Foto / avatar
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: nasabah.fotoUrl != null
                      ? Image.network(
                          nasabah.fotoUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatar(statusColor),
                        )
                      : _avatar(statusColor),
                ),
                const SizedBox(width: 12),
                // Info
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
                        Text(
                          nasabah.kodeNasabah!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1B4F72),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        nasabah.jenisAgunan,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Badge status — seluruh kartu sekarang juga bisa di-tap
                // (lihat InkWell pembungkus) untuk membuka NasabahDetailScreen.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 14, color: statusColor),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _info('Pinjaman', fmt.format(nasabah.nominalPinjaman)),
                _info('Pelunasan', fmt.format(nasabah.jumlahPelunasan)),
                _info('JT', fmtDate.format(nasabah.tanggalJatuhTempo)),
              ],
            ),
            // Jatuh tempo warning
            if (nasabah.status == 'jatuh_tempo') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      color: Colors.red,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Terlambat ${DateTime.now().difference(nasabah.tanggalJatuhTempo).inDays} hari',
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _avatar(Color color) => Container(
    width: 50,
    height: 50,
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
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

// ── Summary chip ─────────────────────────────────────────────────────────────
class _SummaryChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SummaryChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }
}
