import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/nasabah_model.dart';
import '../../providers/nasabah_provider.dart';

class PerpanjangDialog extends ConsumerStatefulWidget {
  final NasabahModel nasabah;
  const PerpanjangDialog({super.key, required this.nasabah});

  @override
  ConsumerState<PerpanjangDialog> createState() => _PerpanjangDialogState();
}

class _PerpanjangDialogState extends ConsumerState<PerpanjangDialog> {
  DateTime? _jatuhTempoBaru;
  bool _loading = false;

  final fmt = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final fmtDate = DateFormat('dd MMM yyyy');

  // FIX: firstDate sebelumnya DateTime.now() — kalau hari ini sudah lewat
  // dari jatuh tempo sekarang, petugas tidak bisa memilih tanggal jatuh
  // tempo baru yang lebih awal (mis. untuk koreksi). Batas bawah sekarang
  // tanggal masuk pinjaman, jadi tanggal berapa pun sejak nasabah masuk —
  // termasuk sebelum jatuh tempo yang sekarang — bisa dipilih.
  Future<void> _pickDate() async {
    final firstDate = widget.nasabah.tanggalMasuk;
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.nasabah.tanggalJatuhTempo.isBefore(firstDate)
          ? firstDate
          : widget.nasabah.tanggalJatuhTempo,
      firstDate: firstDate,
      lastDate: DateTime(2100),
      helpText: 'Pilih Jatuh Tempo Baru',
    );
    if (picked != null) setState(() => _jatuhTempoBaru = picked);
  }

  Future<void> _submit() async {
    if (_jatuhTempoBaru == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih tanggal jatuh tempo baru')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      // ← Bukan langsung perpanjang, tapi ajukan ke admin untuk disetujui
      await ref
          .read(nasabahRepoProvider)
          .ajukanPerpanjangan(
            nasabahId: widget.nasabah.id,
            nominalPinjaman: widget.nasabah.nominalPinjaman,
            jatuhTempoBaru: _jatuhTempoBaru!,
          );
      // FIX (Round E): nasabahPetugasProvider sudah realtime, tapi event
      // UPDATE dari Supabase Realtime tidak selalu sampai secepat itu ke
      // sesi yang sama yang baru saja menulis. Invalidate provider milik
      // dashboard petugas tepat setelah aksi kita sendiri berhasil.
      ref.invalidate(nasabahPetugasProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✅ Pengajuan perpanjangan dikirim! Menunggu persetujuan admin.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final biaya = widget.nasabah.biayaPerpanjangan;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Ajukan Perpanjangan',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Info nasabah
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.nasabah.nama,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'JT Sekarang: ${fmtDate.format(widget.nasabah.tanggalJatuhTempo)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Banner alur persetujuan
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Perpanjangan perlu disetujui admin sebelum berlaku.',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Biaya perpanjangan (20%)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments, color: Colors.orange),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Biaya Perpanjangan (20%)',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                    Text(
                      fmt.format(biaya),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Pilih jatuh tempo baru
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, color: Color(0xFF1B4F72)),
                  const SizedBox(width: 10),
                  Text(
                    _jatuhTempoBaru == null
                        ? 'Pilih Jatuh Tempo Baru'
                        : fmtDate.format(_jatuhTempoBaru!),
                    style: TextStyle(
                      color: _jatuhTempoBaru == null
                          ? Colors.grey
                          : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B4F72),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Ajukan'),
        ),
      ],
    );
  }
}
