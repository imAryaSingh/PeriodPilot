import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Reports whether the device has an active network interface.
/// This is a useful offline hint, but it cannot guarantee Internet access.
class ConnectivityStatus extends ChangeNotifier {
  ConnectivityStatus({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      _update,
      onError: (_) => _setOffline(),
    );
    _refresh();
  }

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOffline = true;

  bool get isOffline => _isOffline;

  Future<void> _refresh() async {
    try {
      _update(await _connectivity.checkConnectivity());
    } on Object {
      _setOffline();
    }
  }

  void _update(List<ConnectivityResult> results) {
    final offline = isOfflineFromConnectivity(results);
    if (offline == _isOffline) return;
    _isOffline = offline;
    notifyListeners();
  }

  void _setOffline() {
    if (_isOffline) return;
    _isOffline = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// A transport-level hint only; internet reachability still depends on the
/// Firestore request succeeding.
bool isOfflineFromConnectivity(List<ConnectivityResult> results) =>
    results.isEmpty || results.every((r) => r == ConnectivityResult.none);
