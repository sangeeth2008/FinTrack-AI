import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../db/models.dart';
import '../security/secure_store.dart';

class ParsedTransactionDraft {
  final String title;
  final int amountPaise;
  final TxnType type;
  final String currency;
  final String categoryId;
  final DateTime occurredAt;
  final PaymentMode paymentMode;
  final String counterparty;
  final String? referenceId;
  final List<String> splitFriends;
  final TxnSource source;

  const ParsedTransactionDraft({
    required this.title,
    required this.amountPaise,
    required this.type,
    this.currency = 'INR',
    required this.categoryId,
    required this.occurredAt,
    required this.paymentMode,
    required this.counterparty,
    this.referenceId,
    this.splitFriends = const [],
    required this.source,
  });

  TransactionModel toTransactionModel({
    required String id,
    required String accountId,
    List<String> tags = const [],
    String? note,
  }) {
    final hash = TransactionModel.computeDedupeHash(
      amountPaise: amountPaise,
      type: type,
      occurredAt: occurredAt,
      counterparty: counterparty.isEmpty ? title : counterparty,
      referenceId: referenceId,
    );
    return TransactionModel(
      id: id,
      amountPaise: amountPaise,
      type: type,
      currency: currency,
      title: title,
      counterparty: counterparty.isEmpty ? title : counterparty,
      categoryId: categoryId,
      accountId: accountId,
      occurredAt: occurredAt,
      paymentMode: paymentMode,
      referenceId: referenceId,
      source: source,
      dedupeHash: hash,
      tags: tags,
      note: note,
    );
  }
}

class AuditRecommendation {
  final String title;
  final String action;
  final int estimatedMonthlySavingPaise;

  const AuditRecommendation({
    required this.title,
    required this.action,
    required this.estimatedMonthlySavingPaise,
  });
}

class DailySummaryReport {
  final DateTime date;
  final int spentTodayPaise;
  final int creditedTodayPaise;
  final int dailyLimitPaise;
  final bool isOverLimit;
  final String headline;
  final String analysis;
  final String topSpendTitle;
  final int topSpendPaise;
  final String takeawayForTomorrow;
  final Map<String, int> categoryBreakdownPaise;
  final bool isAiGenerated;

  const DailySummaryReport({
    required this.date,
    required this.spentTodayPaise,
    required this.creditedTodayPaise,
    required this.dailyLimitPaise,
    required this.isOverLimit,
    required this.headline,
    required this.analysis,
    required this.topSpendTitle,
    required this.topSpendPaise,
    required this.takeawayForTomorrow,
    required this.categoryBreakdownPaise,
    required this.isAiGenerated,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'spentTodayPaise': spentTodayPaise,
        'creditedTodayPaise': creditedTodayPaise,
        'dailyLimitPaise': dailyLimitPaise,
        'isOverLimit': isOverLimit,
        'headline': headline,
        'analysis': analysis,
        'topSpendTitle': topSpendTitle,
        'topSpendPaise': topSpendPaise,
        'takeawayForTomorrow': takeawayForTomorrow,
        'categoryBreakdownPaise': categoryBreakdownPaise,
        'isAiGenerated': isAiGenerated,
      };

  factory DailySummaryReport.fromJson(Map<String, dynamic> json) {
    final catRaw = json['categoryBreakdownPaise'] as Map? ?? const {};
    final catMap = <String, int>{};
    catRaw.forEach((k, v) {
      if (v is num) catMap[k.toString()] = v.round();
    });

    return DailySummaryReport(
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      spentTodayPaise: (json['spentTodayPaise'] as num?)?.round() ?? 0,
      creditedTodayPaise: (json['creditedTodayPaise'] as num?)?.round() ?? 0,
      dailyLimitPaise: (json['dailyLimitPaise'] as num?)?.round() ?? 150000,
      isOverLimit: json['isOverLimit'] == true,
      headline: (json['headline'] as String?) ?? 'Daily Spend Summary',
      analysis: (json['analysis'] as String?) ?? '',
      topSpendTitle: (json['topSpendTitle'] as String?) ?? 'None',
      topSpendPaise: (json['topSpendPaise'] as num?)?.round() ?? 0,
      takeawayForTomorrow: (json['takeawayForTomorrow'] as String?) ?? '',
      categoryBreakdownPaise: catMap,
      isAiGenerated: json['isAiGenerated'] == true,
    );
  }
}

class MonthlyAuditReport {
  final String headline;
  final String cashflowSummary;
  final List<String> leakInsights;
  final List<AuditRecommendation> recommendations;
  final bool isAiGenerated;

