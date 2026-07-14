// Run with: dart run tool/encode_keys.dart
//
// Prints byte vectors for the sensitive runtime values referenced by
// `lib/setup/backend_endpoint.dart` and `lib/setup/attribution_keys.dart`.
// Paste the printed arrays into the corresponding `const` lists.
//
// IMPORTANT: Always run this with `dart run`. Do NOT translate this to
// PowerShell — Windows' default integer arithmetic in PowerShell pipelines
// silently overflows above 2^31, producing wrong bytes and broken URLs.

// ignore_for_file: avoid_relative_lib_imports, avoid_print

import '../lib/cipher/scrambler.dart';

void _emit(String label, String value) {
  if (value.isEmpty) {
    print('$label : <empty — skipped>');
    return;
  }
  final bytes = scramble(value);
  final formatted = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');
  print('$label (${bytes.length} bytes):');
  print('  <int>[$formatted]');
  print('');
}

void main() {
  // --- Backend config endpoint ---------------------------------------
  // Split host and path so the recombined URL never appears as one
  // contiguous string in the compiled binary.
  _emit('endpoint host', 'https://feattherdash.com');
  _emit('endpoint path', '/config.php');

  // --- AppsFlyer attribution -----------------------------------------
  // Fill these in once the dev key / project number land. Re-run.
  const appsFlyerDevKey = ''; // paste the dev key here when regenerating
  const firebaseProjectNumber = ''; // paste the project number here
  _emit('appsflyer dev key', appsFlyerDevKey);
  _emit('firebase project #', firebaseProjectNumber);

  // --- GCD endpoint (AppsFlyer Get-Conversion-Data) ------------------
  _emit('gcd host', 'https://gcdsdk.appsflyer.com');
  _emit('gcd path', '/install_data/v4.0/');

  // --- HTTP/WebView User-Agent fragments -----------------------------
  // Pinning the Chrome / WebKit version fragments hides version strings
  // from a `strings`-style scan of the APK.
  _emit('chrome version', '149.0.7392.104'); // bump per project — see rules
  _emit('webkit version', '605.1.15');
}
