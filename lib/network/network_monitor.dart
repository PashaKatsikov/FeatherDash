import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

// Thin wrapper around connectivity_plus that pairs link-layer
// availability with a DNS probe.
//
// Two subtleties that bit earlier gray-flow builds and are enforced
// here per the template pitfalls (`.cursor/rules/gray_part_pitfalls.md`
// §3):
//   * VPN counts as connectivity. Without whitelisting `vpn`,
//     switching a Wireguard tunnel on flashed the No-Internet
//     screen for users who were actually online.
//   * DNS probe timeout is 7 s, not 3 s. Real "no route" cases
//     throw SocketException instantly, so the higher ceiling only
//     penalises the pathological VPN-tunnel case (which we then
//     correctly classify as online), not real outages.
class NetworkMonitor {
  final Connectivity _connectivity;

  // Any of these means the OS has SOME active network interface. VPN,
  // Bluetooth-tether and "other" are all real routes for a shell app.
  static const Set<ConnectivityResult> _activeInterfaces = {
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
    ConnectivityResult.bluetooth,
    ConnectivityResult.other,
  };

  // Multiple probe hosts so a single blocked domain doesn't produce a
  // false negative. Loops until one succeeds.
  static const List<String> _probeHosts = <String>[
    'cloudflare.com',
    'apple.com',
    'firebase.google.com',
  ];

  static const Duration _dnsTimeout = Duration(seconds: 7);

  NetworkMonitor({Connectivity? plugin})
      : _connectivity = plugin ?? Connectivity();

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    final linkUp = results.any(_activeInterfaces.contains);
    if (!linkUp) return false;

    for (final host in _probeHosts) {
      if (await _probe(host)) return true;
    }
    return false;
  }

  Stream<List<ConnectivityResult>> changes() =>
      _connectivity.onConnectivityChanged;

  Future<bool> _probe(String host) async {
    try {
      final lookup =
          await InternetAddress.lookup(host).timeout(_dnsTimeout);
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
