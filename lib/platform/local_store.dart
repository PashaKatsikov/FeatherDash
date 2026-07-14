import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dto/runtime_mode.dart';

// Persistence helper for the gray flow. Splits values across two
// backends:
//   * SharedPreferences for flags, timestamps and the runtime mode.
//   * flutter_secure_storage for URLs the partner returned and the
//     push-delivered one-shot URL — both contain PII-grade values we
//     keep out of plain prefs.
class LocalStore {
  static const _kRuntimeMode = 'fd_runtime_mode';
  static const _kPartnerExpiry = 'fd_partner_expiry';
  static const _kPushSkipDeadline = 'fd_push_skip_deadline';
  static const _kPushGranted = 'fd_push_granted';
  static const _kPushOsRefused = 'fd_push_os_refused';

  static const _secPartnerUrl = 'fd_partner_url_v2';
  static const _secInboundPush = 'fd_inbound_push_v2';

  late SharedPreferences _prefs;
  final FlutterSecureStorage _vault = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> warmUp() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ----- runtime mode ----------------------------------------------

  RuntimeMode currentMode() =>
      RuntimeMode.parse(_prefs.getString(_kRuntimeMode));

  Future<void> commitMode(RuntimeMode mode) =>
      _prefs.setString(_kRuntimeMode, mode.persisted);

  // ----- partner URL (secure) --------------------------------------

  Future<String?> recalledPartnerUrl() => _vault.read(key: _secPartnerUrl);

  Future<void> rememberPartnerUrl(String url) =>
      _vault.write(key: _secPartnerUrl, value: url);

  int? recalledPartnerExpiry() => _prefs.getInt(_kPartnerExpiry);

  Future<void> rememberPartnerExpiry(int unixSeconds) =>
      _prefs.setInt(_kPartnerExpiry, unixSeconds);

  bool partnerUrlExpired() {
    final exp = recalledPartnerExpiry();
    if (exp == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= exp;
  }

  // ----- push permission state -------------------------------------

  bool isPushGranted() => _prefs.getBool(_kPushGranted) ?? false;

  Future<void> recordPushGranted(bool granted) =>
      _prefs.setBool(_kPushGranted, granted);

  bool isPushOsRefused() => _prefs.getBool(_kPushOsRefused) ?? false;

  Future<void> markPushOsRefused() =>
      _prefs.setBool(_kPushOsRefused, true);

  int? pushSkipDeadline() => _prefs.getInt(_kPushSkipDeadline);

  Future<void> recordPushSkip(int unixSeconds) =>
      _prefs.setInt(_kPushSkipDeadline, unixSeconds);

  // Combines the grant, OS-deny and skip flags into a single decision
  // about whether the promo screen should be shown again.
  //
  // The OS-refused flag matters because Android will silently no-op a
  // permission request after the user has denied it once. Without that
  // flag we'd re-show the promo every 3 days and the Accept button
  // would do nothing.
  bool shouldShowPushPromo() {
    if (isPushGranted()) return false;
    if (isPushOsRefused()) return false;
    final deadline = pushSkipDeadline();
    if (deadline == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= deadline;
  }

  // ----- inbound (cold-start) push URL -----------------------------

  Future<String?> drainInboundPush() async {
    final url = await _vault.read(key: _secInboundPush);
    if (url != null) {
      await _vault.delete(key: _secInboundPush);
    }
    return url;
  }

  Future<void> stashInboundPush(String? url) async {
    if (url == null || url.isEmpty) {
      await _vault.delete(key: _secInboundPush);
    } else {
      await _vault.write(key: _secInboundPush, value: url);
    }
  }
}
