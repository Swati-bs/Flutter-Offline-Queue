import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Simple connectivity monitoring service
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();

  Stream<bool> get connectivityStream => _controller.stream;

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  StreamSubscription<ConnectivityResult>? _subscription;

  ConnectivityService() {
    _init();
  }

  Future<void> _init() async {
    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _isOnline = _hasConnectivity(result);
    _controller.add(_isOnline);

    // Listen to changes
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = _hasConnectivity(result);

      if (wasOnline != _isOnline) {
        // ignore: avoid_print
        print('[ConnectivityService] ${_isOnline ? "🟢 ONLINE" : "🔴 OFFLINE"}');
        _controller.add(_isOnline);
      }
    });
  }

  bool _hasConnectivity(ConnectivityResult result) {
    return result != ConnectivityResult.none;
  }

  Future<bool> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    return _hasConnectivity(result);
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}


