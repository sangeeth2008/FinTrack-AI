import '../../../core/db/models.dart';
import '../../../core/gemini/gemini_service.dart';

class SmsRegexParser {
  static final RegExp _amountRegex = RegExp(
    r'(?:Rs\.?|INR|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static final RegExp _debitKeywordRegex = RegExp(
    r'\b(debited|spent|paid|sent|withdrawn|purchase|charged|dr)\b',
    caseSensitive: false,
  );

  static final RegExp _creditKeywordRegex = RegExp(
    r'\b(credited|received|deposited|refund|cashback|added|cr)\b',
    caseSensitive: false,
  );

  static final RegExp _refRegex = RegExp(
    r'(?:Ref(?:\s*No\.?)?|UTR|UPI(?:\s*Ref)?|Txn(?:\s*ID)?)\s*[:\-]?\s*([A-Za-z0-9]{6,22})',
    caseSensitive: false,
  );

  static final RegExp _counterpartyRegex = RegExp(
    r'(?:to|at|from|towards|VPA|info[:\s])\s+([A-Za-z0-9@._\-\s]{3,28}?)(?:\s+on\b|\s+Ref\b|\s+UPI\b|\.|$)',
    caseSensitive: false,
  );

  /// Parses single or multi-line SMS / transaction text blocks locally.
  static List<ParsedTransactionDraft> parseTextBlock(
    String rawText, {
    DateTime? fallbackTime,
  }) {
    final now = fallbackTime ?? DateTime.now();
    final lines = rawText
        .split(RegExp(r'\r?\n+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final results = <ParsedTransactionDraft>[];
    for (final line in lines) {
      final parsed = parseSingleMessage(line, fallbackTime: now);
      if (parsed != null) {
        results.add(parsed);
      }
    }

    if (results.isEmpty && rawText.trim().isNotEmpty) {
      final single = parseSingleMessage(rawText.trim(), fallbackTime: now);
      if (single != null) results.add(single);
    }

    return results;
  }

  static ParsedTransactionDraft? parseSingleMessage(
    String message, {
    DateTime? fallbackTime,
  }) {
    final amountMatch = _amountRegex.firstMatch(message);
    if (amountMatch == null) return null;

    final rawAmount = (amountMatch.group(1) ?? '').replaceAll(',', '');
    final rupees = double.tryParse(rawAmount);
    if (rupees == null || rupees <= 0) return null;
    final amountPaise = (rupees * 100).round();

    final hasCredit = _creditKeywordRegex.hasMatch(message);
    final hasDebit = _debitKeywordRegex.hasMatch(message);
    if (!hasCredit && !hasDebit) return null;

    final type = (hasCredit && !hasDebit) ? TxnType.credit : TxnType.debit;

    String counterparty = '';
    final partyMatch = _counterpartyRegex.firstMatch(message);
    if (partyMatch != null) {
      counterparty = (partyMatch.group(1) ?? '').trim();
    }
    if (counterparty.isEmpty) {
      counterparty = type == TxnType.credit ? 'Bank Deposit' : 'Merchant Spend';
    }

    final refMatch = _refRegex.firstMatch(message);
    final referenceId = refMatch?.group(1)?.trim();

    final lower = message.toLowerCase();
    final paymentMode = lower.contains('card') || lower.contains('pos')
        ? PaymentMode.card
        : (lower.contains('neft') || lower.contains('imps')
              ? PaymentMode.netBanking
              : PaymentMode.upi);

    final categoryId = inferCategoryId(
      text: '$counterparty $message',
      type: type,
    );

    final title = type == TxnType.credit
        ? 'Received • $counterparty'
        : counterparty;

    return ParsedTransactionDraft(
      title: title,
      amountPaise: amountPaise,
      type: type,
      currency: 'INR',
      categoryId: categoryId,
      occurredAt: fallbackTime ?? DateTime.now(),
      paymentMode: paymentMode,
      counterparty: counterparty,
      referenceId: referenceId,
      source: TxnSource.sms,
    );
  }

  static String inferCategoryId({
    required String text,
    required TxnType type,
  }) {
    if (type == TxnType.credit) {
      final s = text.toLowerCase();
      if (s.contains('refund') ||
          s.contains('split') ||
          s.contains('cashback')) {
        return 'cat_income_refund';
      }
      return 'cat_income_salary';
    }

    final s = text.toLowerCase();
    if (_matchesAny(s, [
      'swiggy',
      'zomato',
      'canteen',
      'mess',
      'cafe',
      'coffee',
      'tea',
      'restaurant',
      'food',
      'bakery',
      'snacks',
      'dominos',
      'kfc',
    ])) {
      return 'cat_food';
    }
    if (_matchesAny(s, [
      'robu',
      'arduino',
      'raspberry',
      'sensor',
      'electronics',
      'amazon',
      'flipkart',
      'tech',
      'laptop',
      'github',
      'cloud',
    ])) {
      return 'cat_tech';
    }
    if (_matchesAny(s, [
      'uber',
      'ola',
      'rapido',
      'auto',
      'rickshaw',
      'metro',
      'bus',
      'irctc',
      'rail',
      'petrol',
      'fuel',
      'cab',
    ])) {
      return 'cat_commute';
    }
    if (_matchesAny(s, [
      'college',
      'tuition',
      'semester',
      'exam',
      'hostel',
      'book',
      'stationery',
      'xerox',
      'print',
    ])) {
      return 'cat_college';
    }
    if (_matchesAny(s, [
      'netflix',
      'spotify',
      'youtube',
      'prime',
      'subscription',
      'icloud',
      'chatgpt',
    ])) {
      return 'cat_subscriptions';
    }
    if (_matchesAny(s, [
      'movie',
      'pvr',
      'inox',
      'bookmyshow',
      'game',
      'steam',
    ])) {
      return 'cat_entertainment';
    }
    if (_matchesAny(s, [
      'jio',
      'airtel',
      'vi ',
      'bsnl',
      'electricity',
      'water',
      'gas',
      'wifi',
      'broadband',
      'recharge',
    ])) {
      return 'cat_utilities';
    }
    return 'cat_other';
  }

  static bool _matchesAny(String haystack, List<String> keywords) {
    for (final kw in keywords) {
      if (haystack.contains(kw)) return true;
    }
    return false;
  }
}

