import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'stock_notifier.dart';

enum RealtimeTableTarget {
  transactions,
  vendors,
  unknown,
}

class RealtimeSyncEvent {
  final RealtimeTableTarget target;
  final String eventType;
  final DateTime timestamp;

  RealtimeSyncEvent({
    required this.target,
    required this.eventType,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class SupabaseRealtimeService {
  static final SupabaseRealtimeService instance =
      SupabaseRealtimeService._internal();
  factory SupabaseRealtimeService() => instance;
  SupabaseRealtimeService._internal();

  RealtimeChannel? _channel;
  Timer? _debounceTimer;
  final Duration _debounceDuration = const Duration(milliseconds: 400);

  final StreamController<RealtimeSyncEvent> _syncStreamController =
      StreamController<RealtimeSyncEvent>.broadcast();

  Stream<RealtimeSyncEvent> get syncStream => _syncStreamController.stream;

  RealtimeTableTarget _pendingTarget = RealtimeTableTarget.unknown;
  String _pendingEventType = '*';
  bool _isSubscribed = false;

  /// Initializes Supabase WebSocket listening to postgres_changes on 'transactions' and 'vendors'
  void initialize() {
    if (_isSubscribed) return;
    _subscribe();
  }

  void _subscribe() {
    try {
      final client = Supabase.instance.client;
      _channel = client.channel('public:inventory_realtime');

      _channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'transactions',
            callback: (payload) {
              debugPrint(
                  '[SupabaseRealtimeService] Event received on transactions: ${payload.eventType}');
              _onDatabaseEvent(
                  RealtimeTableTarget.transactions, payload.eventType.name);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'item_sizes',
            callback: (payload) {
              debugPrint(
                  '[SupabaseRealtimeService] Event received on item_sizes: ${payload.eventType}');
              _onDatabaseEvent(
                  RealtimeTableTarget.transactions, payload.eventType.name);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'materials',
            callback: (payload) {
              debugPrint(
                  '[SupabaseRealtimeService] Event received on materials: ${payload.eventType}');
              _onDatabaseEvent(
                  RealtimeTableTarget.transactions, payload.eventType.name);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'vendors',
            callback: (payload) {
              debugPrint(
                  '[SupabaseRealtimeService] Event received on vendors: ${payload.eventType}');
              _onDatabaseEvent(
                  RealtimeTableTarget.vendors, payload.eventType.name);
            },
          )
          .subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _isSubscribed = true;
          debugPrint(
              '[SupabaseRealtimeService] Realtime channel subscribed successfully.');
        } else if (status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.timedOut) {
          _isSubscribed = false;
          debugPrint(
              '[SupabaseRealtimeService] Realtime channel status: $status (Error: $error)');
        }
      });
    } catch (e) {
      debugPrint(
          '[SupabaseRealtimeService] Error subscribing to realtime channel: $e');
    }
  }

  void _onDatabaseEvent(RealtimeTableTarget target, String eventType) {
    if (_pendingTarget == RealtimeTableTarget.unknown ||
        _pendingTarget == target) {
      _pendingTarget = target;
    } else {
      _pendingTarget =
          RealtimeTableTarget.unknown; // Multiple tables changed in window
    }
    _pendingEventType = eventType;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      final event = RealtimeSyncEvent(
        target: _pendingTarget,
        eventType: _pendingEventType,
      );
      _pendingTarget = RealtimeTableTarget.unknown;
      _pendingEventType = '*';

      debugPrint(
          '[SupabaseRealtimeService] Debounce window passed. Emitting sync event...');
      _syncStreamController.add(event);
      notifyStockDataChanged();
    });
  }

  /// Pauses WebSocket channel when app enters background
  void pause() {
    if (!_isSubscribed && _channel == null) return;
    try {
      debugPrint('[SupabaseRealtimeService] Pausing realtime channel...');
      _channel?.unsubscribe();
      _channel = null;
      _isSubscribed = false;
    } catch (e) {
      debugPrint(
          '[SupabaseRealtimeService] Error pausing realtime channel: $e');
    }
  }

  /// Resumes WebSocket channel when app returns to foreground
  void resume() {
    if (_isSubscribed) return;
    debugPrint('[SupabaseRealtimeService] Resuming realtime channel...');
    _subscribe();
  }

  void dispose() {
    _debounceTimer?.cancel();
    pause();
    _syncStreamController.close();
  }
}
