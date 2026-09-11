import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../providers/nasabah_provider.dart';

// ── Formatter akuntansi: otomatis tambah titik ribuan saat mengetik ──────────
class _ThousandFormatter extends TextInputFormatter {
  final _fmt = NumberFormat('#,###', 'id_ID');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    // Hapus semua karakter non-digit
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final number = int.tryParse(digits) ?? 0;
    // Batasi maksimum 1 miliar
    final clamped = number > 1000000000 ? 1000000000 : number;
    final formatted = _fmt.format(clamped);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PetugasTambahNasabah extends ConsumerStatefulWidget {
  const PetugasTambahNasabah({super.key});

  @override
  ConsumerState<PetugasTambahNasabah> createState() => _State();
}

class _State extends ConsumerState<PetugasTambahNasabah> {
  final _formKey = GlobalKey<FormState>();
  final _namaCtrl = TextEditingController();
  final _alamatCtrl = TextEditingController();
  final _noHpCtrl = TextEditingController();
  final _pinjamanCtrl = TextEditingController();
  final _agunanCtrl = TextEditingController();
  final _detailAgunanCtrl = TextEditingController();
  final _pelunasanCtrl = TextEditingController();
  DateTime? _tanggalMasuk;
  DateTime? _tanggalJatuhTempo;
  Uint8List? _fotoBytes;
  Uint8List? _fotoNasabahBytes;
  bool _loading = false;

  // FIX: Jumlah pelunasan otomatis terisi 120% dari nominal pinjaman
  // (pokok + 20%) setiap kali nominal pinjaman diketik. Field ini tetap
  // bisa diubah manual — begitu diubah manual, auto-isi berhenti supaya
  // tidak menimpa angka yang sudah sengaja diubah petugas. Kalau field
  // dikosongkan lagi, auto-isi aktif kembali.
  bool _pelunasanManual = false;
  bool _syncingPelunasan = false;

  @override
  void initState() {
    super.initState();
    _pinjamanCtrl.addListener(_autoFillPelunasan);
    _pelunasanCtrl.addListener(_onPelunasanEdited);
  }

  void _onPelunasanEdited() {
    if (_syncingPelunasan) return; // perubahan dari auto-fill, abaikan
    _pelunasanManual = _pelunasanCtrl.text.isNotEmpty;
  }

  void _autoFillPelunasan() {
    if (_pelunasanManual) return;
    final pinjaman = _parseRupiah(_pinjamanCtrl.text);
    final pelunasan = (pinjaman * 1.2).round();
    final formatted = pelunasan == 0
        ? ''
        : NumberFormat('#,###', 'id_ID').format(pelunasan);
    _syncingPelunasan = true;
    _pelunasanCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _syncingPelunasan = false;
  }

  @override
  void dispose() {
    _namaCtrl.dispose();
    _alamatCtrl.dispose();
    _noHpCtrl.dispose();
    _pinjamanCtrl.dispose();
    _agunanCtrl.dispose();
    _detailAgunanCtrl.dispose();
    _pelunasanCtrl.dispose();
    super.dispose();
  }

  // Parse angka dari format akuntansi (hapus titik ribuan)
  int _parseRupiah(String val) {
    return int.tryParse(val.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  Future<void> _pickDate(bool isMasuk) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isMasuk ? now : (_tanggalMasuk ?? now),
      firstDate: isMasuk ? now : (_tanggalMasuk ?? now),
      lastDate: DateTime(2100),
      helpText: isMasuk ? 'Pilih Tanggal Masuk' : 'Pilih Tanggal Jatuh Tempo',
    );
    if (picked != null) {
      setState(() {
        if (isMasuk) {
          _tanggalMasuk = picked;
        } else {
          _tanggalJatuhTempo = picked;
        }
      });
    }
  }