  const MonthlyAuditReport({
    required this.headline,
    required this.cashflowSummary,
    required this.leakInsights,
    required this.recommendations,
    required this.isAiGenerated,
  });
}

class GeminiService {
  static const String modelId = 'gemini-3.8-flash';
  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/interactions';

  final Dio _dio;
  final SecureStore secureStore;

  GeminiService({Dio? dio, required this.secureStore})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 25),
                receiveTimeout: const Duration(seconds: 40),
              ),
            );

  static const Map<String, dynamic> _transactionsJsonSchema = {
    'type': 'object',
    'properties': {
      'transactions': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'amount': {'type': 'number'},
            'type': {
              'type': 'string',
              'enum': ['debit', 'credit'],
            },
            'currency': {'type': 'string'},
            'category_id': {
              'type': 'string',
              'enum': [
                'cat_food',
                'cat_tech',
                'cat_commute',
                'cat_college',
                'cat_subscriptions',
                'cat_entertainment',
                'cat_utilities',
                'cat_other',
                'cat_income_salary',
                'cat_income_refund',
              ],
            },
            'date': {
              'type': 'string',
              'description': 'YYYY-MM-DD',
            },
            'time': {
              'type': 'string',
              'description': 'HH:mm in 24h format',
            },
            'payment_mode': {
              'type': 'string',
              'enum': ['UPI', 'Card', 'Cash', 'NetBanking'],
            },
            'payer_or_payee': {'type': 'string'},
            'reference_id': {'type': 'string'},
            'split_friends': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'required': [
            'title',
            'amount',
            'type',
            'category_id',
            'payment_mode',
          ],
        },
      },
    },
    'required': ['transactions'],
  };

  static const Map<String, dynamic> _auditJsonSchema = {
    'type': 'object',
    'properties': {
      'headline': {'type': 'string'},
      'cashflow_summary': {'type': 'string'},
      'leak_insights': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'recommendations': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'action': {'type': 'string'},
            'estimated_monthly_saving_inr': {'type': 'number'},
          },
          'required': [
            'title',
            'action',
            'estimated_monthly_saving_inr',
          ],
        },
      },
    },
    'required': [
      'headline',
      'cashflow_summary',
      'leak_insights',
      'recommendations',
    ],
  };

  static const Map<String, dynamic> _dailySummaryJsonSchema = {
    'type': 'object',
    'properties': {
      'headline': {'type': 'string'},
      'status': {
        'type': 'string',
        'enum': ['under_limit', 'over_limit', 'no_spend'],
      },
      'analysis': {'type': 'string'},
      'top_spend_title': {'type': 'string'},
      'top_spend_amount_inr': {'type': 'number'},
      'takeaway_for_tomorrow': {'type': 'string'},
    },
    'required': [
      'headline',
      'status',
      'analysis',
      'top_spend_title',
      'top_spend_amount_inr',
      'takeaway_for_tomorrow',
    ],
  };

  static const String _parserSystemInstruction =
      'You are a deterministic Indian financial transaction parser for FinTrack AI. '
      'Extract every transaction from the user input (payment screenshot, voice note, SMS, or bank statement). '
      'Distinguish carefully between money spent/debited ("debit") and money received/credited ("credit"). '
      'Map categories strictly to the provided category_id enum. '
      'Return pure JSON matching the schema.';

  static String detectImageMimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  static String _cleanJsonString(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      cleaned = cleaned.substring(firstBrace, lastBrace + 1);
    }
    return cleaned;
  }

  static String _formatDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map && err['message'] is String) {
        return 'Gemini API Error (${e.response?.statusCode ?? ''}): ${err['message']}';
      }
      if (data['message'] is String) {
        return 'Gemini API Error (${e.response?.statusCode ?? ''}): ${data['message']}';
      }
    } else if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map &&
            decoded['error'] is Map &&
            decoded['error']['message'] is String) {
          return 'Gemini API Error (${e.response?.statusCode ?? ''}): ${decoded['error']['message']}';
        }
      } catch (_) {}
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Network error connecting to Gemini API. Check your internet connection.';
    }
    return 'Gemini API request failed (HTTP ${e.response?.statusCode ?? 'unknown'}): ${e.message}';
  }

  Future<Map<String, dynamic>> _callInteractionsJson({
    required String systemInstruction,
    required List<Map<String, dynamic>> inputBlocks,
    required Map<String, dynamic> schema,
  }) async {
    final rawKey = await secureStore.getGeminiApiKey();
    final apiKey = rawKey?.trim().replaceAll('"', '').replaceAll("'", '');
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError(
        'Gemini API key not configured. Paste your key in the box above or in Settings to enable AI vision.',
      );
    }

    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
      'Api-Revision': '2026-05-20',
    };

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        options: Options(headers: headers),
        data: {
          'model': modelId,
          'store': false,
          'system_instruction': systemInstruction,
          'input': inputBlocks,
          'response_format': {
            'type': 'text',
            'mime_type': 'application/json',
            'schema': schema,
          },
        },
      );

      final body = response.data;
      if (body == null) {
        throw const FormatException('Empty response from Gemini API');
      }

      final rawText = _cleanJsonString(extractOutputText(body));
      return jsonDecode(rawText) as Map<String, dynamic>;
    } on DioException catch (firstErr) {
      // Retry without response_format in case multimodal + strict schema combination is rejected
      final status = firstErr.response?.statusCode ?? 0;
      if (status == 400 || status == 404 || status == 422 || status == 500) {
        try {
          final fallbackBlocks = [
            ...inputBlocks,
            {
              'type': 'text',
              'text':
                  'Return ONLY a valid JSON object matching this exact schema (no markdown fences):\n${jsonEncode(schema)}',
            },
          ];
          final retryResponse = await _dio.post<Map<String, dynamic>>(
            _endpoint,
            options: Options(headers: headers),
            data: {
              'model': modelId,
              'system_instruction': systemInstruction,
              'input': fallbackBlocks,
            },
          );
          final retryBody = retryResponse.data;
          if (retryBody != null) {
            final rawText = _cleanJsonString(extractOutputText(retryBody));
            return jsonDecode(rawText) as Map<String, dynamic>;
          }
        } on DioException catch (secondErr) {
          throw StateError(_formatDioError(secondErr));
        } catch (_) {}
      }
      throw StateError(_formatDioError(firstErr));
    }
  }

  static String extractOutputText(Map<String, dynamic> interactionJson) {
    final direct = interactionJson['output_text'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }

    final steps = interactionJson['steps'];
    if (steps is List) {
      for (final step in steps.reversed) {
        if (step is Map && step['type'] == 'model_output') {
          final content = step['content'];
          if (content is List) {
            for (final item in content) {
              if (item is Map && item['text'] is String) {
                return (item['text'] as String).trim();
              }
            }
          }
        }
      }
    }

    final outputs = interactionJson['outputs'];
    if (outputs is List && outputs.isNotEmpty) {
      final last = outputs.last;
      if (last is Map && last['text'] is String) {
        return (last['text'] as String).trim();
      }
    }

    final candidates = interactionJson['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final first = candidates.first;
      if (first is Map && first['content'] is Map) {
        final parts = (first['content'] as Map)['parts'];
        if (parts is List) {
          for (final part in parts) {
            if (part is Map && part['text'] is String) {
              return (part['text'] as String).trim();
            }
          }
        }
      }
    }

    throw const FormatException('Could not locate JSON output in interaction');
  }

  Future<List<ParsedTransactionDraft>> parsePaymentScreenshot(
    Uint8List imageBytes, {
    String? mimeType,
  }) async {
    final resolvedMime =
        (mimeType != null && mimeType.trim().isNotEmpty)
            ? mimeType
            : detectImageMimeType(imageBytes);
    final jsonMap = await _callInteractionsJson(
      systemInstruction: _parserSystemInstruction,
      inputBlocks: [
        {
          'type': 'text',
          'text':
              'Extract all payment details (amount in INR, debit/credit, payee/payer name, date YYYY-MM-DD, time HH:mm, UPI reference ID/UTR, payment mode) from this payment screenshot. '
              'If the screenshot shows "Paid to", "Sent to", "Debited", or a green checkmark payment receipt from GPay/PhonePe/Paytm, mark type as "debit" unless it explicitly says "Received from" or "Credited to your account".',
        },
        {
          'type': 'image',
          'data': base64Encode(imageBytes),
          'mime_type': resolvedMime,
        },
      ],
      schema: _transactionsJsonSchema,
    );
    return _mapDrafts(jsonMap, TxnSource.screenshot);
  }

  Future<List<ParsedTransactionDraft>> parseVoiceNote(
    Uint8List audioBytes, {
    String mimeType = 'audio/mp4',
  }) async {
    final jsonMap = await _callInteractionsJson(
      systemInstruction: _parserSystemInstruction,
      inputBlocks: [
        {
          'type': 'text',
          'text':
              'Extract all expenses or income items mentioned in this voice note, including friend names if the user mentions splitting.',
        },
        {
          'type': 'audio',
          'mime_type': mimeType,
          'data': base64Encode(audioBytes),
        },
      ],
      schema: _transactionsJsonSchema,
    );
    return _mapDrafts(jsonMap, TxnSource.voice);
  }

  Future<List<ParsedTransactionDraft>> parseTextTransactions(
    String rawText, {
    TxnSource source = TxnSource.sms,
  }) async {
    final jsonMap = await _callInteractionsJson(
      systemInstruction: _parserSystemInstruction,
      inputBlocks: [
        {
          'type': 'text',
          'text':
              'Extract every financial transaction (debit or credit) from the following text:\n$rawText',
        },
      ],
      schema: _transactionsJsonSchema,
    );
    return _mapDrafts(jsonMap, source);
  }

  Future<List<ParsedTransactionDraft>> parsePdfStatement(
    Uint8List pdfBytes,
  ) async {
    final jsonMap = await _callInteractionsJson(
      systemInstruction: _parserSystemInstruction,
      inputBlocks: [
        {
          'type': 'text',
          'text':
              'Extract all transactions (both debits/withdrawals and credits/deposits) from this bank statement PDF.',
        },
        {
          'type': 'document',
          'mime_type': 'application/pdf',
          'data': base64Encode(pdfBytes),
        },
      ],
      schema: _transactionsJsonSchema,
    );
    return _mapDrafts(jsonMap, TxnSource.statement);
  }

  Future<String> generateProactiveTip(
    Map<String, dynamic> anonymizedAggregates,
  ) async {
    final jsonMap = await _callInteractionsJson(
      systemInstruction:
          'You are FinTrack AI Copilot, a sharp, encouraging personal financial coach. '
          'Given the user\'s anonymized monthly cashflow and leak summary, produce one ultra-specific, non-generic daily tip under 155 characters.',
      inputBlocks: [
        {
          'type': 'text',
          'text': jsonEncode(anonymizedAggregates),
        },
      ],
      schema: {
        'type': 'object',
        'properties': {
          'tip': {'type': 'string'},
        },
        'required': ['tip'],
      },
    );
    return (jsonMap['tip'] as String?)?.trim() ??
        'Keep tracking every UPI spend to stay ahead of your daily burn rate!';
  }

  Future<MonthlyAuditReport> generateMonthlyAudit(
    Map<String, dynamic> anonymizedAggregates,
  ) async {
    final jsonMap = await _callInteractionsJson(
      systemInstruction:
          'You are FinTrack AI Financial Auditor. Analyze the user\'s monthly credits, debits, category breakdown, and money leakage signals. '
          'Identify where money leaked (micro-spends, subscription creep, peak days) and provide 3 realistic, high-impact recommendations with estimated monthly Rupee savings.',
      inputBlocks: [
        {
          'type': 'text',
          'text': jsonEncode(anonymizedAggregates),
        },
      ],
      schema: _auditJsonSchema,
    );

    final leaks = (jsonMap['leak_insights'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final recs = (jsonMap['recommendations'] as List? ?? const []).map((raw) {
      final map = raw as Map<String, dynamic>;
      final inr = (map['estimated_monthly_saving_inr'] as num?)?.toDouble() ?? 0;
      return AuditRecommendation(
        title: (map['title'] as String?) ?? 'Optimize spend',
        action: (map['action'] as String?) ?? '',
        estimatedMonthlySavingPaise: (inr * 100).round(),
      );
    }).toList();

    return MonthlyAuditReport(
      headline: (jsonMap['headline'] as String?) ?? 'Monthly Spend Audit',
      cashflowSummary: (jsonMap['cashflow_summary'] as String?) ?? '',
      leakInsights: leaks,
      recommendations: recs,
      isAiGenerated: true,
    );
  }

  Future<DailySummaryReport> generateDailySpendSummary({
    required int spentTodayPaise,
    required int creditedTodayPaise,
    required int dailyLimitPaise,
    required List<TransactionModel> todayTransactions,
    required Map<String, String> categoryNames,
  }) async {
    final now = DateTime.now();
    final isOverLimit = spentTodayPaise > dailyLimitPaise;
    final catTotals = <String, int>{};
    TransactionModel? topSpend;

    for (final txn in todayTransactions) {
      if (txn.type == TxnType.debit) {
        catTotals[txn.categoryId] =
            (catTotals[txn.categoryId] ?? 0) + txn.amountPaise;
        if (topSpend == null || txn.amountPaise > topSpend.amountPaise) {
          topSpend = txn;
        }
      }
    }

    // Try Gemini AI first if configured
    try {
      final apiKey = await secureStore.getGeminiApiKey();
      if (apiKey != null && apiKey.trim().isNotEmpty) {
        final payload = {
          'date': now.toIso8601String().split('T').first,
          'daily_spend_limit_inr': dailyLimitPaise / 100.0,
          'total_spent_today_inr': spentTodayPaise / 100.0,
          'total_credited_today_inr': creditedTodayPaise / 100.0,
          'is_over_limit': isOverLimit,
          'top_expense': topSpend != null
              ? {
                  'title': topSpend.title,
                  'amount_inr': topSpend.amountPaise / 100.0,
                  'category': categoryNames[topSpend.categoryId] ?? 'Other',
                }
              : null,
          'category_breakdown_inr': catTotals.map(
            (k, v) => MapEntry(categoryNames[k] ?? k, v / 100.0),
          ),
          'transaction_count': todayTransactions.length,
        };

        final jsonMap = await _callInteractionsJson(
          systemInstruction:
              'You are FinTrack AI End-of-Day Auditor. Analyze the user\'s daily expenses vs their daily spend limit. '
              'Provide an encouraging yet sharp headline (under 60 chars), a 2-sentence summary analysis of where their money went, and 1 actionable takeaway rule for tomorrow. '
              'Return pure JSON strictly matching the schema.',
          inputBlocks: [
            {
              'type': 'text',
              'text': jsonEncode(payload),
            },
          ],
          schema: _dailySummaryJsonSchema,
        );

        final headline = (jsonMap['headline'] as String?)?.trim();
        final analysis = (jsonMap['analysis'] as String?)?.trim();
        final topTitle = (jsonMap['top_spend_title'] as String?)?.trim() ??
            (topSpend?.title ?? 'None');
        final topInr =
            (jsonMap['top_spend_amount_inr'] as num?)?.toDouble() ??
                ((topSpend?.amountPaise ?? 0) / 100.0);
        final takeaway =
            (jsonMap['takeaway_for_tomorrow'] as String?)?.trim();

        if (headline != null && analysis != null) {
          return DailySummaryReport(
            date: now,
            spentTodayPaise: spentTodayPaise,
            creditedTodayPaise: creditedTodayPaise,
            dailyLimitPaise: dailyLimitPaise,
            isOverLimit: isOverLimit,
            headline: headline,
            analysis: analysis,
            topSpendTitle: topTitle,
            topSpendPaise: (topInr * 100).round(),
            takeawayForTomorrow: takeaway ??
                'Keep logging micro-spends to maintain zero unaccounted cashflow.',
            categoryBreakdownPaise: catTotals,
            isAiGenerated: true,
          );
        }
      }
    } catch (_) {}

    // Deterministic High-Quality Fallback (offline or without API key)
    final topSpendTitle = topSpend?.title ?? 'None';
    final topSpendPaise = topSpend?.amountPaise ?? 0;

    String headline;
    String analysis;
    String takeaway;

    final spentRupees = (spentTodayPaise / 100.0).toStringAsFixed(0);
    final limitRupees = (dailyLimitPaise / 100.0).toStringAsFixed(0);

    if (spentTodayPaise == 0) {
      headline = 'Zero Spend Day! ₹0 spent 🎉';
      analysis =
          'You recorded ₹0 in debits today, preserving 100% of your ₹$limitRupees daily allowance.';
      takeaway =
          'Great discipline! Make sure you didn\'t miss logging any cash or UPI payments.';
    } else if (isOverLimit) {
      final overPaise = spentTodayPaise - dailyLimitPaise;
      final overRupees = (overPaise / 100.0).toStringAsFixed(0);
      headline = 'Over Daily Limit by ₹$overRupees ⚠️';
      analysis =
          'You spent ₹$spentRupees today across ${todayTransactions.where((t) => t.type == TxnType.debit).length} debit(s), exceeding your ₹$limitRupees daily target. The largest spend was $topSpendTitle (₹${(topSpendPaise / 100).toStringAsFixed(0)}).';
      takeaway =
          'Aim for a low-spend day tomorrow to rebalance your dynamic monthly burn rate.';
    } else {
      final savedPaise = dailyLimitPaise - spentTodayPaise;
      final savedRupees = (savedPaise / 100.0).toStringAsFixed(0);
      headline = 'Disciplined Day: ₹$savedRupees under limit 🛡️';
      analysis =
          'You stayed within your daily spend limit (₹$spentRupees spent of ₹$limitRupees). You successfully saved ₹$savedRupees today.';
      takeaway =
          'Consistent days like this compound into significant monthly savings.';
    }

    return DailySummaryReport(
      date: now,
      spentTodayPaise: spentTodayPaise,
      creditedTodayPaise: creditedTodayPaise,
      dailyLimitPaise: dailyLimitPaise,
      isOverLimit: isOverLimit,
      headline: headline,
      analysis: analysis,
      topSpendTitle: topSpendTitle,
      topSpendPaise: topSpendPaise,
      takeawayForTomorrow: takeaway,
      categoryBreakdownPaise: catTotals,
      isAiGenerated: false,
    );
  }

  List<ParsedTransactionDraft> _mapDrafts(
    Map<String, dynamic> jsonMap,
    TxnSource source,
  ) {
    final list = jsonMap['transactions'] as List? ?? const [];
    final now = DateTime.now();
    final drafts = <ParsedTransactionDraft>[];

    for (final raw in list) {
      if (raw is! Map) continue;
      final amountNum = (raw['amount'] as num?)?.toDouble() ?? 0.0;
      if (amountNum <= 0) continue;

      final amountPaise = (amountNum * 100).round();
      final type = TxnType.fromString(raw['type'] as String?);
      final title = (raw['title'] as String?)?.trim() ?? 'Transaction';
      final payee = (raw['payer_or_payee'] as String?)?.trim() ?? title;
      final categoryId = (raw['category_id'] as String?) ??
          (type == TxnType.credit ? 'cat_income_salary' : 'cat_other');
      final paymentMode = PaymentMode.fromString(
        raw['payment_mode'] as String?,
      );
      final referenceId = (raw['reference_id'] as String?)?.trim();
      final splitFriends = (raw['split_friends'] as List? ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();

      DateTime occurredAt = now;
      final dateStr = raw['date'] as String?;
      final timeStr = raw['time'] as String?;
      if (dateStr != null && dateStr.isNotEmpty) {
        final parsedDate = DateTime.tryParse(dateStr);
        if (parsedDate != null) {
          var hour = now.hour;
          var minute = now.minute;
          if (timeStr != null && timeStr.contains(':')) {
            final parts = timeStr.split(':');
            hour = int.tryParse(parts[0]) ?? hour;
            minute = int.tryParse(parts[1]) ?? minute;
          }
          occurredAt = DateTime(
            parsedDate.year,
            parsedDate.month,
            parsedDate.day,
            hour,
            minute,
          );
        }
      }

      drafts.add(
        ParsedTransactionDraft(
          title: title,
          amountPaise: amountPaise,
          type: type,
          currency: (raw['currency'] as String?) ?? 'INR',
          categoryId: categoryId,
          occurredAt: occurredAt,
          paymentMode: paymentMode,
          counterparty: payee,
          referenceId:
              (referenceId == null || referenceId.isEmpty) ? null : referenceId,
          splitFriends: splitFriends,
          source: source,
        ),
      );
    }

    return drafts;
  }
}

