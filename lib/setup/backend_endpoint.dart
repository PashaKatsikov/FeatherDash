import '../cipher/scrambler.dart';

// Resolves the backend config endpoint URL.
// The host and path live as separate XOR-scrambled byte vectors so the
// recombined URL never appears as a single contiguous literal in the
// shipped artifact.
//
// Plain value: https://feattherdash.com/config.php
//
// Regenerate via `dart run tool/encode_keys.dart` if the cipher seed
// or endpoint changes.
String resolveBackendEndpoint() {
  const host = <int>[
    0x76, 0xd4, 0x77, 0xd5, 0x34, 0xbb, 0x42, 0xb0,
    0xe7, 0x3a, 0xba, 0x15, 0xfe, 0x99, 0x5e, 0x68,
    0x47, 0x1f, 0xc6, 0xc3, 0x30, 0xc3, 0x6c, 0xc8,
  ];
  const path = <int>[
    0x31, 0xc3, 0x6c, 0xcb, 0x21, 0xe8, 0x0a, 0xb1,
    0xf1, 0x37, 0xab,
  ];
  if (host.isEmpty) return '';
  return unscramble(host) + unscramble(path);
}
