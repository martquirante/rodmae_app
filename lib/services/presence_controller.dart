import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../widgets/advanced_loading_effect.dart';
import 'firebase_service.dart'; // AppRuntime

// ═════════════════════════════════════════════════════════════════════════════
// TIME UTILS
// Converts a DateTime (UTC or local) into a human-readable "last seen" string.
// ═════════════════════════════════════════════════════════════════════════════

abstract final class TimeUtils {
  TimeUtils._();

  /// Returns a human-readable presence string based on [lastSeen] and
  /// whether the user is currently [isOnline].
  ///
  /// Rules:
  ///   online                     → "Active now"
  ///   offline < 1 min            → "Active now"
  ///   offline 1–59 min           → "Active X mins ago"
  ///   offline 1–23 h             → "Active X hours ago"
  ///   offline yesterday          → "Last seen yesterday at HH:MM AM/PM"
  ///   offline 2+ days            → "Last seen on MM/DD/YYYY"
  static String formatLastSeen(DateTime lastSeen, {bool isOnline = false}) {
    if (isOnline) return 'Active now';

    final now = DateTime.now();
    // Normalise to local time for display
    final local = lastSeen.toLocal();
    final diff = now.difference(local);

    if (diff.inSeconds < 60) return 'Active now';
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes;
      return 'Active $mins ${mins == 1 ? 'min' : 'mins'} ago';
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return 'Active $hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }

    // Was it yesterday?
    final today    = DateTime(now.year, now.month, now.day);
    final seenDate = DateTime(local.year, local.month, local.day);
    final daysDiff = today.difference(seenDate).inDays;

    if (daysDiff == 1) {
      return 'Last seen yesterday at ${_formatTime(local)}';
    }

    // 2+ days ago
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final yyyy = local.year;
    return 'Last seen on $mm/$dd/$yyyy';
  }

