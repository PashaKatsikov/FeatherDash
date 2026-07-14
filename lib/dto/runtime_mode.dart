// Tri-state the launcher resolves to before navigating away from the
// boot gate. The value is persisted across launches so the backend's
// verdict is sticky — a paid install never silently degrades back to
// the offline game just because attribution flaked once.
enum RuntimeMode {
  // Boot gate has not yet received a backend verdict.
  unresolved,

  // Backend returned a WebView URL — the user is in the partner shell.
  partner,

  // Backend returned ok=false or the request failed permanently —
  // the user only ever sees the offline game from here on.
  arcade;

  static RuntimeMode parse(String? raw) {
    switch (raw) {
      case 'partner':
        return RuntimeMode.partner;
      case 'arcade':
        return RuntimeMode.arcade;
      default:
        return RuntimeMode.unresolved;
    }
  }

  String get persisted {
    switch (this) {
      case RuntimeMode.partner:
        return 'partner';
      case RuntimeMode.arcade:
        return 'arcade';
      case RuntimeMode.unresolved:
        return 'unresolved';
    }
  }
}
