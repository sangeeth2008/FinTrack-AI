import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/db/models.dart';

class PassphraseRequiredException implements Exception {
  final String message;
  const PassphraseRequiredException([
    this.message = 'This backup file is encrypted. Please enter your passphrase.',
  ]);

  @override
  String toString() => message;
}

class EncryptedBackupService {
  static const String magicHeader = 'FINTRACK_AES256GCM_V1';
  static const int _pbkdf2Iterations = 150000;
  static const _uuid = Uuid();

  final AesGcm _cipher = AesGcm.with256bits();

  /// Checks if [rawContent] represents an encrypted FinTrack backup envelope.
  bool isEncryptedEnvelope(dynamic raw) {
    if (raw == null) return false;
    if (raw is Map) {
      return raw['magic'] == magicHeader ||
          (raw.containsKey('ciphertext') && raw.containsKey('nonce'));
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return false;
      try {
        final decoded = jsonDecode(trimmed);
        return decoded is Map &&
            (decoded['magic'] == magicHeader ||
                (decoded.containsKey('ciphertext') &&
                    decoded.containsKey('nonce')));
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Universal entrypoint: parses plain JSON or decrypts AES-256-GCM encrypted backup.
  Future<Map<String, dynamic>> parseOrDecrypt({
    required String rawJson,
    String? passphrase,
  }) async {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty backup data provided.');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (e) {
      throw FormatException('Malformed JSON file: $e');
    }

    if (isEncryptedEnvelope(decoded)) {
      final pass = passphrase?.trim() ?? '';
      if (pass.isEmpty) {
        throw const PassphraseRequiredException();
      }
      return decryptJsonToSnapshot(
        encryptedEnvelopeJson: trimmed,
        passphrase: pass,
      );
    }

    return normalizeRawJsonSnapshot(decoded);
  }

  /// Normalizes any raw JSON object or array into a valid FinTrack database snapshot.
  Map<String, dynamic> normalizeRawJsonSnapshot(dynamic decoded) {
    if (decoded is List) {
      return {
        'schema_version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        'accounts': <Map<String, dynamic>>[],
        'categories': <Map<String, dynamic>>[],
        'transactions': normalizeTransactionsList(decoded),
        'split_shares': <Map<String, dynamic>>[],
        'impulse_items': <Map<String, dynamic>>[],
      };
    }

    if (decoded is! Map) {
      throw const FormatException('Expected a JSON Object or Array for backup data.');
    }

    final rawMap = Map<String, dynamic>.from(decoded);

    // Look for transactions list under common keys
    final txnsRaw = rawMap['transactions'] ??
        rawMap['data'] ??
        rawMap['items'] ??
        rawMap['records'] ??
        rawMap['history'];

    final rawAccounts = rawMap['accounts'];
    final rawCategories = rawMap['categories'];
    final rawSplits = rawMap['split_shares'] ?? rawMap['splits'];
    final rawImpulse = rawMap['impulse_items'] ?? rawMap['impulse'];

    return {
      'schema_version': rawMap['schema_version'] ?? 1,
      'exported_at': rawMap['exported_at'] ?? DateTime.now().toIso8601String(),
      'accounts': (rawAccounts is List)
          ? rawAccounts.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[],
      'categories': (rawCategories is List)
          ? rawCategories.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[],
      'transactions': (txnsRaw is List)
          ? normalizeTransactionsList(txnsRaw)
          : <Map<String, dynamic>>[],
      'split_shares': (rawSplits is List)
          ? rawSplits.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[],
      'impulse_items': (rawImpulse is List)
          ? rawImpulse.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : <Map<String, dynamic>>[],
    };
  }

  /// Normalizes a list of transaction objects, gracefully handling differences in
  /// naming conventions (snake_case vs camelCase, Rupees vs Paise, Date formats).
  List<Map<String, dynamic>> normalizeTransactionsList(List rawList) {
    final results = <Map<String, dynamic>>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final normalized = normalizeTransactionMap(item);
      if (normalized != null) {
        results.add(normalized);
      }
    }
    return results;
  }

  Map<String, dynamic>? normalizeTransactionMap(Map raw) {
    final m = Map<String, dynamic>.from(raw);

    // 1. Amount Paise extraction
    int amountPaise = 0;
    if (m['amount_paise'] != null) {
      amountPaise = _parsePaise(m['amount_paise']);
    } else if (m['amountPaise'] != null) {
      amountPaise = _parsePaise(m['amountPaise']);
    } else if (m['amount'] != null) {
      amountPaise = _rupeesToPaise(m['amount']);
    } else if (m['price'] != null) {
      amountPaise = _rupeesToPaise(m['price']);
    }
    if (amountPaise <= 0) return null;

    // 2. Transaction Type (debit / credit)
    final rawType = (m['type'] ?? m['txn_type'] ?? m['transactionType'] ?? '').toString().toLowerCase();
    final isCredit = rawType.contains('credit') ||
        rawType.contains('income') ||
        rawType.contains('refund') ||
        rawType.contains('deposit');
    final type = isCredit ? 'credit' : 'debit';

    // 3. Title & Counterparty
    final title = (m['title'] ??
            m['description'] ??
            m['narration'] ??
            m['counterparty'] ??
            m['merchant'] ??
            'Transaction')
        .toString()
        .trim();
    final counterparty = (m['counterparty'] ??
            m['merchant'] ??
            m['payee'] ??
            title)
        .toString()
        .trim();

    // 4. Category ID
    var categoryId = (m['category_id'] ?? m['categoryId'] ?? '').toString().trim();
    if (categoryId.isEmpty || categoryId == 'null') {
      final catName = (m['category'] ?? m['categoryName'] ?? '').toString().toLowerCase();
      categoryId = _mapCategoryNameToId(catName, isCredit: isCredit);
    }

    // 5. Payment Mode & Account ID
    final rawMode = (m['payment_mode'] ?? m['paymentMode'] ?? m['mode'] ?? 'upi').toString();
    final mode = PaymentMode.fromString(rawMode);
    var accountId = (m['account_id'] ?? m['accountId'] ?? '').toString().trim();
    if (accountId.isEmpty || accountId == 'null') {
      accountId = mode == PaymentMode.wallet
          ? AccountModel.walletAccountId
          : AccountModel.primaryAccountId;
    }

    // 6. Occurred At Milliseconds
    final occurredAtMs = _parseOccurredAtMs(m);
    final when = DateTime.fromMillisecondsSinceEpoch(occurredAtMs);

    // 7. Reference & Dedupe Hash
    final refId = (m['reference_id'] ?? m['referenceId'] ?? m['ref_no'] ?? m['utr'])?.toString().trim();
    final hash = (m['dedupe_hash'] ?? m['dedupeHash'])?.toString().trim() ??
        TransactionModel.computeDedupeHash(
          amountPaise: amountPaise,
          type: isCredit ? TxnType.credit : TxnType.debit,
          occurredAt: when,
          counterparty: counterparty.isEmpty ? title : counterparty,
          referenceId: refId,
        );

    // 8. ID & Tags
    final id = (m['id'] ?? _uuid.v4()).toString().trim();
    String tagsJson = '[]';
    if (m['tags_json'] is String) {
      tagsJson = m['tags_json'] as String;
    } else if (m['tags'] is List) {
      tagsJson = jsonEncode(m['tags']);
    }

    return {
      'id': id.isEmpty ? _uuid.v4() : id,
      'amount_paise': amountPaise,
      'type': type,
      'currency': (m['currency'] ?? 'INR').toString(),
      'title': title.isEmpty ? 'Transaction' : title,
      'counterparty': counterparty.isEmpty ? title : counterparty,
      'category_id': categoryId,
      'account_id': accountId,
      'occurred_at_ms': occurredAtMs,
      'payment_mode': mode.name,
      'reference_id': refId,
      'source': (m['source'] ?? 'backup').toString(),
      'dedupe_hash': hash,
      'tags_json': tagsJson,
      'note': m['note']?.toString(),
    };
  }

  static int _parsePaise(dynamic val) {
    if (val is int) return val;
    if (val is double) return val.round();
    if (val is String) {
      final clean = val.replaceAll(RegExp(r'[^0-9.]'), '');
      return int.tryParse(clean) ?? (double.tryParse(clean)?.round() ?? 0);
    }
    return 0;
  }

  static int _rupeesToPaise(dynamic val) {
    if (val is num) return (val * 100).round();
    if (val is String) {
      final clean = val.replaceAll(RegExp(r'[^0-9.]'), '');
      final d = double.tryParse(clean);
      if (d != null) return (d * 100).round();
    }
    return 0;
  }

  static int _parseOccurredAtMs(Map m) {
    final rawMs = m['occurred_at_ms'] ?? m['occurredAtMs'];
    if (rawMs is int) return rawMs;
    if (rawMs is String) {
      final parsed = int.tryParse(rawMs);
      if (parsed != null) return parsed;
    }

    final rawDate = m['occurred_at'] ?? m['occurredAt'] ?? m['date'] ?? m['timestamp'] ?? m['time'];
    if (rawDate is int) {
      return rawDate < 10000000000 ? rawDate * 1000 : rawDate;
    }
    if (rawDate is String) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  static String _mapCategoryNameToId(String name, {required bool isCredit}) {
    if (isCredit) {
      if (name.contains('refund') || name.contains('split')) return 'cat_income_refund';
      return 'cat_income_salary';
    }
    final lower = name.toLowerCase();
    if (lower.contains('food') || lower.contains('eat') || lower.contains('snack') || lower.contains('swiggy') || lower.contains('zomato')) {
      return 'cat_food';
    }
    if (lower.contains('travel') || lower.contains('commute') || lower.contains('auto') || lower.contains('cab') || lower.contains('uber') || lower.contains('ola') || lower.contains('fuel')) {
      return 'cat_commute';
    }
    if (lower.contains('college') || lower.contains('book') || lower.contains('study') || lower.contains('course')) {
      return 'cat_college';
    }
    if (lower.contains('tech') || lower.contains('gadget') || lower.contains('comp') || lower.contains('device')) {
      return 'cat_tech';
    }
    if (lower.contains('sub') || lower.contains('netflix') || lower.contains('spotify') || lower.contains('prime')) {
      return 'cat_subscriptions';
    }
    if (lower.contains('movie') || lower.contains('fun') || lower.contains('game')) {
      return 'cat_entertainment';
    }
    if (lower.contains('bill') || lower.contains('recharge') || lower.contains('electric') || lower.contains('wifi')) {
      return 'cat_utilities';
    }
    return 'cat_other';
  }

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

