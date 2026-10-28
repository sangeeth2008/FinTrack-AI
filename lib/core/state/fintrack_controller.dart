import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../features/backup/domain/encrypted_backup_service.dart';
import '../../features/budgets/domain/burn_rate_engine.dart';
import '../../features/capture/domain/sms_regex_parser.dart';
import '../../features/copilot/domain/leak_detector.dart';
import '../../features/splits/domain/split_calculator.dart';
import '../db/app_database.dart';
import '../db/models.dart';
import '../gemini/gemini_service.dart';
import '../native/reminder_service.dart';
import '../native/share_intent_bridge.dart';
import '../security/lock_controller.dart';

class FinTrackState {
  final bool isReady;
  final ThemeMode themeMode;
  final List<AccountModel> accounts;
  final List<CategoryModel> categories;
  final List<TransactionModel> transactions;
  final List<SplitShareModel> splitShares;
  final List<ImpulseItemModel> impulseItems;
  final CashflowAndBurnSummary cashflow;
  final LeakMetrics leaks;
  final String dailyOpeningTip;
  final bool isTipAiGenerated;
  final MonthlyAuditReport? auditReport;
  final bool isAuditLoading;
  final DailySummaryReport? dailySummary;
  final bool isDailySummaryLoading;
  final bool hasGeminiKey;
  final int hourlyRatePaise;
  final int dailySpendLimitPaise;
  final String upiVpa;
  final String upiName;
  final String? upiQrImagePath;
  final bool autoSmsEnabled;
  final bool smsPermissionGranted;
  final int lastAutoSmsImportedCount;
  final bool expenseReminderEnabled;
  final int expenseReminderIntervalHours;
  final bool nightReminderEnabled;

  const FinTrackState({
    required this.isReady,
    required this.themeMode,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.splitShares,
    required this.impulseItems,
    required this.cashflow,
    required this.leaks,
    required this.dailyOpeningTip,
    this.isTipAiGenerated = false,
    this.auditReport,
    this.isAuditLoading = false,
    this.dailySummary,
    this.isDailySummaryLoading = false,
    this.hasGeminiKey = false,
    this.hourlyRatePaise = 50000,
    this.dailySpendLimitPaise = 150000,
    this.upiVpa = '',
    this.upiName = 'Me',
    this.upiQrImagePath,
    this.autoSmsEnabled = true,
    this.smsPermissionGranted = false,
    this.lastAutoSmsImportedCount = 0,
    this.expenseReminderEnabled = true,
    this.expenseReminderIntervalHours = 3,
    this.nightReminderEnabled = true,
  });

  factory FinTrackState.initial() {
    const emptyCashflow = CashflowAndBurnSummary(
      totalBalancePaise: 0,
      monthlyCreditedPaise: 0,
      monthlyDebitedPaise: 0,
      netMonthlyCashflowPaise: 0,
      savingsRatePercent: 0,
      monthlyBudgetPaise: 2500000,
      safeDailyAllowancePaise: 80000,
      dailySpendLimitPaise: 150000,
      spentTodayPaise: 0,
      remainingTodayPaise: 80000,
      remainingDailyLimitPaise: 150000,
      daysRemainingInMonth: 30,
      monthlyBudgetProgress: 0,
      todayAllowanceProgress: 0,
      dailyLimitProgress: 0,
      isOverDailyLimit: false,
      spendByCategoryPaise: {},
    );
    const emptyLeaks = LeakMetrics(
      microSpendCount: 0,
      microSpendTotalPaise: 0,
      lateNightSpendCount: 0,
      lateNightTotalPaise: 0,
      subscriptionTotalPaise: 0,
      peakSpendWeekday: 'Saturday',
      peakWeekdayTotalPaise: 0,
      topMerchantsBySpend: [],
    );

    return const FinTrackState(
      isReady: false,
      themeMode: ThemeMode.dark,
      accounts: AppDatabase.defaultAccounts,
      categories: AppDatabase.defaultCategories,
      transactions: [],
      splitShares: [],
      impulseItems: [],
      cashflow: emptyCashflow,
      leaks: emptyLeaks,
      dailyOpeningTip:
          'Unlocking encrypted SQLCipher vault… Your financial data stays 100% on-device.',
    );
  }

  CategoryModel categoryById(String id) {
    return categories.firstWhere(
      (c) => c.id == id,
      orElse: () => AppDatabase.defaultCategories.first,
    );
  }

