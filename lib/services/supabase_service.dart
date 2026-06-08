import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../models/couple_settings.dart';
import '../models/finance_entry.dart';
import '../models/chat_message.dart';
import '../models/user_profile.dart';
import '../models/vault_document.dart';
import '../models/meal_plan.dart';
import '../models/surprise_note.dart';
import '../models/love_trigger_event.dart';
import '../models/couple_location.dart';
import 'auth_service.dart';
import 'firebase_service.dart';

final class SupabaseWeddingRepository {
  SupabaseWeddingRepository._();

  static final SupabaseWeddingRepository instance = SupabaseWeddingRepository._();

  SupabaseClient get _client {
    if (!AppRuntime.supabaseReady) {
      throw StateError('Supabase is not initialized.');
    }
    return Supabase.instance.client;
  }

  // --- Highly Robust Local Caching System (Local-First Offline Support) ---

  Future<List<Map<String, dynamic>>> _loadCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(key);
      if (str != null) {
        final decoded = jsonDecode(str);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveCache(String key, List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(list));
    } catch (_) {}
  }

  // --- Finances & Joint Expense Tracker ---

  Future<List<FinanceEntry>> fetchFinances() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('finances')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('date', ascending: false);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_finances', list);
        return list.map(FinanceEntry.fromMap).toList();
      }
    } catch (e) {
      print('Supabase fetchFinances error: $e');
    }
    // Fallback to local cache so the app remains fully functional offline!
    final cached = await _loadCache('cached_finances');
    return cached.map(FinanceEntry.fromMap).toList();
  }

  Stream<List<FinanceEntry>> watchFinances() {
    final controller = StreamController<List<FinanceEntry>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 3), (t) async {
        try {
          final data = await fetchFinances();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      // 1. Emit cached immediately for instant UI loading with zero lag
      final cached = await fetchFinances();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('finances')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('date', ascending: false)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_finances', list);
                if (!controller.isClosed) {
                  controller.add(list.map(FinanceEntry.fromMap).toList());
                }
              },
              onError: (err) {
                // Silently fallback to polling if realtime is not active in DB
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<void> insertFinance(FinanceEntry entry) async {
    final map = entry.toInsertMap();
    
    // Save to local cache immediately for ultra-responsive UI
    final cached = await _loadCache('cached_finances');
    final localMap = {
      'id': entry.id,
      'couple_id': AppConfig.coupleId,
      'title': '${entry.category} - ${entry.title}',
      'amount': entry.amount,
      'type': entry.type == FinanceType.income ? 'Income' : 'Expense',
      'date': Formatters.date(entry.date),
      'created_by': entry.createdBy,
    };
    cached.insert(0, localMap);
    await _saveCache('cached_finances', cached);

    // Asynchronously insert into live Supabase
    try {
      if (AppRuntime.supabaseReady) {
        await _client.from('finances').insert(map);
      }
    } catch (e) {
      print('Supabase insertFinance error: $e');
    }
  }

  Future<void> insertReceiptExpense(ReceiptExtraction receipt) async {
    final entry = FinanceEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: receipt.storeName,
      category: receipt.category,
      amount: receipt.totalAmount,
      type: FinanceType.expense,
      date: DateTime.now(),
      createdBy: PartnerIdentity.active.value.label,
    );
    await insertFinance(entry);
  }

  // --- Spouses chat thread syncing ---

  Future<List<ChatMessage>> fetchChat() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('chat_history')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: true);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_chat', list);
        return list.map(ChatMessage.fromMap).toList();
      }
    } catch (e) {
      print('Supabase fetchChat error: $e');
    }
    final cached = await _loadCache('cached_chat');
    return cached.map(ChatMessage.fromMap).toList();
  }

  Stream<List<ChatMessage>> watchChat() {
    final controller = StreamController<List<ChatMessage>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 3), (t) async {
        try {
          final data = await fetchChat();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      // 1. Emit cached immediately
      final cached = await fetchChat();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('chat_history')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: true)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_chat', list);
                if (!controller.isClosed) {
                  controller.add(list.map(ChatMessage.fromMap).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<void> sendChatMessage(String message) async {
    final localMap = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'couple_id': AppConfig.coupleId,
      'sender': PartnerIdentity.active.value.label,
      'message': message,
      'created_at': DateTime.now().toIso8601String(),
    };
    final cached = await _loadCache('cached_chat');
    cached.add(localMap);
    await _saveCache('cached_chat', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _client.from('chat_history').insert({
          'couple_id': AppConfig.coupleId,
          'sender': PartnerIdentity.active.value.label,
          'message': message,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      print('Supabase sendChatMessage error: $e');
    }
  }

  // --- Checklist Methods (Connecting Newlyweds checklist to the Supabase checklist table) ---

  Future<List<GoalItem>> fetchChecklist() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('checklist')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('id', ascending: true);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_checklist', list);
        return list.map((row) => GoalItem(
              id: '${row['id']}',
              title: '${row['title']}',
              category: '${row['category'] ?? 'Newlyweds'}',
              completed: row['is_completed'] == true,
            )).toList();
      }
    } catch (e) {
      print('Supabase fetchChecklist error: $e');
    }
    final cached = await _loadCache('cached_checklist');
    return cached.map((row) => GoalItem(
          id: '${row['id']}',
          title: '${row['title']}',
          category: '${row['category'] ?? 'Newlyweds'}',
          completed: row['is_completed'] == true,
        )).toList();
  }

  Stream<List<GoalItem>> watchChecklist() {
    final controller = StreamController<List<GoalItem>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 3), (t) async {
        try {
          final data = await fetchChecklist();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      // 1. Emit cached immediately
      final cached = await fetchChecklist();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('checklist')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('id', ascending: true)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_checklist', list);
                if (!controller.isClosed) {
                  controller.add(list.map((row) => GoalItem(
                        id: '${row['id']}',
                        title: '${row['title']}',
                        category: '${row['category'] ?? 'Newlyweds'}',
                        completed: row['is_completed'] == true,
                      )).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<void> insertChecklistItem(String title, String category) async {
    final localId = DateTime.now().microsecondsSinceEpoch.toString();
    final localMap = {
      'id': localId,
      'couple_id': AppConfig.coupleId,
      'title': title,
      'category': category,
      'is_completed': false,
    };
    final cached = await _loadCache('cached_checklist');
    cached.add(localMap);
    await _saveCache('cached_checklist', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _client.from('checklist').insert({
          'couple_id': AppConfig.coupleId,
          'title': title,
          'category': category,
          'is_completed': false,
        });
      }
    } catch (e) {
      print('Supabase insertChecklistItem error: $e');
    }
  }

  Future<void> toggleChecklistItem(String id, bool completed) async {
    final cached = await _loadCache('cached_checklist');
    for (final item in cached) {
      if ('${item['id']}' == id) {
        item['is_completed'] = completed;
        break;
      }
    }
    await _saveCache('cached_checklist', cached);

    try {
      if (AppRuntime.supabaseReady) {
        final intId = int.tryParse(id);
        if (intId != null) {
          await _client.from('checklist').update({
            'is_completed': completed,
          }).eq('id', intId);
        }
      }
    } catch (e) {
      print('Supabase toggleChecklistItem error: $e');
    }
  }

  // --- Secret Vault Storage Methods ---

  Future<List<VaultDocument>> fetchVaultDocuments() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('vault_documents')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('uploaded_at', ascending: false);
        final tableDocs = List<Map<String, dynamic>>.from(rows as List)
            .map(VaultDocument.fromMap)
            .toList();
        if (tableDocs.isNotEmpty) {
          return tableDocs;
        }

        final files = await client.storage
            .from(AppConfig.vaultBucket)
            .list(path: AppConfig.coupleId);
        final docs = <VaultDocument>[];
        for (final file in files) {
          final path = '${AppConfig.coupleId}/${file.name}';
          final signedUrl = await client.storage
              .from(AppConfig.vaultBucket)
              .createSignedUrl(path, 60 * 60);
          final size = Formatters.asDouble(file.metadata?['size']);
          docs.add(
            VaultDocument(
              name: file.name,
              sizeLabel: size > 0
                  ? '${(size / (1024 * 1024)).toStringAsFixed(2)} MB'
                  : 'Protected',
              uploadedAt: Formatters.asDate(file.createdAt),
              status: 'storage',
              signedUrl: signedUrl,
            ),
          );
        }
        return docs;
      }
    } catch (e) {
      print('Supabase fetchVaultDocuments error: $e');
    }
    return <VaultDocument>[];
  }

  // --- Surprise Notes System ---

  Future<List<SurpriseNote>> fetchNotes() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('surprise_notes')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_notes', list);
        return list.map(SurpriseNote.fromMap).toList();
      }
    } catch (e) {
      print('Supabase fetchNotes error: $e');
    }
    final cached = await _loadCache('cached_notes');
    return cached.map(SurpriseNote.fromMap).toList();
  }

  Stream<List<SurpriseNote>> watchNotes() {
    final controller = StreamController<List<SurpriseNote>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 3), (t) async {
        try {
          final data = await fetchNotes();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      final cached = await fetchNotes();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('surprise_notes')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: false)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_notes', list);
                if (!controller.isClosed) {
                  controller.add(list.map(SurpriseNote.fromMap).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<void> insertSurpriseNote(String content) async {
    final localMap = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'couple_id': AppConfig.coupleId,
      'sender': PartnerIdentity.active.value.label,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    };
    final cached = await _loadCache('cached_notes');
    cached.insert(0, localMap);
    await _saveCache('cached_notes', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _client.from('surprise_notes').insert({
          'couple_id': AppConfig.coupleId,
          'sender': PartnerIdentity.active.value.label,
          'content': content,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      print('Supabase insertSurpriseNote error: $e');
    }
  }

  // --- Love Triggers System ---

  Future<List<LoveTriggerEvent>> fetchLoveTriggers() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('love_triggers')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_triggers', list);
        return list.map(LoveTriggerEvent.fromMap).toList();
      }
    } catch (e) {
      print('Supabase fetchLoveTriggers error: $e');
    }
    final cached = await _loadCache('cached_triggers');
    return cached.map(LoveTriggerEvent.fromMap).toList();
  }

  Stream<List<LoveTriggerEvent>> watchLoveTriggers() {
    final controller = StreamController<List<LoveTriggerEvent>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 3), (t) async {
        try {
          final data = await fetchLoveTriggers();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      final cached = await fetchLoveTriggers();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('love_triggers')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: false)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_triggers', list);
                if (!controller.isClosed) {
                  controller.add(list.map(LoveTriggerEvent.fromMap).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<void> insertLoveTrigger(String triggerType) async {
    final localMap = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'couple_id': AppConfig.coupleId,
      'sender': PartnerIdentity.active.value.label,
      'trigger_type': triggerType,
      'created_at': DateTime.now().toIso8601String(),
    };
    final cached = await _loadCache('cached_triggers');
    cached.insert(0, localMap);
    await _saveCache('cached_triggers', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _client.from('love_triggers').insert({
          'couple_id': AppConfig.coupleId,
          'sender': PartnerIdentity.active.value.label,
          'trigger_type': triggerType,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      print('Supabase insertLoveTrigger error: $e');
    }
  }

  // ─── User Profiles (PFP + Display Name + Bio) ─────────────────────────────

  Future<UserProfile?> fetchUserProfile(String partner) async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _client
            .from('user_profiles')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .eq('partner', partner)
            .limit(1);
        final list = List<Map<String, dynamic>>.from(rows as List);
        if (list.isNotEmpty) {
          final profile = UserProfile.fromMap(list.first);
          // Cache locally
          final prefs = await SharedPreferences.getInstance();
          if (profile.avatarUrl != null) {
            await prefs.setString('avatar_url_$partner', profile.avatarUrl!);
          }
          return profile;
        }
      }
    } catch (e) {
      print('fetchUserProfile error: $e');
    }
    // Fallback to local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString('avatar_url_$partner');
      if (cachedUrl != null) {
        return UserProfile(
          id: '',
          coupleId: AppConfig.coupleId,
          partner: partner,
          avatarUrl: cachedUrl,
          updatedAt: DateTime.now(),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> upsertUserProfile({
    required String partner,
    String? displayName,
    String? bio,
    String? avatarUrl,
  }) async {
    if (!AppRuntime.supabaseReady) return;

    try {
      final existing = await _client
          .from('user_profiles')
          .select('id')
          .eq('couple_id', AppConfig.coupleId)
          .eq('partner', partner)
          .maybeSingle();

      final data = {
        'couple_id': AppConfig.coupleId,
        'partner': partner,
        if (displayName != null) 'display_name': displayName,
        if (bio != null) 'bio': bio,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existing != null) {
        await _client
            .from('user_profiles')
            .update(data)
            .eq('id', existing['id']);
      } else {
        await _client
            .from('user_profiles')
            .insert(data);
      }
    } catch (e) {
      print('upsertUserProfile error: $e');
      rethrow;
    }
  }

  /// Upload avatar bytes to Supabase Storage and return the public URL.
  Future<String?> uploadAvatar(Uint8List bytes, String partner) async {
    if (!AppRuntime.supabaseReady) return null;
    try {
      final filename = '${partner.toLowerCase().replaceAll(' ', '_')}.jpg';
      final path = filename;
      await _client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      final url = _client.storage.from('avatars').getPublicUrl(path);
      return url;
    } catch (e) {
      print('uploadAvatar error: $e');
      rethrow;
    }
  }

  // ─── Couple Settings ────────────────────────────────────────────────────────

  Future<CoupleSettings> fetchCoupleSettings() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _client
            .from('couple_settings')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .limit(1);
        final list = List<Map<String, dynamic>>.from(rows as List);
        if (list.isNotEmpty) {
          return CoupleSettings.fromMap(list.first);
        }
      }
    } catch (e) {
      print('fetchCoupleSettings error: $e');
    }
    return CoupleSettings.defaults();
  }

  Future<void> upsertCoupleSettings(CoupleSettings settings) async {
    if (!AppRuntime.supabaseReady) return;
    try {
      await _client.from('couple_settings').upsert(
        {...settings.toMap(), 'updated_at': DateTime.now().toIso8601String()},
        onConflict: 'couple_id',
      );
    } catch (e) {
      print('upsertCoupleSettings error: $e');
    }
  }

  // ─── Couple Locations ──────────────────────────────────────────────────────

  Future<List<CoupleLocation>> fetchLocations() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _client
            .from('couple_locations')
            .select()
            .eq('couple_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_locations', list);
        return list.map(CoupleLocation.fromMap).toList();
      }
    } catch (e) {
      print('fetchLocations error: $e');
    }
    final cached = await _loadCache('cached_locations');
    return cached.map(CoupleLocation.fromMap).toList();
  }

  Future<void> upsertLocation(CoupleLocation location) async {
    try {
      if (AppRuntime.supabaseReady) {
        final payload = {
          ...location.toMap(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        // Resolve conflict on the composite unique constraint (couple_id, partner, location_type)
        await _client.from('couple_locations').upsert(
          payload,
          onConflict: 'couple_id,partner,location_type',
        );
      }
      // Update local cache
      final currentCache = await _loadCache('cached_locations');
      final updatedList = currentCache.where((m) =>
        !(m['partner'] == location.partner && m['location_type'] == location.locationType)
      ).toList();
      updatedList.add({
        ...location.toMap(),
        'id': location.id,
        'updated_at': DateTime.now().toIso8601String(),
      });
      await _saveCache('cached_locations', updatedList);
    } catch (e) {
      print('upsertLocation error: $e');
      rethrow; // propagate so callers can show error UI
    }
  }

  Stream<List<CoupleLocation>> watchLocations() {
    final controller = StreamController<List<CoupleLocation>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 4), (t) async {
        try {
          final data = await fetchLocations();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      // Emit cached immediately
      final cached = await fetchLocations();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('couple_locations')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_locations', list);
                if (!controller.isClosed) {
                  controller.add(list.map(CoupleLocation.fromMap).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }
}

