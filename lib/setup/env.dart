import 'attribution_keys.dart';
import 'backend_endpoint.dart';
import 'legal_links.dart';

// Single facade for read-only environment values referenced across the
// gray flow. Anything secret resolves lazily via the cipher; static
// identifiers live as inline constants.
class Env {
  Env._();

  // Android applicationId — must match the value in android/app/build.gradle.kts
  // and the package= attribute in the Play Console.
  static const String bundleId = 'com.frenzyfeath.featherdash';

  // Store identifier sent in the config request body. On Android this
  // is the package name; iOS would use a numeric App Store id.
  static const String storeId = 'com.frenzyfeath.featherdash';

  // User-facing app display name — used for FCM channel names and the
  // initial-launch system title.
  static const String displayName = 'Feather Dash';

  // iOS only — leave empty for Android-only titles.
  static const String iosStoreId = '';

  // Lazy resolvers ----------------------------------------------------

  static String get backendUrl => resolveBackendEndpoint();

  static String get attributionKey => resolveAttributionKey();

  static String get messagingSenderId => resolveMessagingSenderId();

  static String get privacyUrl => privacyPolicyUrl;

  static String get supportUrl => supportPageUrl;

  // Tuning constants --------------------------------------------------

  // Seconds the push-promo skip lasts. Spec asks for 3 days exactly.
  static const int pushPromoSkipSeconds = 3 * 24 * 60 * 60;

  // Backoff before re-asking AppsFlyer for conversion data when the
  // first callback reports af_status="Organic". Five seconds matches
  // the SDK's recommended cooldown.
  static const int organicRetryDelay = 5;

  // Backend request timeout (seconds).
  static const int backendTimeout = 15;
}
