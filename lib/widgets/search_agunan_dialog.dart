import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/nasabah_provider.dart';
import '../models/nasabah_model.dart';

class SearchAgunanDialog extends ConsumerStatefulWidget {
  const SearchAgunanDialog({super.key});

  @override
  ConsumerState<SearchAgunanDialog> createState() => _SearchAgunanDialogState();
}

class _SearchAgunanDialogState extends ConsumerState<SearchAgunanDialog> {
  final _ctrl = TextEditingController();
  NasabahModel? result;
  bool loading = false;
  bool sudahCari = false;
  String? error;

  // FIX: controller sebelumnya tidak pernah di-dispose (memory leak)
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final kode = _ctrl.text.trim();
    if (kode.isEmpty) return;

    setState(() {
      loading = true;
      error = null;
      result = null;
    });

    try {
      final data = await ref.read(nasabahRepoProvider).cariAgunanByKode(kode);
      // FIX: tanpa cek mounted, setState setelah dialog ditutup -> crash
      if (!mounted) return;
      setState(() {
        result = data;
        loading = false;
        sudahCari = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        sudahCari = true;
        error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final fmtDate = DateFormat('dd MMM yyyy');

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Cari Agunan'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'Kode Agunan',
                hintText: 'Contoh: TDR-2026-0001',
                prefixIcon: const Icon(Icons.qr_code),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: const Color(0xFFF2F5F9),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: loading ? null : _search,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Cari'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B4F72),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (loading) const Center(child: CircularProgressIndicator()),

            if (!loading && error != null)
              Text(
                'Terjadi kesalahan: $error',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),

            // FIX: sebelumnya tidak ada feedback kalau agunan tidak ditemukan
            if (!loading && error == null && sudahCari && result == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Agunan tidak ditemukan atau sudah lunas',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),

            if (!loading && result != null) ...[
              if (result!.fotoUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    result!.fotoUrl!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                result!.nama,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Divider(height: 20),
              _row('Kode', result!.kodeNasabah ?? '-'),
              _row('Jenis Agunan', result!.jenisAgunan),
              if (result!.detailAgunan != null)
                _row('Detail', result!.detailAgunan!),
              if (result!.petugasNama != null)
                _row('Petugas', result!.petugasNama!),
              _row('Pinjaman', fmt.format(result!.nominalPinjaman)),
              _row('Pelunasan', fmt.format(result!.jumlahPelunasan)),
              _row('Jatuh Tempo', fmtDate.format(result!.tanggalJatuhTempo)),
              _row('Status', result!.status),
            ],
          ],
        ),
      ),
      // FIX: sebelumnya dialog tidak punya tombol tutup sama sekali
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
