import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/nasabah_model.dart';
import '../../models/profile_model.dart';
import '../../providers/nasabah_provider.dart';
import '../nasabah_detail_screen.dart';

// FIX: n.petugasNama SELALU null di sini — kartu-kartu di layar ini
// bersumber dari StreamProvider realtime (streamAntreianAdmin() dkk) yang
// TIDAK bisa memakai join `profiles(nama)` (keterbatasan Supabase
// Realtime .stream()). Sebelumnya field "Petugas" pada kartu pengajuan
// selalu tampil '-'. Sekarang dicari manual dari allPetugasProvider
// berdasarkan petugasId.
String _resolvePetugasNama(
  AsyncValue<List<ProfileModel>> petugasAsync,
  NasabahModel n,
) {
  if (n.petugasNama != null && n.petugasNama!.isNotEmpty) {
    return n.petugasNama!;
  }
  final list = petugasAsync.valueOrNull;
  if (list == null) return '...';
  for (final p in list) {
    if (p.id == n.petugasId) return p.nama;
  }
  return '-';
}

class AdminApproval extends ConsumerStatefulWidget {
  const AdminApproval({super.key});

  @override
  ConsumerState<AdminApproval> createState() => _AdminApprovalState();
}

class _AdminApprovalState extends ConsumerState<AdminApproval>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── 3 stream realtime
    final nasabahBaru = ref.watch(antreianAdminStreamProvider);
    final pelunasan = ref.watch(pelunasanAdminStreamProvider);
    final perpanjangan = ref.watch(perpanjanganAdminStreamProvider);

    final countBaru = nasabahBaru.value?.length ?? 0;
    final countLunas = pelunasan.value?.length ?? 0;
    final countPerpanjang = perpanjangan.value?.length ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        title: const Text('Persetujuan'),
        backgroundColor: const Color(0xFF1B4F72),
        foregroundColor: Colors.white,
        // FIX (Round C): tab-tab di layar ini sudah realtime (StreamProvider),
        // tapi nama petugas yang ditampilkan di kartu bersumber dari
        // allPetugasProvider (FutureProvider sekali-jalan) — kalau ada
        // petugas baru/nama diubah setelah layar ini dibuka, namanya baru
        // muncul setelah restart aplikasi. Tombol ini memberi cara manual
        // untuk menyegarkannya, penting terutama di APK yang tidak punya
        // ctrl+r.
        actions: [
          IconButton(
            tooltip: 'Segarkan data petugas',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(allPetugasProvider);
              _showSnackbar(context, 'Data disegarkan', const Color(0xFF1B4F72));
            },
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: const Color(0xFFC9A84C),
          indicatorWeight: 3,
          tabs: [
            Tab(child: _TabLabel('Nasabah Baru', countBaru, Colors.blue)),
            Tab(child: _TabLabel('Pelunasan', countLunas, Colors.green)),
            Tab(
              child: _TabLabel('Perpanjangan', countPerpanjang, Colors.orange),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // ── TAB 1: Nasabah Baru
          _NasabahBaruTab(nasabahBaru),
          // ── TAB 2: Pelunasan
          _PelunasanTab(pelunasan),
          // ── TAB 3: Perpanjangan
          _PerpanjanganTab(perpanjangan),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// TAB LABEL dengan badge
// ──────────────────────────────────────────────────────────────────────────────
class _TabLabel extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _TabLabel(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// TAB 1 — Nasabah Baru
// ──────────────────────────────────────────────────────────────────────────────
class _NasabahBaruTab extends ConsumerWidget {
  final AsyncValue<List<NasabahModel>> async;
  const _NasabahBaruTab(this.async);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final fmtDate = DateFormat('dd MMM yyyy');
    final petugasAsync = ref.watch(allPetugasProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(e.toString()),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyView(
            'Tidak ada nasabah baru menunggu persetujuan',
            Icons.people_outline,
            Colors.blue,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: list.length,
          itemBuilder: (_, i) => _NasabahBaruCard(
            nasabah: list[i],
            petugasNama: _resolvePetugasNama(petugasAsync, list[i]),
            fmt: fmt,
            fmtDate: fmtDate,
            onApprove: () => _approve(context, ref, list[i]),
            onTolak: () => _showTolakDialog(context, ref, list[i]),
          ),
        );
      },
    );
  }

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    NasabahModel n,
  ) async {
    final confirm = await _confirmDialog(
      context,
      title: 'Setujui Nasabah',
      content:
          'Setujui pengajuan atas nama ${n.nama}?\nNasabah akan aktif dan masuk ke dashboard petugas.',
      confirmLabel: 'Setujui',
      confirmColor: const Color(0xFF1B4F72),
    );
    if (confirm == true) {
      await ref.read(nasabahRepoProvider).approveAdmin(n.id);
      // FIX (Round D): allNasabahProvider dkk sudah realtime dan TIDAK
      // di-invalidate di sini (itu tetap benar — layar lain otomatis
      // update sendiri). TAPI antreianAdminStreamProvider — antrean di TAB
      // INI sendiri — dilaporkan kadang tidak langsung hilang dari daftar
      // setelah disetujui/ditolak walau baris nasabah-nya sudah berubah di
      // DB (kemungkinan event UPDATE dari Supabase Realtime tidak selalu
      // sampai secepat INSERT). Invalidate provider milik TAB INI SENDIRI
      // tepat setelah aksi kita sendiri berhasil aman dilakukan — beda
      // dengan invalidate "pasif" dari layar lain yang cuma menonton (itu
      // yang dilarang) — ini "refresh setelah aksi sendiri", pola standar.
      ref.invalidate(antreianAdminStreamProvider);
      if (context.mounted) {
        _showSnackbar(
          context,
          '✅ Nasabah disetujui dan sudah aktif!',
          Colors.green,
        );
      }
    }
  }

  Future<void> _showTolakDialog(
    BuildContext context,
    WidgetRef ref,
    NasabahModel n,
  ) async {
    final catatan = await _promptTolakCatatan(
      context,
      title: 'Tolak Pengajuan',
      message: 'Tolak pengajuan atas nama ${n.nama}?',
    );
    if (catatan == null) return;
    await ref.read(nasabahRepoProvider).tolakNasabah(n.id, catatan);
    // FIX (Round D): lihat komentar di _approve() di atas.
    ref.invalidate(antreianAdminStreamProvider);
    if (context.mounted) {
      _showSnackbar(context, 'Pengajuan ditolak', Colors.red);
    }
  }
}

class _NasabahBaruCard extends StatelessWidget {
  final NasabahModel nasabah;
  final String petugasNama;
  final NumberFormat fmt;
  final DateFormat fmtDate;
  final VoidCallback onApprove;
  final VoidCallback onTolak;

  const _NasabahBaruCard({
    required this.nasabah,
    required this.petugasNama,
    required this.fmt,
    required this.fmtDate,
    required this.onApprove,
    required this.onTolak,
  });

  @override
  Widget build(BuildContext context) {
    final n = nasabah;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      // FIX: kartu sekarang bisa di-tap untuk melihat detail lengkap
      // nasabah (foto, alamat, no HP, dll — tidak semua tampil di kartu
      // ringkas ini). Tombol Setujui/Tolak tetap berfungsi langsung dari
      // list tanpa perlu masuk ke detail dulu.
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NasabahDetailScreen(nasabah: n)),
        ),
        child: Column(
        children: [
          // ── Header berwarna
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFF1B4F72),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: n.fotoUrl != null
                      ? Image.network(
                          n.fotoUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatar(),
                        )
                      : _avatar(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.nama,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        n.kodeNasabah ?? 'Menunggu kode...',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Baru',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Body detail
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _infoGrid([
                  _InfoItem('Petugas', petugasNama, Icons.person),
                  _InfoItem('Jenis Agunan', n.jenisAgunan, Icons.inventory_2),
                  _InfoItem(
                    'Pinjaman',
                    fmt.format(n.nominalPinjaman),
                    Icons.payments,
                  ),
                  _InfoItem(
                    'Pelunasan',
                    fmt.format(n.jumlahPelunasan),
                    Icons.price_check,
                  ),
                  _InfoItem(
                    'Tgl Masuk',
                    fmtDate.format(n.tanggalMasuk),
                    Icons.calendar_today,
                  ),
                  _InfoItem(
                    'Jatuh Tempo',
                    fmtDate.format(n.tanggalJatuhTempo),
                    Icons.event,
                  ),
                ]),
                if (n.fotoNasabahUrl != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.badge_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      const Text(
                        'Foto Nasabah',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      n.fotoNasabahUrl!,
                      height: 100,
                      width: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                ],
                if (n.detailAgunan != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Detail: ${n.detailAgunan}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onTolak,
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('Tolak'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: onApprove,
                        icon: const Icon(Icons.check_circle, size: 16),
                        label: const Text('Setujui Nasabah'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B4F72),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _avatar() => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.inventory_2, color: Colors.white),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// TAB 2 — Pelunasan
// ──────────────────────────────────────────────────────────────────────────────
class _PelunasanTab extends ConsumerWidget {
  final AsyncValue<List<NasabahModel>> async;
  const _PelunasanTab(this.async);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final fmtDate = DateFormat('dd MMM yyyy');
    final petugasAsync = ref.watch(allPetugasProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(e.toString()),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyView(
            'Tidak ada pengajuan pelunasan',
            Icons.check_circle_outline,
            Colors.green,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final n = list[i];
            return _ApprovalCard(
              nasabah: n,
              petugasNama: _resolvePetugasNama(petugasAsync, n),
              fmt: fmt,
              fmtDate: fmtDate,
              accentColor: Colors.green,
              icon: Icons.payments,
              badgeLabel: 'Petugas ✓',
              statusLabel: 'Pengajuan Pelunasan',
              actionLabel: 'Setujui Pelunasan',
              onAction: () => _approvePelunasan(context, ref, n),
              onTolak: () => _tolakPelunasan(context, ref, n),
            );
          },
        );
      },
    );
  }

  Future<void> _approvePelunasan(
    BuildContext context,
    WidgetRef ref,
    NasabahModel n,
  ) async {
    final confirm = await _confirmDialog(
      context,
      title: 'Setujui Pelunasan',
      content:
          'Setujui pelunasan untuk nasabah ${n.nama}?\nStatus akan berubah menjadi Lunas.',
      confirmLabel: 'Setujui',
      confirmColor: Colors.green,
    );
    if (confirm == true) {
      await ref.read(nasabahRepoProvider).approveAdminPelunasan(n.id);

      // FIX (Round D): allNasabahProvider & nasabahLunasProvider (dipakai
      // layar LAIN) tetap TIDAK di-invalidate di sini — itu sudah benar,
      // realtime cukup untuk mereka. Tapi antrean di TAB INI SENDIRI
      // (pelunasanAdminStreamProvider) dilaporkan admin kadang tidak
      // langsung hilang dari daftar setelah disetujui. Invalidate provider
      // milik tab ini sendiri, tepat setelah aksi kita sendiri berhasil,
      // supaya dijamin ter-update — beda dengan invalidate "pasif" dari
      // layar lain yang cuma menonton (itu yang dilarang).
      ref.invalidate(pelunasanAdminStreamProvider);
      if (context.mounted) {
        _showSnackbar(
          context,
          '✅ Pelunasan disetujui! Nasabah sudah Lunas.',
          Colors.green,
        );
      }
    }
  }

  Future<void> _tolakPelunasan(
    BuildContext context,
    WidgetRef ref,
    NasabahModel n,
  ) async {
    final catatan = await _promptTolakCatatan(
      context,
      title: 'Tolak Pelunasan',
      message: 'Tolak pengajuan pelunasan untuk ${n.nama}?',
    );
    if (catatan == null) return;
    await ref.read(nasabahRepoProvider).tolakPelunasan(n.id, catatan);
    // FIX (Round D): lihat komentar di _approvePelunasan() di atas.
    ref.invalidate(pelunasanAdminStreamProvider);
    if (context.mounted) {
      _showSnackbar(context, 'Pengajuan pelunasan ditolak', Colors.red);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// TAB 3 — Perpanjangan
// ──────────────────────────────────────────────────────────────────────────────
class _PerpanjanganTab extends ConsumerWidget {
  final AsyncValue<List<NasabahModel>> async;
  const _PerpanjanganTab(this.async);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final fmtDate = DateFormat('dd MMM yyyy');
    final petugasAsync = ref.watch(allPetugasProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(e.toString()),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyView(
            'Tidak ada pengajuan perpanjangan',
            Icons.update,
            Colors.orange,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final n = list[i];
            return _ApprovalCard(
              nasabah: n,
              petugasNama: _resolvePetugasNama(petugasAsync, n),
              fmt: fmt,
              fmtDate: fmtDate,
              accentColor: Colors.orange,
              icon: Icons.update,
              badgeLabel: 'Petugas ✓',
              statusLabel: 'Pengajuan Perpanjangan',
              actionLabel: 'Setujui Perpanjangan',
              onAction: () => _approvePerpanjangan(context, ref, n),
              onTolak: () => _tolakPerpanjangan(context, ref, n),
              extraInfo:
                  'Biaya Perpanjangan: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(n.biayaPerpanjangan)}',
            );
          },
        );
      },
    );
  }

  Future<void> _approvePerpanjangan(
    BuildContext context,
    WidgetRef ref,
    NasabahModel n,
  ) async {
    final confirm = await _confirmDialog(
      context,
      title: 'Setujui Perpanjangan',
      content:
          'Setujui perpanjangan untuk nasabah ${n.nama}?\nJatuh tempo akan diperbarui.',
      confirmLabel: 'Setujui',
      confirmColor: Colors.orange,
    );
    if (confirm == true) {
      await ref.read(nasabahRepoProvider).approveAdminPerpanjangan(n.id);
      // FIX (Round D): allNasabahProvider (dipakai layar LAIN) tetap TIDAK
      // di-invalidate — itu sudah benar. Tapi antrean di TAB INI SENDIRI
      // (perpanjanganAdminStreamProvider) dilaporkan admin kadang tidak
      // langsung hilang setelah disetujui. Invalidate provider milik tab
      // ini sendiri tepat setelah aksi kita sendiri berhasil, supaya
      // dijamin ter-update.
      ref.invalidate(perpanjanganAdminStreamProvider);
      // FIX (fitur baru): biaya perpanjangan yang baru saja disetujui ini
      // harus langsung ikut terhitung di "Storting" bulan berjalan pada
      // halaman detail petugas — provider itu FutureProvider biasa
      // (bukan realtime), jadi perlu di-invalidate manual di sini.
      ref.invalidate(biayaPerpanjanganApprovedProvider(n.petugasId));
      if (context.mounted) {
        _showSnackbar(
          context,
          '✅ Perpanjangan disetujui! Jatuh tempo diperbarui.',
          Colors.orange,
        );
      }
    }
  }

  Future<void> _tolakPerpanjangan(
    BuildContext context,
    WidgetRef ref,
    NasabahModel n,
  ) async {
    final catatan = await _promptTolakCatatan(
      context,
      title: 'Tolak Perpanjangan',
      message: 'Tolak pengajuan perpanjangan untuk ${n.nama}?',
    );
    if (catatan == null) return;
    await ref.read(nasabahRepoProvider).tolakPerpanjangan(n.id, catatan);
    // FIX (Round D): lihat komentar di _approvePerpanjangan() di atas.
    ref.invalidate(perpanjanganAdminStreamProvider);
    if (context.mounted) {
      _showSnackbar(context, 'Pengajuan perpanjangan ditolak', Colors.red);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Generic Approval Card (untuk Pelunasan & Perpanjangan)
// ──────────────────────────────────────────────────────────────────────────────
class _ApprovalCard extends StatelessWidget {
  final NasabahModel nasabah;
  final String petugasNama;
  final NumberFormat fmt;
  final DateFormat fmtDate;
  final Color accentColor;
  final IconData icon;
  final String badgeLabel;
  final String statusLabel;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onTolak;
  final String? extraInfo;

  const _ApprovalCard({
    required this.nasabah,
    required this.petugasNama,
    required this.fmt,
    required this.fmtDate,
    required this.accentColor,
    required this.icon,
    required this.badgeLabel,
    required this.statusLabel,
    required this.actionLabel,
    required this.onAction,
    this.onTolak,
    this.extraInfo,
  });

  @override
  Widget build(BuildContext context) {
    final n = nasabah;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      // FIX: kartu sekarang bisa di-tap untuk melihat detail lengkap
      // nasabah. Tombol aksi di bawah tetap berfungsi langsung dari list.
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => NasabahDetailScreen(nasabah: n)),
        ),
        child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(color: accentColor.withOpacity(0.2)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.nama,
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        n.kodeNasabah ?? '-',
                        style: TextStyle(
                          color: accentColor.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badgeLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _infoGrid([
                  _InfoItem('Petugas', petugasNama, Icons.person),
                  _InfoItem('Agunan', n.jenisAgunan, Icons.inventory_2),
                  _InfoItem(
                    'Pinjaman',
                    fmt.format(n.nominalPinjaman),
                    Icons.payments,
                  ),
                  _InfoItem(
                    'Pelunasan',
                    fmt.format(n.jumlahPelunasan),
                    Icons.price_check,
                  ),
                  _InfoItem(
                    'JT Saat ini',
                    fmtDate.format(n.tanggalJatuhTempo),
                    Icons.event,
                  ),
                ]),
                if (extraInfo != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accentColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: accentColor, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          extraInfo!,
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (onTolak != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onTolak,
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: const Text('Tolak'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    if (onTolak != null) const SizedBox(width: 10),
                    Expanded(
                      flex: onTolak != null ? 2 : 1,
                      child: ElevatedButton.icon(
                        onPressed: onAction,
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: Text(actionLabel),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ──────────────────────────────────────────────────────────────────────────────

class _InfoItem {
  final String label;
  final String value;
  final IconData icon;
  const _InfoItem(this.label, this.value, this.icon);
}

Widget _infoGrid(List<_InfoItem> items) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: items
        .map(
          (item) => SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Icon(item.icon, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  item.label,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  item.value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
}

/// Dialog konfirmasi tolak + input alasan, dipakai oleh ketiga tab
/// (Nasabah Baru, Pelunasan, Perpanjangan). Return alasan yang diketik
/// (bisa string kosong) kalau admin menekan Tolak, atau null kalau batal.
Future<String?> _promptTolakCatatan(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final ctrl = TextEditingController();
  try {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'Alasan penolakan',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              maxLines: 2,
            ),
          ],
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
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    return confirm == true ? ctrl.text.trim() : null;
  } finally {
    // FIX: controller sebelumnya tidak pernah di-dispose (memory leak)
    ctrl.dispose();
  }
}

Future<bool?> _confirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmLabel,
  required Color confirmColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

void _showSnackbar(BuildContext context, String message, Color color) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
}

class _EmptyView extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;
  const _EmptyView(this.message, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView(this.error);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('Error: $error', style: const TextStyle(color: Colors.red)),
    );
  }
}
