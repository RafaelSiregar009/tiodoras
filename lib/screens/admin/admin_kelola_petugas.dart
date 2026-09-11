import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/profile_model.dart';
import '../../providers/nasabah_provider.dart';

/// Admin: CRUD akun petugas (tambah, ubah nama/email/password, hapus).
///
/// Operasi create/update/delete akun login dikirim ke Edge Function
/// 'manage-petugas' lewat NasabahRepository — lihat komentar di
/// nasabah_repository.dart untuk alasannya.
class AdminKelolaPetugas extends ConsumerWidget {
  const AdminKelolaPetugas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final petugasAsync = ref.watch(allPetugasProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        title: const Text('Kelola Petugas'),
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
      ),
      body: petugasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.badge_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'Belum ada akun petugas',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allPetugasProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: list.length,
              itemBuilder: (_, i) =>
                  _PetugasTile(petugas: list[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFormDialog(context, ref),
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Tambah Petugas'),
      ),
    );
  }
}

class _PetugasTile extends ConsumerWidget {
  final ProfileModel petugas;
  const _PetugasTile({required this.petugas});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 6,
        ),
        // FIX (fitur baru): tampilkan foto profil petugas kalau admin sudah
        // pernah mengaturnya (lewat dialog tambah/ubah petugas di bawah),
        // fallback ke huruf pertama nama seperti sebelumnya kalau belum ada.
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF1B4F72),
          backgroundImage: petugas.avatarUrl != null
              ? NetworkImage(petugas.avatarUrl!)
              : null,
          child: petugas.avatarUrl != null
              ? null
              : Text(
                  petugas.nama.isNotEmpty
                      ? petugas.nama[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
        title: Text(
          petugas.nama,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        // FIX (fitur baru): tampilkan No. HP di bawah nama kalau sudah
        // diisi, supaya admin bisa lihat sekilas tanpa buka dialog ubah.
        subtitle: Text(
          petugas.noHp != null && petugas.noHp!.isNotEmpty
              ? petugas.noHp!
              : 'Petugas',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Color(0xFF1B4F72)),
              tooltip: 'Ubah',
              onPressed: () => _showFormDialog(
                context,
                ref,
                existing: petugas,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Hapus',
              onPressed: () => _confirmHapus(context, ref, petugas),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmHapus(
    BuildContext context,
    WidgetRef ref,
    ProfileModel p,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Akun Petugas'),
        content: Text(
          'Hapus akun petugas "${p.nama}"? Akun ini tidak akan bisa login lagi.\n\n'
          'Jika petugas ini masih memiliki data nasabah, penghapusan akan '
          'ditolak sampai data nasabahnya diselesaikan/dipindahkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(nasabahRepoProvider).hapusPetugas(p.id);
      ref.invalidate(allPetugasProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Akun ${p.nama} dihapus'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghapus: ${_cleanError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ── Dialog tambah / ubah petugas ────────────────────────────────────────────
Future<void> _showFormDialog(
  BuildContext context,
  WidgetRef ref, {
  ProfileModel? existing,
}) async {
  final isEdit = existing != null;
  final namaCtrl = TextEditingController(text: existing?.nama ?? '');
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  // FIX (fitur baru): field profil tambahan petugas, prefill dari data lama
  // kalau sedang ubah akun.
  final noHpCtrl = TextEditingController(text: existing?.noHp ?? '');
  final nikCtrl = TextEditingController(text: existing?.nik ?? '');
  bool loading = false;
  bool obscure = true;
  // FIX (fitur baru): foto profil petugas yang dipilih admin di dialog ini.
  // Null berarti tidak ganti foto (saat ubah, foto lama tetap dipakai).
  Uint8List? avatarBytes;

  Future<void> pickAvatar(void Function(void Function()) setState) async {
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
    if (img != null) {
      final bytes = await img.readAsBytes();
      setState(() => avatarBytes = bytes);
    }
  }

  await showDialog(
    context: context,
    barrierDismissible: !loading,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isEdit ? 'Ubah Akun Petugas' : 'Tambah Petugas'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Foto profil (opsional)
              Center(
                child: GestureDetector(
                  onTap: () => pickAvatar(setState),
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: const Color(0xFF1B4F72),
                        backgroundImage: avatarBytes != null
                            ? MemoryImage(avatarBytes!)
                            : (existing?.avatarUrl != null
                                  ? NetworkImage(existing!.avatarUrl!)
                                        as ImageProvider
                                  : null),
                        child:
                            avatarBytes == null && existing?.avatarUrl == null
                            ? Text(
                                namaCtrl.text.isNotEmpty
                                    ? namaCtrl.text[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1B4F72),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'Foto profil (opsional)',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: namaCtrl,
                decoration: InputDecoration(
                  labelText: 'Nama',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: isEdit ? 'Email baru (opsional)' : 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: isEdit
                      ? 'Password baru (opsional)'
                      : 'Password (min. 6 karakter)',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noHpCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'No. HP / Telepon',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nikCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'NIK / No. KTP',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (isEdit) ...[
                const SizedBox(height: 8),
                const Text(
                  'Kosongkan email/password kalau tidak ingin diubah.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: loading ? null : () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: loading
                ? null
                : () async {
                    final nama = namaCtrl.text.trim();
                    final email = emailCtrl.text.trim();
                    final pass = passCtrl.text;
                    final noHp = noHpCtrl.text.trim();
                    final nik = nikCtrl.text.trim();

                    if (nama.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Nama wajib diisi')),
                      );
                      return;
                    }
                    if (!isEdit && (email.isEmpty || pass.isEmpty)) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Email dan password wajib diisi'),
                        ),
                      );
                      return;
                    }

                    setState(() => loading = true);
                    try {
                      final repo = ref.read(nasabahRepoProvider);
                      // FIX (fitur baru): kalau admin memilih foto baru,
                      // upload dulu ke Storage (dari sesi admin yang sedang
                      // login) baru kirim URL-nya ke Edge Function
                      // manage-petugas untuk disimpan ke baris profil
                      // petugas — service_role tetap hanya dipakai di
                      // server, sesuai aturan yang sudah ada.
                      String? avatarUrl;
                      if (avatarBytes != null) {
                        avatarUrl = await repo.uploadAvatar(
                          avatarBytes!,
                          isEdit ? existing.id : nama,
                        );
                      }
                      if (isEdit) {
                        await repo.updatePetugas(
                          id: existing.id,
                          nama: nama,
                          email: email.isEmpty ? null : email,
                          password: pass.isEmpty ? null : pass,
                          avatarUrl: avatarUrl,
                          noHp: noHp,
                          nik: nik,
                        );
                      } else {
                        await repo.tambahPetugas(
                          nama: nama,
                          email: email,
                          password: pass,
                          avatarUrl: avatarUrl,
                          noHp: noHp.isEmpty ? null : noHp,
                          nik: nik.isEmpty ? null : nik,
                        );
                      }
                      ref.invalidate(allPetugasProvider);
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isEdit
                                  ? '✅ Akun $nama diperbarui'
                                  : '✅ Akun petugas $nama dibuat',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      setState(() => loading = false);
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text('Gagal: ${_cleanError(e)}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B4F72),
              foregroundColor: Colors.white,
            ),
            child: loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(isEdit ? 'Simpan' : 'Tambah'),
          ),
        ],
      ),
    ),
  );

  namaCtrl.dispose();
  emailCtrl.dispose();
  passCtrl.dispose();
  noHpCtrl.dispose();
  nikCtrl.dispose();
}

String _cleanError(Object e) {
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring('Exception: '.length) : s;
}
