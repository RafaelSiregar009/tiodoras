import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/nasabah_provider.dart';
import '../../screens/nasabah_detail_screen.dart';
import '../../widgets/nasabah_card.dart';

/// Riwayat yang terpisah dari antrean persetujuan agar pelunasan final mudah
/// ditelusuri tanpa membuat daftar pekerjaan admin terlihat masih terbuka.
class AdminNasabahLunas extends ConsumerWidget {
  const AdminNasabahLunas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lunasAsync = ref.watch(nasabahLunasProvider);
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        title: const Text('Riwayat Pelunasan'),
        backgroundColor: const Color(0xFF127044),
        foregroundColor: Colors.white,
      ),
      body: lunasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Riwayat tidak dapat dimuat: $error'),
          ),
        ),
        data: (list) {
          final total = list.fold<int>(
            0,
            (sum, nasabah) => sum + nasabah.jumlahPelunasan,
          );

          return RefreshIndicator(
            // FIX: nasabahLunasProvider sekarang realtime — jangan invalidate.
            onRefresh: () async {},
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _SummaryHero(
                  jumlahNasabah: list.length,
                  totalPelunasan: currency.format(total),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF127044),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Nasabah telah lunas',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${list.length} data',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (list.isEmpty)
                  const _EmptyPaidState()
                else
                  ...list.map(
                    (nasabah) => NasabahCard(
                      nasabah: nasabah,
                      showPerpanjang: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => NasabahDetailScreen(nasabah: nasabah),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryHero extends StatelessWidget {
  final int jumlahNasabah;
  final String totalPelunasan;

  const _SummaryHero({
    required this.jumlahNasabah,
    required this.totalPelunasan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B5C37), Color(0xFF21A366)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF127044).withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pelunasan terverifikasi',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  totalPelunasan,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$jumlahNasabah nasabah sudah menyelesaikan kewajibannya',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPaidState extends StatelessWidget {
  const _EmptyPaidState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 46, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 54, color: Colors.grey),
          SizedBox(height: 14),
          Text(
            'Belum ada pelunasan final',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Data akan muncul setelah pelunasan disetujui admin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
