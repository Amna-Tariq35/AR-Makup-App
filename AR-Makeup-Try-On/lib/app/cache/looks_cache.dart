// looks_cache.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LooksCache {
  LooksCache._();
  static final LooksCache instance = LooksCache._();

  // ── State ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _looks = [];
  bool _loaded = false;
  bool _loading = false;
  Completer<void>? _prefetchCompleter;

  // Expose read-only view
  List<Map<String, dynamic>> get looks => List.unmodifiable(_looks);
  bool get isLoaded => _loaded;
  bool get isLoading => _loading;

  // ── Listeners ──────────────────────────────────────────────────────────────
  final List<VoidCallback> _listeners = [];
  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);
  void _notify() {
    for (final cb in _listeners) {
      cb();
    }
  }

  // ── Prefetch ───────────────────────────────────────────────────────────────
  Future<void> prefetch(String userId, {bool force = false}) async {
    if (_loaded && !force) return;

    // Agar already load ho raha hai — naya call mat karo, existing ka wait karo
    if (_loading && _prefetchCompleter != null) {
      return _prefetchCompleter!.future;
    }

    _loading = true;
    _prefetchCompleter = Completer<void>();

    try {
      final response = await Supabase.instance.client
          .from('saved_looks')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      _looks = List<Map<String, dynamic>>.from(response);
      _loaded = true;
      _notify();
      _prefetchCompleter!.complete();
    } catch (e) {
      debugPrint('❌ LooksCache prefetch error: $e');
      _prefetchCompleter!.completeError(e);
    } finally {
      _loading = false;
      _prefetchCompleter = null;
    }
  }

  // ── Optimistic insert ──────────────────────────────────────────────────────
  void optimisticAdd(Map<String, dynamic> look) {
    _looks.insert(0, look);
    _notify();
  }

  // ── Update a look in-place ─────────────────────────────────────────────────
  void updateLook(String lookId, Map<String, dynamic> patch) {
    final idx = _looks.indexWhere((l) => l['id'] == lookId);
    if (idx != -1) {
      _looks[idx] = {..._looks[idx], ...patch};
      _notify();
    }
  }

  // ── Update favourite flag ──────────────────────────────────────────────────
  void setFavourite(String lookId, bool value) {
    updateLook(lookId, {'is_favourite': value});
  }

  // ── Remove ─────────────────────────────────────────────────────────────────
  void remove(String lookId) {
    _looks.removeWhere((l) => l['id'] == lookId);
    _notify();
  }

  // ── Hard refresh ───────────────────────────────────────────────────────────
  Future<void> refresh(String userId) {
    _loaded = false; // force block karo chahe _loading true ho
    return prefetch(userId, force: true);
  }

  // ── Clear on logout ────────────────────────────────────────────────────────
  void clear() {
    _looks = [];
    _loaded = false;
    _loading = false;
    _prefetchCompleter = null;
    _notify();
  }
}