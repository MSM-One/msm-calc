import 'dart:async';
import 'package:flutter/material.dart';

class ResilientSupabaseStream<T> {
  final Stream<T> Function() streamFactory;
  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;

  final StreamController<T> _controller = StreamController<T>.broadcast();
  StreamSubscription<T>? _subscription;
  Duration _currentDelay;
  Timer? _retryTimer;
  bool _isDisposed = false;

  final ValueNotifier<bool> isErrorNotifier = ValueNotifier<bool>(false);

  ResilientSupabaseStream({
    required this.streamFactory,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
  }) : _currentDelay = initialDelay {
    _connect();
  }

  Stream<T> get stream => _controller.stream;

  void _connect() {
    if (_isDisposed) return;

    _subscription?.cancel();
    try {
      _subscription = streamFactory().listen(
        (data) {
          _currentDelay = initialDelay; // Reset backoff on success
          if (isErrorNotifier.value) {
            isErrorNotifier.value = false;
          }
          if (!_controller.isClosed) {
            _controller.add(data);
          }
        },
        onError: (error) {
          debugPrint("[ResilientSupabaseStream] Stream error: $error");
          if (!isErrorNotifier.value) {
            isErrorNotifier.value = true;
          }
          _handleFailure();
        },
        onDone: () {
          debugPrint("[ResilientSupabaseStream] Stream done.");
          if (!isErrorNotifier.value) {
            isErrorNotifier.value = true;
          }
          _handleFailure();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("[ResilientSupabaseStream] Connection error: $e");
      if (!isErrorNotifier.value) {
        isErrorNotifier.value = true;
      }
      _handleFailure();
    }
  }

  void _handleFailure() {
    if (_isDisposed) return;
    _subscription?.cancel();

    debugPrint(
        "[ResilientSupabaseStream] Reconnecting in ${_currentDelay.inSeconds}s...");
    _retryTimer?.cancel();
    _retryTimer = Timer(_currentDelay, () {
      _currentDelay = Duration(
          milliseconds: (_currentDelay.inMilliseconds * multiplier).toInt());
      if (_currentDelay > maxDelay) {
        _currentDelay = maxDelay;
      }
      _connect();
    });
  }

  void dispose() {
    _isDisposed = true;
    _retryTimer?.cancel();
    _subscription?.cancel();
    _controller.close();
    isErrorNotifier.dispose();
  }
}
