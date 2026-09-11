import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/nasabah_provider.dart';
import '../../widgets/nasabah_card.dart';

class PetugasNasabahList extends ConsumerWidget {
  const PetugasNasabahList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nasabahAsync = ref.watch(nasabahPetugasProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        title: const Text('Daftar Nasabah'),
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
                    'Belum ada nasabah',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            // FIX: nasabahPetugasProvider sekarang realtime — jangan invalidate.
            onRefresh: () async {},
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: list.length,
              itemBuilder: (_, i) => NasabahCard(
                nasabah: list[i],
                // FIX: boleh ajukan ulang setelah pengajuan sebelumnya
                // ditolak admin, tidak hanya saat statusPelunasan null.
                onLunas: (list[i].statusPelunasan == null ||
                        list[i].statusPelunasan == 'ditolak_pelunasan' ||
                        list[i].statusPelunasan == 'ditolak_perpanjangan')
                    ? () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Ajukan Pelunasan'),
                            content: Text(
                              'Ajukan pelunasan untuk ${list[i].nama}?\n'
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
                        if (confirm == true) {
                          await ref
                              .read(nasabahRepoProvider)
                              .ajukanPelunasan(list[i].id);
                          // FIX (Round E): nasabahPetugasProvider sudah
                          // realtime, tapi event UPDATE dari Supabase
                          // Realtime tidak selalu sampai secepat itu ke
                          // sesi yang sama yang baru saja menulis.
                          // Invalidate provider milik layar ini sendiri
                          // tepat setelah aksi kita sendiri berhasil.
                          ref.invalidate(nasabahPetugasProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '✅ Pengajuan pelunasan dikirim ke admin!',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      }
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }
}
