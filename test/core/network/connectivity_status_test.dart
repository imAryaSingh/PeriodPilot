import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_substitute/core/network/connectivity_status.dart';

void main() {
  group('isOfflineFromConnectivity', () {
    test('treats an empty result as offline', () {
      expect(isOfflineFromConnectivity(const []), isTrue);
    });

    test('treats no network interface as offline', () {
      expect(
        isOfflineFromConnectivity(const [ConnectivityResult.none]),
        isTrue,
      );
    });

    test('treats wifi and mobile data as connected', () {
      expect(
        isOfflineFromConnectivity(const [
          ConnectivityResult.wifi,
          ConnectivityResult.mobile,
        ]),
        isFalse,
      );
    });

    test('does not mark a mixed transport result offline', () {
      expect(
        isOfflineFromConnectivity(const [
          ConnectivityResult.none,
          ConnectivityResult.ethernet,
        ]),
        isFalse,
      );
    });
  });
}
