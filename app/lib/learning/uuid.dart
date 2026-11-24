import 'dart:math' as math;
import 'dart:typed_data';

final _secure = math.Random.secure();

Uint8List _randomBytes(int n) =>
    Uint8List.fromList([for (var i = 0; i < n; i++) _secure.nextInt(256)]);

/// UUIDv7 (RFC 9562): 48-bit millisecond timestamp, version, variant, random bits.
String uuidv7([int? now, Uint8List Function(int n) random = _randomBytes]) {
  final b = random(16);
  var ms = now ?? DateTime.now().millisecondsSinceEpoch;
  for (var i = 5; i >= 0; i--) {
    b[i] = ms % 256;
    ms ~/= 256;
  }
  b[6] = (b[6] & 0x0f) | 0x70; // version 7
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
