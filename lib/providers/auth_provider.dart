import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile_model.dart';
import '../repositories/auth_repository.dart';
import '../services/device_service.dart';
import '../services/fcm_service.dart';

final authRepoProvider = Provider((ref) => AuthRepository());

final authInitializingProvider = StateProvider<bool>((ref) => true);

/// Hasil login: butuh verifikasi perangkat, atau sukses langsung.
class LoginResult {
  final bool needVerification;
  final String? role;
  const LoginResult.needVerification() : needVerification = true, role = null;
  const LoginResult.success(this.role) : needVerification = false;
}

// ── Guard perangkat (dipakai UI global di main.dart) ──────────────────────
class DeviceGuardState {
  final bool kicked;
  final String? takeoverCode;
  final String? takeoverLabel;
  const DeviceGuardState({
    this.kicked = false,
    this.takeoverCode,
    this.takeoverLabel,
  });

  DeviceGuardState copyWith({
    bool? kicked,
    String? takeoverCode,
    String? takeoverLabel,
    bool clearCode = false,
  }) => DeviceGuardState(
    kicked: kicked ?? this.kicked,
    takeoverCode: clearCode ? null : (takeoverCode ?? this.takeoverCode),
    takeoverLabel: clearCode ? null : (takeoverLabel ?? this.takeoverLabel),
  );
}

final deviceGuardProvider =
    StateNotifierProvider<DeviceGuardNotifier, DeviceGuardState>(
      (ref) => DeviceGuardNotifier(),
    );

class DeviceGuardNotifier extends StateNotifier<DeviceGuardState> {
  DeviceGuardNotifier() : super(const DeviceGuardState());
  void setKicked() => state = state.copyWith(kicked: true);
  void showCode(String code, String? label) =>
      state = state.copyWith(takeoverCode: code, takeoverLabel: label);
  void clearCode() => state = state.copyWith(clearCode: true);
  void reset() => state = const DeviceGuardState();
}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileModel?>(
  (ref) => ProfileNotifier(ref, ref.read(authRepoProvider)),
);

class ProfileNotifier extends StateNotifier<ProfileModel?> {
  final Ref _ref;
  final AuthRepository _repo;
  bool _loggingOut = false;
  StreamSubscription? _guardSub;

  ProfileNotifier(this._ref, this._repo) : super(null) {
    _init();
  }

  Future<void> _init() async {
    try {
      final profile = await _repo.getCurrentProfile();
      if (profile != null) {
        final stillBound = await _repo.isThisDeviceBound();
        if (!stillBound) {
          // Perangkat ini sudah diambil alih perangkat lain → keluar.
          await _repo.logout();
          state = null;
        } else {
          state = profile;
          _registerFcmIfAdmin();
          _startDeviceGuard();
        }
      } else {
        state = null;
      }
    } catch (_) {
      state = null;
    } finally {
      _ref.read(authInitializingProvider.notifier).state = false;
    }
  }

  Future<LoginResult> login(String email, String password) async {
    _ref.read(deviceGuardProvider.notifier).reset();
    final profile = await _repo.login(email, password);
    final bind = await _repo.bindOrRequestDevice();
    if (bind == 'need_verification') {
      // Jangan set state — tunggu verifikasi di perangkat baru.
      return const LoginResult.needVerification();
    }
    state = profile;
    _registerFcmIfAdmin();
    _startDeviceGuard();
    return LoginResult.success(profile.role);
  }

  /// Dipanggil setelah kode verifikasi benar (perangkat baru).
  Future<String> verifyAndComplete(String code) async {
    final res = await _repo.verifyDeviceTakeover(code);
    switch (res) {
      case 'ok':
        _ref.read(deviceGuardProvider.notifier).reset();
        final profile = await _repo.getCurrentProfile();
        state = profile;
        _registerFcmIfAdmin();
        _startDeviceGuard();
        return profile?.role ?? 'petugas';
      case 'wrong_code':
        throw Exception('Kode verifikasi salah');
      case 'expired':
        throw Exception(
          'Kode kedaluwarsa. Minta kode baru dari perangkat lama.',
        );
      default:
        throw Exception('Permintaan tidak ditemukan. Coba login ulang.');
    }
  }

  /// Batal verifikasi (perangkat baru) → keluar.
  Future<void> cancelVerification() async {
    await _signOutLocal();
  }

  void _registerFcmIfAdmin() {
    final profile = state;
    if (profile != null && profile.role == 'admin') {
      FcmService.registerForAdmin(_repo);
    }
  }

  Future<void> _startDeviceGuard() async {
    final uid = _repo.currentUserId;
    if (uid == null) return;
    final myDeviceId = await DeviceService.getDeviceId();
    _guardSub?.cancel();
    _guardSub = _repo.watchOwnProfile(uid).listen((rows) async {
      if (rows.isEmpty) return;
      final row = rows.first;
      final boundDevice = row['device_id'] as String?;
      final takeoverReq = row['takeover_requested'] == true;
      if (boundDevice != null && boundDevice != myDeviceId) {
        // Ditendang oleh perangkat lain.
        _ref.read(deviceGuardProvider.notifier).setKicked();
        await _signOutLocal();
      } else if (takeoverReq) {
        final info = await _repo.getTakeoverCode();
        if (info != null) {
          _ref
              .read(deviceGuardProvider.notifier)
              .showCode(
                info['code'].toString(),
                info['new_device_label']?.toString(),
              );
        }
      } else {
        _ref.read(deviceGuardProvider.notifier).clearCode();
      }
    });
  }

  /// Keluar lokal saja (tanpa melepas ikatan) — dipakai saat ditendang.
  Future<void> _signOutLocal() async {
    _guardSub?.cancel();
    _guardSub = null;
    await _repo.logout();
    state = null;
  }

  /// Logout yang diminta user — lepaskan juga ikatan perangkat.
  Future<void> logout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      try {
        await _repo.releaseDevice();
      } catch (_) {}
      await _signOutLocal();
    } finally {
      _loggingOut = false;
    }
  }

  void updateAvatarLocally(String? avatarUrl) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(avatarUrl: avatarUrl);
  }
}
