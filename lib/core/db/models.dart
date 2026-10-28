import 'dart:convert';
import 'package:crypto/crypto.dart';

enum TxnType {
  debit,
  credit;

  static TxnType fromString(String? raw) {
    return raw?.toLowerCase() == 'credit' ? TxnType.credit : TxnType.debit;
  }
}

enum PaymentMode {
  upi('UPI'),
  card('Card'),
  cash('Cash'),
  netBanking('NetBanking');

  final String label;
  const PaymentMode(this.label);

  static PaymentMode fromString(String? raw) {
    final s = (raw ?? '').toLowerCase();
    if (s.contains('card') || s.contains('pos')) return PaymentMode.card;
    if (s.contains('cash')) return PaymentMode.cash;
    if (s.contains('net') || s.contains('neft') || s.contains('imps')) {
      return PaymentMode.netBanking;
    }
    return PaymentMode.upi;
  }
}

enum TxnSource {
  manual,
  screenshot,
  voice,
  sms,
  statement,
  splitSettlement;

  static TxnSource fromString(String? raw) {
    return TxnSource.values.firstWhere(
      (e) => e.name.toLowerCase() == (raw ?? '').toLowerCase(),
      orElse: () => TxnSource.manual,
    );
  }
}

class AccountModel {
  final String id;
  final String name;
  final String type; // bank | upi | cash
  final int initialBalancePaise;
  final int colorValue;

  const AccountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.initialBalancePaise,
    required this.colorValue,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'initial_balance_paise': initialBalancePaise,
        'color_value': colorValue,
      };

  factory AccountModel.fromMap(Map<String, Object?> map) => AccountModel(
        id: map['id'] as String,
        name: map['name'] as String,
        type: map['type'] as String,
        initialBalancePaise: (map['initial_balance_paise'] as num).toInt(),
        colorValue: (map['color_value'] as num).toInt(),
      );
}

class CategoryModel {
  final String id;
  final String name;
  final String iconKey;
  final int colorValue;
  final int monthlyBudgetPaise;
  final bool isIncome;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.monthlyBudgetPaise,
    this.isIncome = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon_key': iconKey,
        'color_value': colorValue,
        'monthly_budget_paise': monthlyBudgetPaise,
        'is_income': isIncome ? 1 : 0,
      };

  factory CategoryModel.fromMap(Map<String, Object?> map) => CategoryModel(
        id: map['id'] as String,
        name: map['name'] as String,
        iconKey: map['icon_key'] as String,
        colorValue: (map['color_value'] as num).toInt(),
        monthlyBudgetPaise: (map['monthly_budget_paise'] as num).toInt(),
        isIncome: ((map['is_income'] as num?)?.toInt() ?? 0) == 1,
      );
}

class TransactionModel {
  final String id;
  final int amountPaise;
  final TxnType type;
  final String currency;
  final String title;
  final String counterparty;
  final String categoryId;
  final String accountId;
  final DateTime occurredAt;
  final PaymentMode paymentMode;
  final String? referenceId;
  final TxnSource source;
  final String dedupeHash;
  final List<String> tags;
  final String? note;

  const TransactionModel({
    required this.id,
    required this.amountPaise,
    required this.type,
    this.currency = 'INR',
    required this.title,
    required this.counterparty,
    required this.categoryId,
    required this.accountId,
    required this.occurredAt,
    required this.paymentMode,
    this.referenceId,
    required this.source,
    required this.dedupeHash,
    this.tags = const [],
    this.note,
  });

  static String computeDedupeHash({
    required int amountPaise,
    required TxnType type,
    required DateTime occurredAt,
    required String counterparty,
    String? referenceId,
  }) {
    final cleanRef = referenceId?.trim().toLowerCase() ?? '';
    if (cleanRef.isNotEmpty && cleanRef.length >= 6) {
      return sha1.convert(utf8.encode('ref:$cleanRef')).toString();
    }
    final dayKey =
        '${occurredAt.year}-${occurredAt.month.toString().padLeft(2, '0')}-${occurredAt.day.toString().padLeft(2, '0')}';
    final normParty = counterparty
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final payload = '${type.name}|$amountPaise|$dayKey|$normParty';
    return sha1.convert(utf8.encode(payload)).toString();
  }

