import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// CONNECTIVITY SERVICE
//
// Background network supervisor that:
//   • Listens to ConnectivityResult changes via connectivity_plus.
//   • Exposes a [ValueNotifier<bool>] that any widget can watch reactively.
//   • Triggers a silent background sync from Supabase when connectivity
//     is restored after a period of being offline.
//
// Usage:
//   // Bootstrap (call once in AppBootstrapper.initialize):
//   await ConnectivityService.instance.initialize();
//
//   // Watch in a widget:
//   ValueListenableBuilder<bool>(
//     valueListenable: ConnectivityService.isOnline,
//     builder: (_, online, __) => online ? OnlineWidget() : OfflineWidget(),
//   )
// ═════════════════════════════════════════════════════════════════════════════

final class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  // ── Public reactive notifier ───────────────────────────────────────────────

  /// `true`  → at least one active network interface (Wi-Fi or mobile data).
  /// `false` → no connection detected.
  static final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  // ── Internal ───────────────────────────────────────────────────────────────

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = false;

  // ──────────────────────────────────────────────────────────────────────────
  // INITIALIZE
  // Call once during app startup. Performs an immediate check then subscribes
  // to the stream for ongoing updates.
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    // 1. Perform an immediate connectivity check.
    final current = await Connectivity().checkConnectivity();
    _updateState(current);

    // 2. Subscribe to ongoing changes.
    _sub = Connectivity().onConnectivityChanged.listen(_updateState);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DISPOSE
  // Cancel the stream subscription. Call during app shutdown.
  // ──────────────────────────────────────────────────────────────────────────

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // INTERNAL UPDATE
  // ──────────────────────────────────────────────────────────────────────────

  void _updateState(List<ConnectivityResult> results) {
    // Consider online if ANY result is not `none`.
    final nowOnline = results.any((r) => r != ConnectivityResult.none);

    if (isOnline.value == nowOnline) return; // no change

    isOnline.value = nowOnline;

    if (nowOnline && _wasOffline) {
      // We just recovered from an offline state — silently re-sync.
      _silentBackgroundSync();
    }

    _wasOffline = !nowOnline;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SILENT BACKGROUND SYNC
  // Runs best-effort data re-fetch when connectivity is restored.
  // Does NOT throw — any error is swallowed.
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _silentBackgroundSync() async {
    debugPrint('[ConnectivityService] Network restored — triggering background sync...');
    try {
      await Future.wait([
        SupabaseWeddingRepository.instance.fetchNotes(),
        SupabaseWeddingRepository.instance.fetchLoveTriggers(),
        SupabaseWeddingRepository.instance.fetchChat(),
        SupabaseWeddingRepository.instance.fetchFinances(),
      ]);
      debugPrint('[ConnectivityService] Background sync complete.');
    } catch (e) {
      debugPrint('[ConnectivityService] Background sync error (non-fatal): $e');
    }
  }
}
