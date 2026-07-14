import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../dto/config_payload.dart';
import '../platform/local_store.dart';
import '../setup/env.dart';
import 'browser_http.dart';

// Posts the attribution body to the config endpoint and persists
// whatever decision the server returns. The boot pipeline relies on
// the saved URL as a fallback when a later request fails, so writing
// to disk on success is a hard requirement, not an optimisation.
class BackendClient {
  final LocalStore _store;

  BackendClient(this._store);

  Future<ConfigPayload> deliver(Map<String, dynamic> body) async {
    final endpoint = Env.backendUrl;
    if (endpoint.isEmpty) {
      return ConfigPayload.failed('endpoint-missing');
    }

    try {
      final response = await browserHttp
          .post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: Env.backendTimeout));

      if (response.statusCode != 200) {
        return ConfigPayload.failed('http-${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ConfigPayload.failed('bad-shape');
      }

      final payload = ConfigPayload.fromJson(decoded);
      if (payload.usable) {
        await _store.rememberPartnerUrl(payload.url!);
        if (payload.expires != null) {
          await _store.rememberPartnerExpiry(payload.expires!);
        }
      }
      return payload;
    } catch (e) {
      if (kDebugMode) debugPrint('[Backend] deliver failed: $e');
      return ConfigPayload.failed(e.toString());
    }
  }

  Future<String?> cachedUrl() => _store.recalledPartnerUrl();
}
