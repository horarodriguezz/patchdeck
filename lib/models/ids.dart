import 'dart:math';

final Random _rng = Random.secure();

/// Short random hex id, unique enough for local documents.
String newId() {
  final b = StringBuffer();
  for (var i = 0; i < 12; i++) {
    b.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}