  TransactionModel copyWith({
    String? id,
    int? amountPaise,
    TxnType? type,
    String? currency,
    String? title,
    String? counterparty,
    String? categoryId,
    String? accountId,
    DateTime? occurredAt,
    PaymentMode? paymentMode,
    String? referenceId,
    TxnSource? source,
    String? dedupeHash,
    List<String>? tags,
    String? note,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      amountPaise: amountPaise ?? this.amountPaise,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      title: title ?? this.title,
      counterparty: counterparty ?? this.counterparty,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      occurredAt: occurredAt ?? this.occurredAt,
      paymentMode: paymentMode ?? this.paymentMode,
      referenceId: referenceId ?? this.referenceId,
      source: source ?? this.source,
      dedupeHash: dedupeHash ?? this.dedupeHash,
      tags: tags ?? this.tags,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'amount_paise': amountPaise,
        'type': type.name,
        'currency': currency,
        'title': title,
        'counterparty': counterparty,
        'category_id': categoryId,
        'account_id': accountId,
        'occurred_at_ms': occurredAt.millisecondsSinceEpoch,
        'payment_mode': paymentMode.name,
        'reference_id': referenceId,
        'source': source.name,
        'dedupe_hash': dedupeHash,
        'tags_json': jsonEncode(tags),
        'note': note,
      };

  factory TransactionModel.fromMap(Map<String, Object?> map) {
    final rawTags = map['tags_json'] as String?;
    List<String> parsedTags = const [];
    if (rawTags != null && rawTags.isNotEmpty) {
      try {
        parsedTags = (jsonDecode(rawTags) as List).cast<String>();
      } catch (_) {}
    }

    return TransactionModel(
      id: map['id'] as String,
      amountPaise: (map['amount_paise'] as num).toInt(),
      type: TxnType.fromString(map['type'] as String?),
      currency: (map['currency'] as String?) ?? 'INR',
      title: map['title'] as String,
      counterparty: (map['counterparty'] as String?) ?? '',
      categoryId: map['category_id'] as String,
      accountId: map['account_id'] as String,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        (map['occurred_at_ms'] as num).toInt(),
      ),
      paymentMode: PaymentMode.fromString(map['payment_mode'] as String?),
      referenceId: map['reference_id'] as String?,
      source: TxnSource.fromString(map['source'] as String?),
      dedupeHash: map['dedupe_hash'] as String,
      tags: parsedTags,
      note: map['note'] as String?,
    );
  }
}

class SplitShareModel {
  final String id;
  final String transactionId;
  final String friendName;
  final String? friendUpiVpa;
  final int sharePaise;
  final bool isSettled;
  final DateTime createdAt;
  final DateTime? settledAt;

  const SplitShareModel({
    required this.id,
    required this.transactionId,
    required this.friendName,
    this.friendUpiVpa,
    required this.sharePaise,
    this.isSettled = false,
    required this.createdAt,
    this.settledAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'transaction_id': transactionId,
        'friend_name': friendName,
        'friend_upi_vpa': friendUpiVpa,
        'share_paise': sharePaise,
        'is_settled': isSettled ? 1 : 0,
        'created_at_ms': createdAt.millisecondsSinceEpoch,
        'settled_at_ms': settledAt?.millisecondsSinceEpoch,
      };

  factory SplitShareModel.fromMap(Map<String, Object?> map) => SplitShareModel(
        id: map['id'] as String,
        transactionId: map['transaction_id'] as String,
        friendName: map['friend_name'] as String,
        friendUpiVpa: map['friend_upi_vpa'] as String?,
        sharePaise: (map['share_paise'] as num).toInt(),
        isSettled: ((map['is_settled'] as num?)?.toInt() ?? 0) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at_ms'] as num).toInt(),
        ),
        settledAt: map['settled_at_ms'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (map['settled_at_ms'] as num).toInt(),
              ),
      );
}

class ImpulseItemModel {
  final String id;
  final String title;
  final int pricePaise;
  final String categoryId;
  final DateTime createdAt;
  final DateTime unlockAt;
  final String status; // locked | purchased | skipped
  final String? reasonNote;

  const ImpulseItemModel({
    required this.id,
    required this.title,
    required this.pricePaise,
    required this.categoryId,
    required this.createdAt,
    required this.unlockAt,
    this.status = 'locked',
    this.reasonNote,
  });

  bool isCoolingDown(DateTime now) =>
      status == 'locked' && unlockAt.isAfter(now);

  bool isReadyForDecision(DateTime now) =>
      status == 'locked' && !unlockAt.isAfter(now);

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'price_paise': pricePaise,
        'category_id': categoryId,
        'created_at_ms': createdAt.millisecondsSinceEpoch,
        'unlock_at_ms': unlockAt.millisecondsSinceEpoch,
        'status': status,
        'reason_note': reasonNote,
      };

  factory ImpulseItemModel.fromMap(Map<String, Object?> map) =>
      ImpulseItemModel(
        id: map['id'] as String,
        title: map['title'] as String,
        pricePaise: (map['price_paise'] as num).toInt(),
        categoryId: map['category_id'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at_ms'] as num).toInt(),
        ),
        unlockAt: DateTime.fromMillisecondsSinceEpoch(
          (map['unlock_at_ms'] as num).toInt(),
        ),
        status: (map['status'] as String?) ?? 'locked',
        reasonNote: map['reason_note'] as String?,
      );
}

