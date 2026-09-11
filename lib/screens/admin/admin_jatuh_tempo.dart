import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/nasabah_model.dart';
import '../../providers/nasabah_provider.dart';
import '../../widgets/nasabah_card.dart';
import '../nasabah_detail_screen.dart';

// FIX (Round C): halaman ini sekarang realtime (lihat
// nasabahJatuhTempoProvider di nasabah_provider.dart) — tidak perlu ctrl+r
// atau refresh manual lagi, termasuk saat sudah dibuild jadi APK. Sekaligus
// dipecah jadi 2 bagian: yang SUDAH lewat jatuh tempo, dan yang AKAN jatuh
// tempo dalam 0-2 hari (peringatan H-2).
class AdminJatuhTempo extends ConsumerWidget {
  const AdminJatuhTempo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nasabahJatuhTempoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nasabah Jatuh Tempo'),
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Tidak ada nasabah jatuh tempo'));
          }

          final sudahTelat = list.where((n) => n.isJatuhTempo).toList();
          final akanTelat = list.where((n) => n.akanJatuhTempo).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (sudahTelat.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.warning_amber,
                  color: Colors.red,
                  label: 'Sudah Jatuh Tempo (${sudahTelat.length})',
                ),
                const SizedBox(height: 8),
                ...sudahTelat.map((n) => _Item(nasabah: n)),
                const SizedBox(height: 8),
              ],
              if (akanTelat.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.notifications_active,
                  color: const Color(0xFFB8860B),
                  label: 'Akan Jatuh Tempo H-2 (${akanTelat.length})',
                ),
                const SizedBox(height: 8),
                ...akanTelat.map((n) => _Item(nasabah: n)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  final NasabahModel nasabah;
  const _Item({required this.nasabah});

  @override
  Widget build(BuildContext context) {
    return NasabahCard(
      nasabah: nasabah,
      showPerpanjang: false,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NasabahDetailScreen(nasabah: nasabah),
        ),
      ),
    );
  }
}