  /// Formats [dt] as "HH:MM AM/PM"  e.g. "9:04 PM"
  static String _formatTime(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PRESENCE MODEL
// Snapshot of one partner's online / last-seen state.
// ═════════════════════════════════════════════════════════════════════════════

class PresenceState {
  final bool isOnline;
  final DateTime? lastSeen;

  const PresenceState({required this.isOnline, this.lastSeen});

  /// Convenience: human-readable label derived from [TimeUtils].
  String get label => lastSeen != null
      ? TimeUtils.formatLastSeen(lastSeen!, isOnline: isOnline)
      : isOnline
          ? 'Active now'
          : 'Offline';

  @override
  String toString() => 'PresenceState(isOnline: $isOnline, lastSeen: $lastSeen)';
}

// ═════════════════════════════════════════════════════════════════════════════
// PRESENCE CONTROLLER
//
// • Implements WidgetsBindingObserver to capture AppLifecycleState changes.
// • On `resumed`  → writes is_online=true  + last_seen=NOW to Supabase.
// • On `paused` / `inactive` / `detached` → writes is_online=false + last_seen=NOW.
// • Exposes a stream of [PresenceState] for any partner by name.
// • Maintains a 30-second heartbeat while active to keep presence fresh.
// ═════════════════════════════════════════════════════════════════════════════

final class PresenceController with WidgetsBindingObserver {
  PresenceController._();

  static final PresenceController instance = PresenceController._();

  // ── State ──────────────────────────────────────────────────────────────────
  String? _myPartnerName;   // set via [attach]
  Timer? _heartbeatTimer;
  bool   _attached = false;

  // ── Supabase shorthand ─────────────────────────────────────────────────────
  SupabaseClient get _db => Supabase.instance.client;

  // ──────────────────────────────────────────────────────────────────────────
  // ATTACH / DETACH
  // Call [attach] once the current user's partner name is known (after login).
  // Call [detach] on sign-out or app termination.
  // ──────────────────────────────────────────────────────────────────────────

  void attach(String partnerName) {
    if (_attached && _myPartnerName == partnerName) return;
    if (_attached) {
      detach();
    }
    _myPartnerName = partnerName;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    // Immediately mark online and start heartbeat.
    _writePresence(isOnline: true);
    _startHeartbeat();
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _writePresence(isOnline: false);
    WidgetsBinding.instance.removeObserver(this);
    _myPartnerName = null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // APP LIFECYCLE OBSERVER
  // ──────────────────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _writePresence(isOnline: true);
        _startHeartbeat();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _heartbeatTimer?.cancel();
        _writePresence(isOnline: false);
      case AppLifecycleState.hidden:
        break; // desktop-only, not relevant
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // WRITE PRESENCE to Supabase `user_presence` table
  //
  // Expected schema (create once in Supabase):
  //   CREATE TABLE user_presence (
  //     couple_id  text,
  //     partner    text,
  //     is_online  boolean  DEFAULT false,
  //     last_seen  timestamptz DEFAULT now(),
  //     PRIMARY KEY (couple_id, partner)
  //   );
  //   ALTER TABLE user_presence ENABLE ROW LEVEL SECURITY;
  //   -- Add a policy allowing authenticated writes for the couple.
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _writePresence({required bool isOnline}) async {
    final partner = _myPartnerName;
    if (partner == null) return;
    if (!AppRuntime.supabaseReady) return;
    try {
      await _db.from('user_presence').upsert(
        {
          'couple_id': AppConfig.coupleId,
          'partner':   partner,
          'is_online': isOnline,
          'last_seen': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'couple_id,partner',
      );
    } catch (e) {
      debugPrint('PresenceController._writePresence error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEARTBEAT — refreshes last_seen every 30 s while foregrounded
  // ──────────────────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _writePresence(isOnline: true);
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STREAM — watch a partner's presence in real-time
  //
  // Usage:
  //   PresenceController.instance.watchPresence('Eurine')
  //       .listen((state) => print(state.label));
  // ──────────────────────────────────────────────────────────────────────────

  Stream<PresenceState> watchPresence(String partnerName) {
    final ctrl = StreamController<PresenceState>.broadcast();
    StreamSubscription? realtimeSub;
    Timer? pollTimer;

    void doFetch() async {
      final state = await _fetchPresence(partnerName);
      if (!ctrl.isClosed) ctrl.add(state);
    }

    void start() async {
      // 1. Emit immediately
      doFetch();

      // 2. Start periodic polling (every 15 seconds) to ensure freshness
      // even if Realtime is silent, RLS fails, or connection drops.
      pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => doFetch());

      if (!AppRuntime.supabaseReady) return;

      // 3. Subscribe to Supabase Realtime changes on the row
      try {
        realtimeSub = _db
            .from('user_presence')
            .stream(primaryKey: ['couple_id', 'partner'])
            .eq('couple_id', AppConfig.coupleId)
            .listen(
              (rows) {
                final row = rows.cast<Map<String, dynamic>>().firstWhere(
                  (r) => (r['partner'] as String?)?.toLowerCase() ==
                      partnerName.toLowerCase(),
                  orElse: () => {},
                );
                if (row.isNotEmpty && !ctrl.isClosed) {
                  ctrl.add(_rowToState(row));
                }
              },
              onError: (e) {
                debugPrint('watchPresence realtime stream error: $e');
              },
            );
      } catch (e) {
        debugPrint('watchPresence realtime subscription failed: $e');
      }
    }

    ctrl.onListen = start;
    ctrl.onCancel = () {
      realtimeSub?.cancel();
      pollTimer?.cancel();
    };

    return ctrl.stream;
  }

  /// Single fetch (used for immediate emit or polling fallback).
  Future<PresenceState> _fetchPresence(String partnerName) async {
    try {
      if (!AppRuntime.supabaseReady) return const PresenceState(isOnline: false);
      final rows = await _db
          .from('user_presence')
          .select()
          .eq('couple_id', AppConfig.coupleId)
          .eq('partner', partnerName)
          .limit(1);
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty) return _rowToState(list.first);
    } catch (e) {
      debugPrint('PresenceController._fetchPresence error: $e');
    }
    return const PresenceState(isOnline: false);
  }

  PresenceState _rowToState(Map<String, dynamic> row) {
    final isOnline = row['is_online'] == true;
    final rawLastSeen = row['last_seen'];
    DateTime? lastSeen;
    if (rawLastSeen != null) {
      lastSeen = DateTime.tryParse(rawLastSeen.toString())?.toLocal();
    }
    // If online but last_seen is stale by more than 6 min, treat as offline
    // (guards against crash / ungraceful exits that left is_online=true).
    if (isOnline && lastSeen != null) {
      final stale = DateTime.now().difference(lastSeen).inSeconds > 360;
      if (stale) return PresenceState(isOnline: false, lastSeen: lastSeen);
    }
    return PresenceState(isOnline: isOnline, lastSeen: lastSeen);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// WIDGET: PresenceIndicatorText
//
// A self-contained, reusable widget that:
//   • Accepts [partnerName] (e.g. "Eurine" or "Rodel").
//   • Listens to the presence stream.
//   • Shows a coloured dot + formatted "Active now" / "Last seen..." label.
//   • Stateless regarding data — all state lives in the StreamBuilder.
//
// Example usage (Chat header, App Bar, Profile card, etc.):
//   PresenceIndicatorText(partnerName: 'Eurine')
//   PresenceIndicatorText(partnerName: 'Rodel', style: myTextStyle)
// ═════════════════════════════════════════════════════════════════════════════

class PresenceIndicatorText extends StatelessWidget {
  final String partnerName;
  /// Optional override for the text style.
  final TextStyle? style;
  /// Dot size. Defaults to 7.
  final double dotSize;

  const PresenceIndicatorText({
    required this.partnerName,
    this.style,
    this.dotSize = 7.0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PresenceState>(
      stream: PresenceController.instance.watchPresence(partnerName),
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PresenceState(isOnline: false);
        final isActive = state.isOnline ||
            (state.lastSeen != null &&
                DateTime.now().difference(state.lastSeen!).inSeconds < 60);

        final dotColor = isActive
            ? const Color(0xFF4ADE80) // green-400
            : const Color(0xFF6B7280); // grey-500

        final label = state.label;

        final defaultStyle = TextStyle(
          color: isActive
              ? const Color(0xFF4ADE80)
              : Colors.white.withValues(alpha: 0.55),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        );

        final isWaiting = snapshot.connectionState == ConnectionState.waiting;
        final showLoading = isWaiting;

        return AdvancedLoadingEffect(
          isLoading: showLoading,
          placeholder: Container(
            width: 100,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Presence dot with pulse when active
              _PresenceDot(color: dotColor, size: dotSize, pulse: isActive),
              const SizedBox(width: 5),
              Text(
                '$partnerName: $label',
                style: style ?? defaultStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Internal animated dot ─────────────────────────────────────────────────────

class _PresenceDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool pulse;

  const _PresenceDot({
    required this.color,
    required this.size,
    required this.pulse,
  });

  @override
  State<_PresenceDot> createState() => _PresenceDotState();
}

class _PresenceDotState extends State<_PresenceDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.30).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PresenceDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.scale(
        scale: widget.pulse ? _scale.value : 1.0,
        child: Container(
          width:  widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: widget.pulse
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.55),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// WIDGET: PresenceAvatarBadge
//
// Wraps any circular avatar widget and overlays a coloured presence dot on
// the bottom-right corner.
//
//   • Green + pulse  → partner is ONLINE right now
//   • Grey (static)  → partner is OFFLINE
//
// Example usage (Chat header, Profile cards, etc.):
//
//   PresenceAvatarBadge(
//     partnerName: 'Eurine',
//     radius: 20,
//     child: CircleAvatar(backgroundImage: ...),
//   )
// ═════════════════════════════════════════════════════════════════════════════

class PresenceAvatarBadge extends StatelessWidget {
  /// The partner whose presence we monitor.
  final String partnerName;

  /// The circular avatar widget to decorate.
  final Widget child;

  /// Radius of the avatar (used for positioning the dot).
  final double radius;

  /// Badge dot diameter. Defaults to 12.
  final double badgeSize;

  const PresenceAvatarBadge({
    required this.partnerName,
    required this.child,
    required this.radius,
    this.badgeSize = 12,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PresenceState>(
      stream: PresenceController.instance.watchPresence(partnerName),
      builder: (context, snapshot) {
        final state   = snapshot.data ?? const PresenceState(isOnline: false);
        final online  = state.isOnline ||
            (state.lastSeen != null &&
                DateTime.now().difference(state.lastSeen!).inSeconds < 60);
        final dotColor = online
            ? const Color(0xFF4ADE80) // green-400
            : const Color(0xFF6B7280); // grey-500

        final isWaiting = snapshot.connectionState == ConnectionState.waiting;
        final showLoading = isWaiting;

        return AdvancedLoadingEffect(
          isLoading: showLoading,
          shape: BoxShape.circle,
          placeholder: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: const BoxDecoration(
              color: Colors.white12,
              shape: BoxShape.circle,
            ),
          ),
          child: SizedBox(
            width:  radius * 2,
            height: radius * 2,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                child,
                Positioned(
                  bottom: 0,
                  right:  0,
                  child: Container(
                    width:  badgeSize,
                    height: badgeSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // White ring separates the dot from the avatar
                      border: Border.all(
                        color: Colors.white,
                        width: 1.8,
                      ),
                      color: dotColor,
                      boxShadow: online
                          ? [
                              BoxShadow(
                                color: dotColor.withValues(alpha: 0.6),
                                blurRadius: 5,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: online
                        ? _PresenceDot(
                            color: dotColor,
                            size: badgeSize - 3.6,
                            pulse: true,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
