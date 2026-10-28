import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class PinHasher {
  final int iterations;

  const PinHasher({this.iterations = 210000});

  List<int> generateSalt({int length = 16}) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  Future<List<int>> deriveBytes(String pin, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    return secretKey.extractBytes();
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
      return constantTimeEquals(actualBytes, expectedBytes);
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