  AccountModel accountById(String id) {
    return accounts.firstWhere(
      (a) => a.id == id,
      orElse: () => AppDatabase.defaultAccounts.first,
    );
  }

  Map<String, String> get categoryNamesMap => {
        for (final c in categories) c.id: c.name,
      };

  FinTrackState copyWith({
    bool? isReady,
    ThemeMode? themeMode,
    List<AccountModel>? accounts,
    List<CategoryModel>? categories,
    List<TransactionModel>? transactions,
    List<SplitShareModel>? splitShares,
    List<ImpulseItemModel>? impulseItems,
    CashflowAndBurnSummary? cashflow,
    LeakMetrics? leaks,
    String? dailyOpeningTip,
    bool? isTipAiGenerated,
    MonthlyAuditReport? auditReport,
    bool? isAuditLoading,
    DailySummaryReport? dailySummary,
    bool? isDailySummaryLoading,
    bool? hasGeminiKey,
    int? hourlyRatePaise,
    int? dailySpendLimitPaise,
    String? upiVpa,
    String? upiName,
    String? upiQrImagePath,
    bool clearUpiQrImagePath = false,
    bool? autoSmsEnabled,
    bool? smsPermissionGranted,
    int? lastAutoSmsImportedCount,
    bool? expenseReminderEnabled,
    int? expenseReminderIntervalHours,
    bool? nightReminderEnabled,
  }) {
    return FinTrackState(
      isReady: isReady ?? this.isReady,
      themeMode: themeMode ?? this.themeMode,
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      transactions: transactions ?? this.transactions,
      splitShares: splitShares ?? this.splitShares,
      impulseItems: impulseItems ?? this.impulseItems,
      cashflow: cashflow ?? this.cashflow,
      leaks: leaks ?? this.leaks,
      dailyOpeningTip: dailyOpeningTip ?? this.dailyOpeningTip,
      isTipAiGenerated: isTipAiGenerated ?? this.isTipAiGenerated,
      auditReport: auditReport ?? this.auditReport,
      isAuditLoading: isAuditLoading ?? this.isAuditLoading,
      dailySummary: dailySummary ?? this.dailySummary,
      isDailySummaryLoading:
          isDailySummaryLoading ?? this.isDailySummaryLoading,
      hasGeminiKey: hasGeminiKey ?? this.hasGeminiKey,
      hourlyRatePaise: hourlyRatePaise ?? this.hourlyRatePaise,
      dailySpendLimitPaise: dailySpendLimitPaise ?? this.dailySpendLimitPaise,
      upiVpa: upiVpa ?? this.upiVpa,
      upiName: upiName ?? this.upiName,
      upiQrImagePath: clearUpiQrImagePath
          ? null
          : (upiQrImagePath ?? this.upiQrImagePath),
      autoSmsEnabled: autoSmsEnabled ?? this.autoSmsEnabled,
      smsPermissionGranted: smsPermissionGranted ?? this.smsPermissionGranted,
      lastAutoSmsImportedCount:
          lastAutoSmsImportedCount ?? this.lastAutoSmsImportedCount,
      expenseReminderEnabled:
          expenseReminderEnabled ?? this.expenseReminderEnabled,
      expenseReminderIntervalHours:
          expenseReminderIntervalHours ?? this.expenseReminderIntervalHours,
      nightReminderEnabled: nightReminderEnabled ?? this.nightReminderEnabled,
    );
  }
}

final geminiServiceProvider = Provider<GeminiService>((ref) {
  final store = ref.watch(secureStoreProvider);
  return GeminiService(secureStore: store);
});

final nativeBridgeProvider = Provider<NativeBridgeService>((ref) {
  final bridge = NativeBridgeService();
  ref.onDispose(bridge.dispose);
  return bridge;
});

final encryptedBackupServiceProvider = Provider<EncryptedBackupService>((ref) {
  return EncryptedBackupService();
});

final finTrackControllerProvider =
    NotifierProvider<FinTrackController, FinTrackState>(
  FinTrackController.new,
);

class FinTrackController extends Notifier<FinTrackState> {
  static const _uuid = Uuid();
  AppDatabase? _db;
  StreamSubscription<NativeSmsMessage>? _smsSub;

  @override
  FinTrackState build() {
    ref.onDispose(() {
      _smsSub?.cancel();
    });
    _bootstrap();
    return FinTrackState.initial();
  }