  // FIX: dipakai untuk dua foto (agunan & nasabah) — `onPicked` menentukan
  // state mana yang diisi.
  Future<void> _pickFotoGeneric(void Function(Uint8List bytes) onPicked) async {
    final picker = ImagePicker();
    final picked = await showModalBottomSheet<ImageSource>(
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
    if (picked != null) {
      final img = await picker.pickImage(source: picked, imageQuality: 70);
      if (img != null) {
        final bytes = await img.readAsBytes();
        setState(() => onPicked(bytes));
      }
    }
  }

  Future<void> _pickFoto() => _pickFotoGeneric((b) => _fotoBytes = b);

  Future<void> _pickFotoNasabah() =>
      _pickFotoGeneric((b) => _fotoNasabahBytes = b);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // FIX: semua data yang diisi petugas saat mengajukan nasabah wajib
    // diisi — termasuk kedua foto, yang sebelumnya opsional. Foto bukan
    // bagian dari Form/TextFormField jadi divalidasi manual di sini,
    // sebelum data dikirim.
    if (_fotoBytes == null || _fotoNasabahBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi foto agunan & foto nasabah')),
      );
      return;
    }
    if (_tanggalMasuk == null || _tanggalJatuhTempo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi tanggal masuk & jatuh tempo')),
      );
      return;
    }
    final pinjaman = _parseRupiah(_pinjamanCtrl.text);
    final pelunasan = _parseRupiah(_pelunasanCtrl.text);
    if (pinjaman == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal pinjaman tidak valid')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref
          .read(nasabahRepoProvider)
          .tambahNasabah(
            nama: _namaCtrl.text.trim(),
            alamat: _alamatCtrl.text.trim().isEmpty
                ? null
                : _alamatCtrl.text.trim(),
            noHp: _noHpCtrl.text.trim().isEmpty ? null : _noHpCtrl.text.trim(),
            nominalPinjaman: pinjaman,
            jenisAgunan: _agunanCtrl.text.trim(),
            detailAgunan: _detailAgunanCtrl.text.trim().isEmpty
                ? null
                : _detailAgunanCtrl.text.trim(),
            jumlahPelunasan: pelunasan,
            tanggalMasuk: _tanggalMasuk!,
            tanggalJatuhTempo: _tanggalJatuhTempo!,
            foto: _fotoBytes,
            fotoNasabah: _fotoNasabahBytes,
          );
      // FIX (Round E): nasabahPetugasProvider & antreianNasabahProvider
      // sekarang realtime, tapi event INSERT dari Supabase Realtime tidak
      // selalu sampai secepat itu ke SESI YANG SAMA yang baru saja
      // menulis — akibatnya nasabah yang baru diajukan kadang belum
      // langsung muncul di banner "Menunggu Konfirmasi" pada dashboard
      // sampai di-refresh manual. Invalidate provider antrean SENDIRI
      // tepat setelah aksi kita sendiri berhasil (bukan invalidate pasif
      // dari layar lain) memastikan itu langsung ter-update — sama
      // seperti perbaikan di admin_approval.dart.
      ref.invalidate(antreianNasabahProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Pengajuan berhasil! Menunggu persetujuan admin.'),
          backgroundColor: Colors.green,
        ),
      );
      context.pop();
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
    final fmtDate = DateFormat('dd MMM yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        title: const Text('Tambah Nasabah'),
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Banner alur
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pengajuan akan dikonfirmasi Admin sebelum aktif',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Foto agunan & foto nasabah (dua foto terpisah, WAJIB diisi)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text(
                'Foto Agunan & Foto Nasabah (wajib diisi)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[700],
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _fotoBox(
                    bytes: _fotoBytes,
                    label: 'Foto Agunan',
                    onTap: _pickFoto,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _fotoBox(
                    bytes: _fotoNasabahBytes,
                    label: 'Foto Nasabah',
                    onTap: _pickFotoNasabah,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Data Nasabah
            _sectionLabel('Data Nasabah'),
            _buildCard([
              _field(_namaCtrl, 'Nama Nasabah', Icons.person),
              _field(
                _alamatCtrl,
                'Alamat',
                Icons.location_on_outlined,
                maxLines: 2,
              ),
              _field(
                _noHpCtrl,
                'No. HP',
                Icons.phone_outlined,
                inputType: TextInputType.phone,
              ),
            ]),
            const SizedBox(height: 12),

            // ── Data Keuangan
            _sectionLabel('Data Keuangan'),
            _buildCard([
              _rupiahField(_pinjamanCtrl, 'Nominal Pinjaman', Icons.payments),
              _rupiahField(
                _pelunasanCtrl,
                'Jumlah yang Harus Dilunasi',
                Icons.price_check,
                helperText: 'Otomatis 120% dari pokok — bisa diubah manual',
              ),
            ]),
            const SizedBox(height: 12),

            // ── Data Agunan
            _sectionLabel('Data Agunan'),
            _buildCard([
              _field(_agunanCtrl, 'Jenis Agunan', Icons.inventory_2),
              _field(
                _detailAgunanCtrl,
                'Detail Agunan (No. Polisi, No. Seri, dsb)',
                Icons.info_outline,
              ),
            ]),
            const SizedBox(height: 12),

            // ── Tanggal
            _sectionLabel('Tanggal'),
            _buildCard([
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.calendar_today,
                  color: Color(0xFF1B4F72),
                ),
                title: Text(
                  _tanggalMasuk == null
                      ? 'Tanggal Masuk'
                      : fmtDate.format(_tanggalMasuk!),
                  style: TextStyle(
                    color: _tanggalMasuk == null ? Colors.grey : Colors.black,
                  ),
                ),
                subtitle: const Text(
                  'Tidak bisa mundur dari hari ini',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickDate(true),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event, color: Colors.orange),
                title: Text(
                  _tanggalJatuhTempo == null
                      ? 'Tanggal Jatuh Tempo'
                      : fmtDate.format(_tanggalJatuhTempo!),
                  style: TextStyle(
                    color: _tanggalJatuhTempo == null
                        ? Colors.grey
                        : Colors.black,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickDate(false),
              ),
            ]),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4F72),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'AJUKAN NASABAH',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Kotak pemilih foto (dipakai untuk foto agunan & foto nasabah)
  Widget _fotoBox({
    required Uint8List? bytes,
    required String label,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: bytes != null ? const Color(0xFF1B4F72) : Colors.grey.shade300,
        ),
      ),
      child: bytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(bytes, fit: BoxFit.cover),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt, size: 32, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ),
              ],
            ),
    ),
  );

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 4),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.grey,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _buildCard(List<Widget> children) => Container(
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
    child: Column(children: children),
  );

  // Field rupiah dengan format akuntansi otomatis
  Widget _rupiahField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    String? helperText,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [_ThousandFormatter()],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        prefixText: 'Rp  ',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: const Color(0xFFF2F5F9),
        helperText: helperText ?? 'Maks. Rp 1.000.000.000',
        helperStyle: const TextStyle(fontSize: 10),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Wajib diisi';
        final val = _parseRupiah(v);
        if (val == 0) return 'Nominal tidak valid';
        return null;
      },
    ),
  );

  // Field teks biasa
  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = true,
    TextInputType inputType = TextInputType.text,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: ctrl,
      keyboardType: inputType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: maxLines == 1 ? Icon(icon) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: const Color(0xFFF2F5F9),
      ),
      validator: required
          ? (v) => v == null || v.isEmpty ? 'Wajib diisi' : null
          : null,
    ),
  );
}
