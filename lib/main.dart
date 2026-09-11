import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'supabase_config.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/petugas/petugas_dashboard.dart';
import 'screens/petugas/petugas_nasabah_list.dart';
import 'screens/petugas/petugas_tambah_nasabah.dart';
import 'screens/petugas/petugas_antreian.dart';
import 'screens/petugas/petugas_jatuh_tempo.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/admin/admin_nasabah_list.dart';
import 'screens/admin/admin_nasabah_lunas.dart';
import 'screens/admin/admin_jatuh_tempo.dart';
import 'screens/admin/admin_approval.dart';
import 'screens/admin/admin_nasabah_petugas.dart';
import 'screens/admin/admin_kelola_petugas.dart';

// FIX (fitur baru): handler ini WAJIB berupa top-level function (bukan
// method di dalam class) dan ditandai @pragma('vm:entry-point') — dipanggil
// Android di proses/isolate terpisah saat ada notifikasi masuk sementara
// aplikasi sedang di-background/tertutup total. Notifikasi "notification"
// payload dari server sebenarnya sudah otomatis ditampilkan Android sendiri
// tanpa handler ini, tapi tetap wajib didaftarkan supaya plugin
// firebase_messaging tidak melempar warning saat init.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  // FIX (fitur baru): setup Firebase untuk push notification. Dibungkus
  // try/catch supaya aplikasi TETAP BISA JALAN (login, dll) walau
  // google-services.json belum terpasang atau HP tidak punya Google Play
  // Services — notifikasi jadi fitur opsional, bukan syarat aplikasi bisa
  // dipakai sama sekali.
  //
  // FIX (bug baru): dilewati SAMA SEKALI di web (kIsWeb) — Firebase di
  // project ini HANYA dikonfigurasi untuk Android (google-services.json +
  // plugin Gradle), tidak ada konfigurasi Firebase untuk web. Kalau
  // dipanggil tanpa konfigurasi web, Firebase.initializeApp() bisa
  // menggantung TANPA batas waktu (bukan langsung melempar error), jadi
  // try/catch di bawah tidak menolong — main() tidak pernah sampai ke
  // runApp(), dan `flutter run -d chrome` jadi loading terus selamanya.
  // Push notification memang didesain khusus untuk HP Android (APK), jadi
  // melewati Firebase di web tidak menghilangkan fitur apa pun di sana.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    } catch (_) {}
  }
  runApp(const ProviderScope(child: MyApp()));
}

final router = GoRouter(
  // FIX (fitur baru): dulu '/login' — sekarang mulai dari SplashScreen
  // supaya sesi yang sudah tersimpan otomatis lanjut ke dashboard tanpa
  // perlu login ulang setiap kali app dibuka (lihat splash_screen.dart).
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

    // ── Petugas
    GoRoute(
      path: '/petugas/dashboard',
      builder: (_, __) => const PetugasDashboard(),
    ),
    GoRoute(
      path: '/petugas/nasabah',
      builder: (_, __) => const PetugasNasabahList(),
    ),
    GoRoute(
      path: '/petugas/tambah',
      builder: (_, __) => const PetugasTambahNasabah(),
    ),
    GoRoute(
      path: '/petugas/antreian',
      builder: (_, __) => const PetugasAntreian(),
    ),
    // FIX: sebelumnya route ini didaftarkan DUA KALI
    GoRoute(
      path: '/petugas/jatuh-tempo',
      builder: (_, __) => const PetugasJatuhTempo(),
    ),

    // ── Admin
    GoRoute(
      path: '/admin/dashboard',
      builder: (_, __) => const AdminDashboard(),
    ),
    GoRoute(
      path: '/admin/nasabah',
      builder: (_, __) => const AdminNasabahList(),
    ),
    GoRoute(
      path: '/admin/nasabah-lunas',
      builder: (_, __) => const AdminNasabahLunas(),
    ),
    GoRoute(
      path: '/admin/jatuh-tempo',
      builder: (_, __) => const AdminJatuhTempo(),
    ),
    GoRoute(
      path: '/admin/approval',
      builder: (_, __) => const AdminApproval(),
    ),
    GoRoute(
      path: '/admin/nasabah-petugas/:petugasId',
      builder: (_, state) =>
          AdminNasabahPetugas(petugasId: state.pathParameters['petugasId']!),
    ),
    GoRoute(
      path: '/admin/petugas',
      builder: (_, __) => const AdminKelolaPetugas(),
    ),
  ],
);

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'PT TIODORAS L.',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4F72)),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
