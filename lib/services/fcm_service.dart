import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../repositories/auth_repository.dart';

/// FIX (fitur baru): push notification ke HP admin saat petugas mengajukan
/// pelunasan/perpanjangan. Dipanggil dari ProfileNotifier (lihat
/// auth_provider.dart) setiap kali profil yang login/aktif adalah admin —
/// baik lewat login manual maupun sesi yang masih tersimpan dari
/// sebelumnya (buka app lagi tanpa logout).
///
/// Kenapa harus ada dua lapis (FCM + flutter_local_notifications):
/// Firebase Cloud Messaging sendiri HANYA otomatis menampilkan notifikasi
/// di status bar saat aplikasi di-background/tertutup. Saat aplikasi
/// sedang dibuka (foreground), notifikasi "notification" payload TIDAK
/// pernah muncul otomatis — harus ditangkap manual lewat
/// FirebaseMessaging.onMessage lalu ditampilkan sendiri pakai
/// flutter_local_notifications, supaya admin tetap lihat notifikasinya
/// walau pas kejadian dia sedang buka aplikasinya.
class FcmService {
  static final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();
  static bool _localNotifReady = false;
  static bool _listenersAttached = false;

  static const _channelId = 'pengajuan_channel';
  static const _channelName = 'Pengajuan Petugas';
  static const _channelDesc =
      'Notifikasi pengajuan pelunasan/perpanjangan dari petugas';

  static Future<void> registerForAdmin(AuthRepository authRepo) async {
    try {
      if (!_localNotifReady) {
        await _setupLocalNotifications();
        _localNotifReady = true;
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null) {
        await authRepo.saveFcmToken(token);
      }

      if (!_listenersAttached) {
        _listenersAttached = true;
        messaging.onTokenRefresh.listen((newToken) {
          authRepo.saveFcmToken(newToken);
        });
        FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      }
    } catch (e) {
      // FIX: setup FCM gagal (mis. google-services.json belum terpasang,
      // atau HP tidak punya Google Play Services) TIDAK BOLEH membuat
      // login admin ikut gagal — fitur notifikasi opsional, login tetap
      // yang utama.
    }
  }

  static Future<void> _setupLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotif.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _localNotif
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  static void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotif.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
