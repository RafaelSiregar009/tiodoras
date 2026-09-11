import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/profile_model.dart';
import '../../providers/nasabah_provider.dart';
import '../../widgets/nasabah_card.dart';
import '../nasabah_detail_screen.dart';

class AdminNasabahList extends ConsumerWidget {
  const AdminNasabahList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nasabahAsync = ref.watch(allNasabahProvider);
    // FIX: allNasabahProvider bersumber dari stream realtime tanpa join
    // profiles(nama), jadi n.petugasNama selalu null — header grup dulu
    // selalu jatuh ke fallback generik 'Petugas'. Sekarang dicari manual
    // dari allPetugasProvider.
    final petugasAsync = ref.watch(allPetugasProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        title: const Text('Semua Nasabah'),
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
      ),
      body: nasabahAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Text(
                'Belum ada nasabah',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return RefreshIndicator(
            // FIX (Round C): allNasabahProvider sekarang realtime — jangan
            // invalidate. Tapi nama petugas (petugasAsync) masih dari
            // allPetugasProvider (FutureProvider sekali-jalan), jadi tarik
            // ke bawah tetap berguna untuk menyegarkan itu — penting di
            // APK yang tidak ada ctrl+r.
            onRefresh: () async => ref.invalidate(allPetugasProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final n = list[i];
                final petugasList = petugasAsync.valueOrNull ?? <ProfileModel>[];
                String namaPetugas(String petugasId) {
                  if (n.petugasNama != null && n.petugasNama!.isNotEmpty) {
                    return n.petugasNama!;
                  }
                  for (final p in petugasList) {
                    if (p.id == petugasId) return p.nama;
                  }
                  return 'Petugas';
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (i == 0 || list[i - 1].petugasId != n.petugasId) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 8,
                          bottom: 4,
                          left: 4,
                        ),
                        child: Text(
                          namaPetugas(n.petugasId),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                    NasabahCard(
                      nasabah: n,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NasabahDetailScreen(nasabah: n),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
