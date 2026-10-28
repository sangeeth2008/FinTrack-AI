import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class EncryptedBackupService {
  static const String magicHeader = 'FINTRACK_AES256GCM_V1';
  static const int _pbkdf2Iterations = 150000;

  final AesGcm _cipher = AesGcm.with256bits();

  Future<String> encryptSnapshotToJson({
    required Map<String, dynamic> snapshot,
    required String passphrase,
  }) async {
    if (passphrase.trim().length < 4) {
      throw ArgumentError('Backup passphrase must be at least 4 characters');
    }

    final rng = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    final nonce = List<int>.generate(12, (_) => rng.nextInt(256));

    final secretKey = await _deriveKey(passphrase, salt);
    final cleartextBytes = utf8.encode(jsonEncode(snapshot));

    final secretBox = await _cipher.encrypt(
      cleartextBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    final envelope = {
      'magic': magicHeader,
      'iterations': _pbkdf2Iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };

    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  Future<Map<String, dynamic>> decryptJsonToSnapshot({
    required String encryptedEnvelopeJson,
    required String passphrase,
  }) async {
    final decoded = jsonDecode(encryptedEnvelopeJson);
    if (decoded is! Map || decoded['magic'] != magicHeader) {
      throw const FormatException('Invalid FinTrack backup file header');
    }

    final salt = base64Decode(decoded['salt'] as String);
    final nonce = base64Decode(decoded['nonce'] as String);
    final cipherText = base64Decode(decoded['ciphertext'] as String);
    final macBytes = base64Decode(decoded['mac'] as String);

    final secretKey = await _deriveKey(passphrase, salt);
    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final cleartextBytes = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return jsonDecode(utf8.decode(cleartextBytes)) as Map<String, dynamic>;
  }

  Future<SecretKey> _deriveKey(String passphrase, List<int> salt) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }
}