  Future<void> attachTestDatabase(AppDatabase db) async {
    _db = db;
    await _reloadFromDb(refreshAiTip: false);
  }

  Future<void> _bootstrap() async {
    final store = ref.read(secureStoreProvider);
    final bridge = ref.read(nativeBridgeProvider);
    final rawTheme = await store.getThemeMode();
    final themeMode = switch (rawTheme) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    final apiKey = await store.getGeminiApiKey();
    final hourlyRate = await store.getHourlyRatePaise();
    final dailyLimit = await store.getDailySpendLimitPaise();
    final upiVpa = await store.getUpiVpa();
    final upiName = await store.getUpiName();
    final qrPath = await store.getUpiQrImagePath();
    final autoSms = await store.getAutoSmsEnabled();
    final hasSmsPerm = await bridge.hasSmsPermission();
    final reminderEnabled = await store.getExpenseReminderEnabled();
    final intervalHours = await store.getExpenseReminderIntervalHours();
    final nightEnabled = await store.getNightReminderEnabled();

    DailySummaryReport? initialDailySummary;
    final cachedSummaryJson = await store.getLastDailySummaryJson();
    if (cachedSummaryJson != null && cachedSummaryJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedSummaryJson);
        if (decoded is Map<String, dynamic>) {
          final summary = DailySummaryReport.fromJson(decoded);
          final now = DateTime.now();
          if (summary.date.year == now.year &&
              summary.date.month == now.month &&
              summary.date.day == now.day) {
            initialDailySummary = summary;
          }
        }
      } catch (_) {}
    }

    state = state.copyWith(
      themeMode: themeMode,
      hasGeminiKey: apiKey != null && apiKey.isNotEmpty,
      hourlyRatePaise: hourlyRate,
      dailySpendLimitPaise: dailyLimit,
      upiVpa: upiVpa,
      upiName: upiName,
      upiQrImagePath: qrPath,
      autoSmsEnabled: autoSms,
      smsPermissionGranted: hasSmsPerm,
      expenseReminderEnabled: reminderEnabled,
      expenseReminderIntervalHours: intervalHours,
      nightReminderEnabled: nightEnabled,
      dailySummary: initialDailySummary,
    );

    if (reminderEnabled) {
      await ReminderService.scheduleExpenseReminders(
        intervalHours: intervalHours,
        nightReminder: nightEnabled,
      );
    }

    _smsSub?.cancel();
    _smsSub = bridge.incomingSmsStream.listen((msg) {
      if (state.autoSmsEnabled) {
        _handleIncomingNativeSms(msg);
      }
    });

    try {
      final dbPassword = await store.getOrCreateDatabaseKey();
      _db ??= await AppDatabase.openEncrypted(password: dbPassword);
      await _reloadFromDb(refreshAiTip: true);
      if (autoSms && hasSmsPerm) {
        await syncBankSmsInbox(requestPermissionIfNeeded: false);
      }
    } catch (_) {
      state = state.copyWith(isReady: true);
    }
  }

  Future<void> _reloadFromDb({bool refreshAiTip = false}) async {
    final db = _db;
    if (db == null) return;

    final store = ref.read(secureStoreProvider);
    final monthlyBudgetPaise = await store.getMonthlyBudgetPaise();
    final dailySpendLimitPaise = await store.getDailySpendLimitPaise();
    final accounts = await db.getAccounts();
    final categories = await db.getCategories();
    final transactions = await db.getAllTransactions();
    final splits = await db.getSplitShares();
    final impulse = await db.getImpulseItems();

    final cashflow = BurnRateEngine.compute(
      accounts: accounts,
      transactions: transactions,
      monthlyBudgetPaise: monthlyBudgetPaise,
      dailySpendLimitPaise: dailySpendLimitPaise,
    );
    final leaks = LeakDetector.analyzeMonth(transactions);
    final localTip = LeakDetector.generateLocalOpeningTip(
      cashflow: cashflow,
      leaks: leaks,
    );
    final catMap = {for (final c in categories) c.id: c.name};
    final localAudit = LeakDetector.generateLocalAuditReport(
      cashflow: cashflow,
      leaks: leaks,
      categoryNamesById: catMap,
    );

    state = state.copyWith(
      isReady: true,
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      splitShares: splits,
      impulseItems: impulse,
      cashflow: cashflow,
      leaks: leaks,
      dailySpendLimitPaise: dailySpendLimitPaise,
      dailyOpeningTip: state.isTipAiGenerated ? state.dailyOpeningTip : localTip,
      auditReport: state.auditReport?.isAiGenerated == true
          ? state.auditReport
          : localAudit,
    );

    if (refreshAiTip && state.hasGeminiKey && transactions.isNotEmpty) {
      _refreshDailyTipFromGemini();
    }
  }

  Future<void> _refreshDailyTipFromGemini() async {
    try {
      final payload = LeakDetector.buildAnonymizedPayload(
        cashflow: state.cashflow,
        leaks: state.leaks,
        categoryNamesById: state.categoryNamesMap,
      );
      final tip = await ref
          .read(geminiServiceProvider)
          .generateProactiveTip(payload);
      if (tip.isNotEmpty) {
        state = state.copyWith(
          dailyOpeningTip: tip,
          isTipAiGenerated: true,
        );
      }
    } catch (_) {}
  }

  Future<void> generateMonthlyAiAudit() async {
    state = state.copyWith(isAuditLoading: true);
    try {
      final payload = LeakDetector.buildAnonymizedPayload(
        cashflow: state.cashflow,
        leaks: state.leaks,
        categoryNamesById: state.categoryNamesMap,
      );
      if (state.hasGeminiKey) {
        final report = await ref
            .read(geminiServiceProvider)
            .generateMonthlyAudit(payload);
        state = state.copyWith(auditReport: report, isAuditLoading: false);
      } else {
        final localReport = LeakDetector.generateLocalAuditReport(
          cashflow: state.cashflow,
          leaks: state.leaks,
          categoryNamesById: state.categoryNamesMap,
        );
        state = state.copyWith(auditReport: localReport, isAuditLoading: false);
      }
    } catch (_) {
      final fallback = LeakDetector.generateLocalAuditReport(
        cashflow: state.cashflow,
        leaks: state.leaks,
        categoryNamesById: state.categoryNamesMap,
      );
      state = state.copyWith(auditReport: fallback, isAuditLoading: false);
    }
  }

  Future<void> addTransaction({
    required int amountPaise,
    required TxnType type,
    required String title,
    required String counterparty,
    required String categoryId,
    required String accountId,
    required PaymentMode paymentMode,
    DateTime? occurredAt,
    String? referenceId,
    TxnSource source = TxnSource.manual,
    List<String> tags = const [],
    String? note,
    List<ComputedSplitShare> friendSplits = const [],
  }) async {
    final db = _db;
    if (db == null) return;

    final when = occurredAt ?? DateTime.now();
    final txnId = _uuid.v4();
    final hash = TransactionModel.computeDedupeHash(
      amountPaise: amountPaise,
      type: type,
      occurredAt: when,
      counterparty: counterparty.isEmpty ? title : counterparty,
      referenceId: referenceId,
    );

    final txn = TransactionModel(
      id: txnId,
      amountPaise: amountPaise,
      type: type,
      title: title.trim().isEmpty ? counterparty : title.trim(),
      counterparty: counterparty.trim().isEmpty ? title.trim() : counterparty.trim(),
      categoryId: categoryId,
      accountId: accountId,
      occurredAt: when,
      paymentMode: paymentMode,
      referenceId: referenceId,
      source: source,
      dedupeHash: hash,
      tags: tags,
      note: note,
    );

    await db.upsertTransaction(txn);

    for (final share in friendSplits) {
      if (share.isUser || share.sharePaise <= 0) continue;
      await db.insertSplitShare(
        SplitShareModel(
          id: _uuid.v4(),
          transactionId: txnId,
          friendName: share.name,
          friendUpiVpa: share.upiVpa,
          sharePaise: share.sharePaise,
          createdAt: when,
        ),
      );
    }

    await _reloadFromDb();
  }

  Future<int> importParsedDrafts(
    List<ParsedTransactionDraft> drafts, {
    String? accountId,
  }) async {
    final db = _db;
    if (db == null || drafts.isEmpty) return 0;

    final targetAccount = accountId ?? state.accounts.first.id;
    var importedCount = 0;

    for (final draft in drafts) {
      final learnedCat = await db.lookupLearnedCategory(draft.counterparty);
      final txnId = _uuid.v4();
      final model = draft
          .toTransactionModel(id: txnId, accountId: targetAccount)
          .copyWith(categoryId: learnedCat ?? draft.categoryId);

      final isDupe = await db.existsByDedupeHashOrRef(
        dedupeHash: model.dedupeHash,
        referenceId: model.referenceId,
      );
      if (isDupe) continue;

      await db.upsertTransaction(model);
      importedCount++;

      if (draft.splitFriends.isNotEmpty && draft.type == TxnType.debit) {
        final computed = SplitCalculator.calculate(
          totalPaise: draft.amountPaise,
          mode: SplitMode.equal,
          friends: draft.splitFriends
              .map((name) => FriendSplitInput(name: name))
              .toList(),
        );
        for (final share in computed) {
          if (share.isUser || share.sharePaise <= 0) continue;
          await db.insertSplitShare(
            SplitShareModel(
              id: _uuid.v4(),
              transactionId: txnId,
              friendName: share.name,
              sharePaise: share.sharePaise,
              createdAt: draft.occurredAt,
            ),
          );
        }
      }
    }

    await _reloadFromDb(refreshAiTip: true);
    return importedCount;
  }

  Future<void> deleteTransaction(String id) async {
    final db = _db;
    if (db == null) return;
    await db.deleteTransaction(id);
    await _reloadFromDb();
  }

  /// Marks a friend's split share as settled AND logs an incoming Credit
  /// transaction to the user's account so their balance increases accurately.
  Future<void> settleSplitShare(
    SplitShareModel share, {
    String? accountId,
  }) async {
    final db = _db;
    if (db == null || share.isSettled) return;

    final now = DateTime.now();
    await db.markSplitSettled(share.id, now);

    final targetAccount = accountId ?? state.accounts.first.id;
    await addTransaction(
      amountPaise: share.sharePaise,
      type: TxnType.credit,
      title: 'Split Settled • ${share.friendName}',
      counterparty: share.friendName,
      categoryId: 'cat_income_refund',
      accountId: targetAccount,
      paymentMode: PaymentMode.upi,
      occurredAt: now,
      source: TxnSource.splitSettlement,
      note: 'Repayment for split expense',
    );
  }

  Future<void> addImpulseItem({
    required String title,
    required int pricePaise,
    required String categoryId,
    int coolOffHours = 24,
    String? reasonNote,
  }) async {
    final db = _db;
    if (db == null) return;
    final now = DateTime.now();
    final item = ImpulseItemModel(
      id: _uuid.v4(),
      title: title.trim(),
      pricePaise: pricePaise,
      categoryId: categoryId,
      createdAt: now,
      unlockAt: now.add(Duration(hours: coolOffHours)),
      reasonNote: reasonNote,
    );
    await db.upsertImpulseItem(item);
    await _reloadFromDb();
  }

  Future<void> resolveImpulseItem(
    ImpulseItemModel item, {
    required bool purchase,
  }) async {
    final db = _db;
    if (db == null) return;

    if (purchase) {
      await db.updateImpulseStatus(item.id, 'purchased');
      await addTransaction(
        amountPaise: item.pricePaise,
        type: TxnType.debit,
        title: item.title,
        counterparty: item.title,
        categoryId: item.categoryId,
        accountId: state.accounts.first.id,
        paymentMode: PaymentMode.upi,
        note: 'Purchased after cooling-off period',
      );
    } else {
      await db.updateImpulseStatus(item.id, 'skipped');
      await _reloadFromDb();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final store = ref.read(secureStoreProvider);
    final raw = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    await store.setThemeMode(raw);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> saveGeminiApiKey(String? apiKey) async {
    final store = ref.read(secureStoreProvider);
    await store.setGeminiApiKey(apiKey);
    final current = await store.getGeminiApiKey();
    state = state.copyWith(hasGeminiKey: current != null && current.isNotEmpty);
    if (state.hasGeminiKey) {
      _refreshDailyTipFromGemini();
    }
  }

  Future<void> updateMonthlyBudget(int budgetPaise) async {
    await ref.read(secureStoreProvider).setMonthlyBudgetPaise(budgetPaise);
    await _reloadFromDb();
  }

  Future<void> updateDailySpendLimit(int limitPaise) async {
    final clamped = limitPaise.clamp(10000, 10000000); // ₹100 min, ₹1,00,000 max
    await ref.read(secureStoreProvider).setDailySpendLimitPaise(clamped);
    state = state.copyWith(dailySpendLimitPaise: clamped);
    await _reloadFromDb();
    unawaited(refreshDailySummary());
  }

  Future<DailySummaryReport> refreshDailySummary({bool forceAi = false}) async {
    state = state.copyWith(isDailySummaryLoading: true);
    final now = DateTime.now();
    final todayTxns = state.transactions.where((t) {
      return t.occurredAt.year == now.year &&
          t.occurredAt.month == now.month &&
          t.occurredAt.day == now.day;
    }).toList();

    var spent = 0;
    var credited = 0;
    for (final t in todayTxns) {
      if (t.type == TxnType.debit) {
        spent += t.amountPaise;
      } else {
        credited += t.amountPaise;
      }
    }

    try {
      final summary = await ref
          .read(geminiServiceProvider)
          .generateDailySpendSummary(
            spentTodayPaise: spent,
            creditedTodayPaise: credited,
            dailyLimitPaise: state.dailySpendLimitPaise,
            todayTransactions: todayTxns,
            categoryNames: state.categoryNamesMap,
          );

      await ref
          .read(secureStoreProvider)
          .setLastDailySummaryJson(jsonEncode(summary.toJson()));

      state = state.copyWith(
        dailySummary: summary,
        isDailySummaryLoading: false,
      );
      return summary;
    } catch (_) {
      state = state.copyWith(isDailySummaryLoading: false);
      rethrow;
    }
  }

  Future<void> updateReminderSettings({
    bool? enabled,
    int? intervalHours,
    bool? nightReminder,
  }) async {
    final store = ref.read(secureStoreProvider);
    final newEnabled = enabled ?? state.expenseReminderEnabled;
    final newInterval = intervalHours ?? state.expenseReminderIntervalHours;
    final newNight = nightReminder ?? state.nightReminderEnabled;

    await store.setExpenseReminderEnabled(newEnabled);
    await store.setExpenseReminderIntervalHours(newInterval);
    await store.setNightReminderEnabled(newNight);

    if (newEnabled) {
      await ReminderService.scheduleExpenseReminders(
        intervalHours: newInterval,
        nightReminder: newNight,
      );
    } else {
      await ReminderService.cancelExpenseReminders();
    }

    state = state.copyWith(
      expenseReminderEnabled: newEnabled,
      expenseReminderIntervalHours: newInterval,
      nightReminderEnabled: newNight,
    );
  }

  Future<void> sendTestReminder() async {
    await ReminderService.requestNotificationPermission();
    await ReminderService.showTestReminder();
  }

  Future<void> updateAccountInitialBalance(
    String accountId,
    int initialBalancePaise,
  ) async {
    final db = _db;
    if (db == null) return;
    await db.updateAccountInitialBalance(accountId, initialBalancePaise);
    await _reloadFromDb();
  }

  Future<void> updatePreferences({
    int? hourlyRatePaise,
    String? upiVpa,
    String? upiName,
    String? upiQrImagePath,
    bool clearUpiQrImagePath = false,
  }) async {
    final store = ref.read(secureStoreProvider);
    if (hourlyRatePaise != null) {
      await store.setHourlyRatePaise(hourlyRatePaise);
    }
    if (upiVpa != null) {
      await store.setUpiVpa(upiVpa);
    }
    if (upiName != null) {
      await store.setUpiName(upiName);
    }
    if (clearUpiQrImagePath) {
      await store.setUpiQrImagePath(null);
    } else if (upiQrImagePath != null) {
      await store.setUpiQrImagePath(upiQrImagePath);
    }
    state = state.copyWith(
      hourlyRatePaise: hourlyRatePaise ?? state.hourlyRatePaise,
      upiVpa: upiVpa ?? state.upiVpa,
      upiName: upiName ?? state.upiName,
      upiQrImagePath: upiQrImagePath,
      clearUpiQrImagePath: clearUpiQrImagePath,
    );
  }

  Future<void> setAutoSmsEnabled(bool enabled) async {
    final store = ref.read(secureStoreProvider);
    final bridge = ref.read(nativeBridgeProvider);
    await store.setAutoSmsEnabled(enabled);
    bool hasPerm = state.smsPermissionGranted;
    if (enabled && !hasPerm) {
      hasPerm = await bridge.requestSmsPermission();
    }
    state = state.copyWith(
      autoSmsEnabled: enabled,
      smsPermissionGranted: hasPerm,
    );
    if (enabled && hasPerm) {
      await syncBankSmsInbox(requestPermissionIfNeeded: false);
    }
  }

  Future<void> _handleIncomingNativeSms(NativeSmsMessage msg) async {
    final drafts = SmsRegexParser.parseTextBlock(msg.body);
    if (drafts.isNotEmpty) {
      final adjusted = drafts
          .map(
            (d) => ParsedTransactionDraft(
              title: d.title,
              amountPaise: d.amountPaise,
              type: d.type,
              categoryId: d.categoryId,
              occurredAt: msg.date,
              paymentMode: d.paymentMode,
              counterparty: d.counterparty,
              referenceId: d.referenceId,
              splitFriends: d.splitFriends,
              source: TxnSource.sms,
            ),
          )
          .toList();
      final count = await importParsedDrafts(adjusted);
      if (count > 0) {
        state = state.copyWith(
          lastAutoSmsImportedCount: state.lastAutoSmsImportedCount + count,
        );
      }
      return;
    }

    // Fallback to Gemini AI if configured
    if (state.hasGeminiKey) {
      try {
        final aiDrafts = await ref
            .read(geminiServiceProvider)
            .parseTextTransactions(msg.body, source: TxnSource.sms);
        if (aiDrafts.isNotEmpty) {
          final count = await importParsedDrafts(aiDrafts);
          if (count > 0) {
            state = state.copyWith(
              lastAutoSmsImportedCount: state.lastAutoSmsImportedCount + count,
            );
          }
        }
      } catch (_) {}
    }
  }

  Future<int> syncBankSmsInbox({bool requestPermissionIfNeeded = true}) async {
    final bridge = ref.read(nativeBridgeProvider);
    final store = ref.read(secureStoreProvider);

    bool hasPerm = await bridge.hasSmsPermission();
    if (!hasPerm && requestPermissionIfNeeded) {
      hasPerm = await bridge.requestSmsPermission();
    }
    state = state.copyWith(smsPermissionGranted: hasPerm);
    if (!hasPerm) return 0;

    final sinceMs = await store.getLastSmsSyncEpochMs();
    final messages = await bridge.readRecentBankSms(
      sinceEpochMs: sinceMs,
      limit: 100,
    );

    final allDrafts = <ParsedTransactionDraft>[];
    int newestEpoch = sinceMs;

    // Play-Protect-safe Smart Clipboard Bank SMS Auto-Detection
    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final clipText = clipData?.text?.trim() ?? '';
      if (clipText.isNotEmpty) {
        final clipParsed = SmsRegexParser.parseTextBlock(clipText);
        allDrafts.addAll(clipParsed);
      }
    } catch (_) {}

    for (final msg in messages) {
      final epoch = msg.date.millisecondsSinceEpoch;
      if (epoch > newestEpoch) newestEpoch = epoch;

      final parsed = SmsRegexParser.parseTextBlock(msg.body);
      for (final d in parsed) {
        allDrafts.add(
          ParsedTransactionDraft(
            title: d.title,
            amountPaise: d.amountPaise,
            type: d.type,
            categoryId: d.categoryId,
            occurredAt: msg.date,
            paymentMode: d.paymentMode,
            counterparty: d.counterparty,
            referenceId: d.referenceId,
            splitFriends: d.splitFriends,
            source: TxnSource.sms,
          ),
        );
      }
    }

    int imported = 0;
    if (allDrafts.isNotEmpty) {
      imported = await importParsedDrafts(allDrafts);
    }

    if (newestEpoch > sinceMs) {
      await store.setLastSmsSyncEpochMs(newestEpoch);
    }
    if (imported > 0) {
      state = state.copyWith(
        lastAutoSmsImportedCount: state.lastAutoSmsImportedCount + imported,
      );
    }
    return imported;
  }

  Future<String> exportEncryptedBackup(String passphrase) async {
    final db = _db;
    if (db == null) throw StateError('Database not ready');
    final snapshot = await db.exportSnapshot();
    return ref
        .read(encryptedBackupServiceProvider)
        .encryptSnapshotToJson(snapshot: snapshot, passphrase: passphrase);
  }

  Future<void> restoreEncryptedBackup({
    required String encryptedJson,
    required String passphrase,
  }) async {
    final db = _db;
    if (db == null) throw StateError('Database not ready');
    final snapshot = await ref
        .read(encryptedBackupServiceProvider)
        .decryptJsonToSnapshot(
          encryptedEnvelopeJson: encryptedJson,
          passphrase: passphrase,
        );
    await db.restoreSnapshot(snapshot);
    await _reloadFromDb(refreshAiTip: true);
  }
}

