import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class PinHasher {
  static const int legacyIterations = 210000;
  final int iterations;

  const PinHasher({this.iterations = 12000});

  List<int> generateSalt({int length = 16}) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  static Future<List<int>> _derivePbkdf2InIsolate(
    String pin,
    List<int> salt,
    int iterCount,
  ) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterCount,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    return secretKey.extractBytes();
  }

  Future<List<int>> deriveBytes(String pin, List<int> salt) async {
    final iterCount = iterations;
    final saltCopy = List<int>.from(salt);
    return Isolate.run(
      () => _derivePbkdf2InIsolate(pin, saltCopy, iterCount),
    );
  }

  Future<({String hashBase64, String saltBase64})> createPinRecord(
    String pin,
  ) async {
    final salt = generateSalt();
    final hashBytes = await deriveBytes(pin, salt);
    return (
      hashBase64: base64Encode(hashBytes),
      saltBase64: base64Encode(salt),
    );
  }

  Future<bool> verifyPin(
    String candidatePin, {
    required String storedHashBase64,
    required String storedSaltBase64,
  }) async {
    try {
      final salt = base64Decode(storedSaltBase64);
      final expectedBytes = base64Decode(storedHashBase64);
      final actualBytes = await deriveBytes(candidatePin, salt);
      if (constantTimeEquals(actualBytes, expectedBytes)) {
        return true;
      }
      // Transparently support PINs created with legacy 210,000 iteration count
      if (iterations != legacyIterations && iterations == 12000) {
        final legacyBytes = await Isolate.run(
          () => _derivePbkdf2InIsolate(
            candidatePin,
            List<int>.from(salt),
            legacyIterations,
          ),
        );
        return constantTimeEquals(legacyBytes, expectedBytes);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

