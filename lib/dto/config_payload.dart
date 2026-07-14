// Parsed shape of the JSON response returned by the backend config
// endpoint. The wire format is intentionally small:
//
//   { "ok": true,  "url": "https://...", "expires": 1700000000 }
//   { "ok": false, "message": "organic" }
//
// `expires` is a unix-second deadline — we don't fail on missing or
// past values, we just trigger an early re-fetch on the next launch.
class ConfigPayload {
  final bool ok;
  final String? url;
  final String? message;
  final int? expires;

  const ConfigPayload({
    required this.ok,
    this.url,
    this.message,
    this.expires,
  });

  factory ConfigPayload.fromJson(Map<String, dynamic> json) {
    return ConfigPayload(
      ok: json['ok'] is bool ? json['ok'] as bool : false,
      url: (json['url'] as String?)?.trim().isEmpty == true
          ? null
          : json['url'] as String?,
      message: json['message'] as String?,
      expires: json['expires'] is int ? json['expires'] as int : null,
    );
  }

  factory ConfigPayload.failed(String reason) =>
      ConfigPayload(ok: false, message: reason);

  bool get usable => ok && url != null && url!.isNotEmpty;
}
