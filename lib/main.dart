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
import 'providers/auth_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/device_verify_screen.dart';
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

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
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

final rootNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(
      path: '/device-verify',
      builder: (_, __) => const DeviceVerifyScreen(),
    ),

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
    GoRoute(path: '/admin/approval', builder: (_, __) => const AdminApproval()),
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
    // Reaksi global terhadap event perangkat (ditendang / minta kode).
    ref.listen<DeviceGuardState>(deviceGuardProvider, (prev, next) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx == null) return;

      if (next.kicked && !(prev?.kicked ?? false)) {
        router.go('/login');
        showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            title: const Text('Sesi Berakhir'),
            content: const Text(
              'Anda telah keluar karena akun ini login di perangkat lain.',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(rootNavigatorKey.currentContext!),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else if (next.takeoverCode != null &&
          next.takeoverCode != prev?.takeoverCode) {
        showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            title: const Text('Permintaan Login Perangkat Baru'),
            content: Text(
              'Perangkat baru (${next.takeoverLabel ?? 'tidak diketahui'}) '
              'ingin masuk ke akun ini.\n\n'
              'Berikan kode verifikasi ini ke perangkat tersebut:\n',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(rootNavigatorKey.currentContext!),
                child: const Text('Tutup'),
              ),
            ],
          ),
        );
        // Tampilkan kode besar lewat dialog kedua supaya jelas terbaca.
        showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            title: const Text('Kode Verifikasi'),
            content: Text(
              next.takeoverCode!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(rootNavigatorKey.currentContext!),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });

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
