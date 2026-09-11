import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

/// FIX (fitur baru): sebelumnya app SELALU mulai dari halaman login setiap
/// kali dibuka, walau sesi Supabase-nya sendiri sebenarnya sudah otomatis
/// tersimpan di HP (supabase_flutter menyimpan sesi secara default). Halaman
/// ini jadi titik awal app (lihat main.dart, initialLocation: '/splash'):
/// tampil sebentar (loading) selagi ProfileNotifier mengecek apakah ada
/// sesi login tersimpan, lalu otomatis diarahkan ke dashboard yang sesuai
/// TANPA perlu login ulang — atau ke halaman login kalau memang belum/tidak
/// ada sesi tersimpan (misalnya setelah logout, atau login pertama kali).
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // FIX (bug): profileProvider WAJIB di-watch di sini, bukan cuma
    // di-`read` di dalam callback di bawah. Riverpod provider itu lazy —
    // baru benar-benar dibuat (constructor ProfileNotifier jalan, _init()
    // jalan) saat pertama kali di-watch/read. Sebelumnya provider ini
    // cuma dibaca di dalam callback yang baru jalan SETELAH
    // authInitializingProvider == false — padahal authInitializingProvider
    // itu sendiri baru di-set false DARI DALAM _init() milik
    // ProfileNotifier. Hasilnya saling tunggu (deadlock): ProfileNotifier
    // nggak pernah dibuat sama sekali, dan splash screen nyangkut loading
    // selama-lamanya di semua platform (Android maupun web).
    final profile = ref.watch(profileProvider);
    final initializing = ref.watch(authInitializingProvider);

    if (!initializing) {
      // FIX: navigasi tidak boleh dipanggil langsung di dalam build() —
      // dijadwalkan setelah frame ini selesai digambar, supaya aman.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (profile == null) {
          context.go('/login');
        } else if (profile.role == 'admin') {
          context.go('/admin/dashboard');
        } else {
          context.go('/petugas/dashboard');
        }
      });
    }

    return const Scaffold(
      backgroundColor: Color(0xFF0F2D4A),
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
