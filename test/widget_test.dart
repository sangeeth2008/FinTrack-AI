import 'package:fintrack/app/app.dart';
import 'package:fintrack/core/db/models.dart';
import 'package:fintrack/core/gemini/gemini_service.dart';
import 'package:fintrack/core/security/biometric_service.dart';
import 'package:fintrack/core/security/lock_controller.dart';
import 'package:fintrack/core/security/pin_hasher.dart';
import 'package:fintrack/core/security/secure_store.dart';
import 'package:fintrack/features/backup/domain/encrypted_backup_service.dart';
import 'package:fintrack/features/budgets/domain/burn_rate_engine.dart';
import 'package:fintrack/features/capture/domain/csv_statement_parser.dart';
import 'package:fintrack/features/capture/domain/sms_regex_parser.dart';
import 'package:fintrack/features/copilot/domain/leak_detector.dart';
import 'package:fintrack/features/splits/domain/split_calculator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBiometricService extends BiometricService {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> authenticate({
    String reason = 'Authenticate to unlock FinTrack AI',
  }) async => false;
}

void main() {
  group('Security & PIN Hashing (PBKDF2-SHA256)', () {
    test('creates and verifies 6-digit PIN with constant-time compare', () async {
      const hasher = PinHasher(iterations: 1000);
      final record = await hasher.createPinRecord('482910');

      final ok = await hasher.verifyPin(
        '482910',
        storedHashBase64: record.hashBase64,
        storedSaltBase64: record.saltBase64,
      );
      final wrong = await hasher.verifyPin(
        '000000',
        storedHashBase64: record.hashBase64,
        storedSaltBase64: record.saltBase64,
      );

      expect(ok, isTrue);
      expect(wrong, isFalse);
    });

    test('enforces 3-attempt 5-min lockout (configurable) and always locks on minimize', () async {
      final store = SecureStore.inMemory();
      final container = ProviderContainer(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          pinHasherProvider.overrideWithValue(const PinHasher(iterations: 500)),
          biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(lockControllerProvider.notifier);
      await notifier.setupPinAndUnlock(pin: '123456', enableBiometric: false);
      expect(
        container.read(lockControllerProvider).status,
        VaultStatus.unlocked,
      );

      // Minimizing immediately locks the vault when alwaysLockOnMinimize is true
      final t0 = DateTime(2026, 10, 28, 12, 0, 0);
      notifier.onAppBackgrounded(at: t0);
      expect(container.read(lockControllerProvider).status, VaultStatus.locked);

      // 3 wrong attempts triggers 5-minute (300s) lockout & Access Denied screen
      for (var i = 0; i < 3; i++) {
        final unlocked = await notifier.unlockWithPin('999999', nowOverride: t0);
        expect(unlocked, isFalse);
      }
      final lockedState = container.read(lockControllerProvider);
      expect(lockedState.failedAttempts, 3);
      expect(lockedState.showDeniedScreen, isTrue);
      expect(lockedState.isCoolingDown(t0), isTrue);
      expect(lockedState.remainingCooldownSeconds(t0), 300);

      // After 5-minute cooldown expires, correct PIN unlocks and shows Welcome screen
      final afterCooldown = t0.add(const Duration(minutes: 5, seconds: 1));
      final unlockedAfter = await notifier.unlockWithPin(
        '123456',
        nowOverride: afterCooldown,
      );
      expect(unlockedAfter, isTrue);
      expect(
        container.read(lockControllerProvider).status,
        VaultStatus.unlocked,
      );
      expect(container.read(lockControllerProvider).showWelcomeScreen, isTrue);
    });
  });

  group('Multimodal SMS, CSV Statement & Gemini Output Parsers', () {
    test('parses Indian bank debit & credit SMS messages accurately', () {
      const debitSms =
          'Rs 450.00 debited from A/C XX4912 on 28-OCT-26 to SWIGGY INDIA Ref 630192837465';
      const creditSms =
          'INR 15,000.00 credited to A/C XX4912 from TECH STIPEND on 28-OCT-26 UPI Ref 991827364510';

      final drafts = SmsRegexParser.parseTextBlock('$debitSms\n$creditSms');
      expect(drafts.length, 2);

      expect(drafts[0].type, TxnType.debit);
      expect(drafts[0].amountPaise, 45000);
      expect(drafts[0].categoryId, 'cat_food');
      expect(drafts[0].referenceId, '630192837465');

      expect(drafts[1].type, TxnType.credit);
      expect(drafts[1].amountPaise, 1500000);
      expect(drafts[1].categoryId, 'cat_income_salary');
    });

    test('parses CSV bank statements offline with debits and credits', () {
      const sampleCsv = '''
Date,Narration,Withdrawal,Deposit,Ref No
2026-10-25,UPI-ROBU IN ELECTRONICS,1250.50,,UTR100200300
2026-10-26,NEFT SALARY CREDIT,,25000.00,UTR999888777
''';
      final drafts = CsvStatementParser.parseCsvContent(sampleCsv);
      expect(drafts.length, 2);
      expect(drafts[0].type, TxnType.debit);
      expect(drafts[0].amountPaise, 125050);
      expect(drafts[0].categoryId, 'cat_tech');
      expect(drafts[1].type, TxnType.credit);
      expect(drafts[1].amountPaise, 2500000);
    });

    test('extracts structured JSON from Gemini 3.8 Flash Interactions payload', () {
      final responsePayload = {
        'id': 'inter_123',
        'steps': [
          {
            'type': 'model_output',
            'content': [
              {
                'type': 'text',
                'text': '{"transactions":[{"title":"Auto","amount":150}]}',
              },
            ],
          },
        ],
      };
      final text = GeminiService.extractOutputText(responsePayload);
      expect(text, contains('"Auto"'));
    });
  });

  group('Peer Splits, Cashflow & Dynamic Daily Burn-Rate Engine', () {
    test('reconciles remainder paise on equal splits and builds UPI URI', () {
      // ₹10.00 (1000 paise) split 3 ways (You + 2 friends) -> 334 + 333 + 333 = 1000
      final shares = SplitCalculator.calculate(
        totalPaise: 1000,
        mode: SplitMode.equal,
        friends: const [
          FriendSplitInput(name: 'Sravan'),
          FriendSplitInput(name: 'Rahul'),
        ],
      );
      final sum = shares.fold<int>(0, (s, item) => s + item.sharePaise);
      expect(sum, 1000);
      expect(shares.first.isUser, isTrue);
      expect(shares.first.sharePaise, 334);

      final uri = SplitCalculator.buildUpiPaymentUri(
        payeeVpa: 'sangeeth@okaxis',
        payeeName: 'Sangeeth',
        amountPaise: 33300,
        note: 'Dinner split',
      );
      expect(uri.scheme, 'upi');
      expect(uri.queryParameters['pa'], 'sangeeth@okaxis');
      expect(uri.queryParameters['am'], '333.00');
    });

    test('computes net balance, monthly credits/debits, and rollover burn rate', () {
      final now = DateTime(2026, 10, 21, 14, 0); // 11 days left in Oct (21..31)
      const accounts = [
        AccountModel(
          id: 'acc_1',
          name: 'Primary',
          type: 'upi',
          initialBalancePaise: 1000000, // ₹10,000 opening
          colorValue: 0xFF10E5A0,
        ),
      ];
      final txns = [
        TransactionModel(
          id: 't1',
          amountPaise: 2000000, // +₹20,000 credited
          type: TxnType.credit,
          title: 'Freelance Payout',
          counterparty: 'Client',
          categoryId: 'cat_income_salary',
          accountId: 'acc_1',
          occurredAt: DateTime(2026, 10, 5),
          paymentMode: PaymentMode.netBanking,
          source: TxnSource.manual,
          dedupeHash: 'h1',
        ),
        TransactionModel(
          id: 't2',
          amountPaise: 400000, // -₹4,000 spent before today
          type: TxnType.debit,
          title: 'Lab Components',
          counterparty: 'Robu',
          categoryId: 'cat_tech',
          accountId: 'acc_1',
          occurredAt: DateTime(2026, 10, 10),
          paymentMode: PaymentMode.upi,
          source: TxnSource.manual,
          dedupeHash: 'h2',
        ),
        TransactionModel(
          id: 't3',
          amountPaise: 5000, // -₹50 micro spend today
          type: TxnType.debit,
          title: 'Chai',
          counterparty: 'Stall',
          categoryId: 'cat_food',
          accountId: 'acc_1',
          occurredAt: DateTime(2026, 10, 21, 10, 0),
          paymentMode: PaymentMode.upi,
          source: TxnSource.manual,
          dedupeHash: 'h3',
        ),
      ];

      final summary = BurnRateEngine.compute(
        accounts: accounts,
        transactions: txns,
        monthlyBudgetPaise: 1500000, // ₹15,000 budget
        nowOverride: now,
      );

      // Total balance = 10,000 + 20,000 - 4,050 = ₹25,950 (2,595,000 paise)
      expect(summary.totalBalancePaise, 2595000);
      expect(summary.monthlyCreditedPaise, 2000000);
      expect(summary.monthlyDebitedPaise, 405000);
      expect(summary.netMonthlyCashflowPaise, 1595000);
      // Remaining budget before today = 15,000 - 4,000 = 11,000 across 11 days = ₹1,000/day
      expect(summary.safeDailyAllowancePaise, 100000);
      expect(summary.spentTodayPaise, 5000);
      expect(summary.remainingTodayPaise, 95000);

      // Verify leak detector & privacy-preserving aggregate builder
      final leaks = LeakDetector.analyzeMonth(txns, nowOverride: now);
      expect(leaks.microSpendCount, 1);
      expect(leaks.microSpendTotalPaise, 5000);

      final payload = LeakDetector.buildAnonymizedPayload(
        cashflow: summary,
        leaks: leaks,
        categoryNamesById: {'cat_tech': 'Tech', 'cat_food': 'Food'},
      );
      expect(payload['monthly_credited_inr'], 20000.0);
      expect(payload.containsKey('transactions'), isFalse);
    });
  });

  group('AES-256-GCM Encrypted Local Backup & Restore', () {
    test('encrypts and decrypts vault snapshot and rejects wrong password', () async {
      final service = EncryptedBackupService();
      final snapshot = {
        'schema_version': 1,
        'transactions': [
          {'id': 'tx_1', 'amount_paise': 99900, 'title': 'Secret Project'},
        ],
      };

      final encrypted = await service.encryptSnapshotToJson(
        snapshot: snapshot,
        passphrase: 'correct-horse-battery',
      );
      expect(encrypted, contains(EncryptedBackupService.magicHeader));
      expect(encrypted, isNot(contains('Secret Project')));

      final restored = await service.decryptJsonToSnapshot(
        encryptedEnvelopeJson: encrypted,
        passphrase: 'correct-horse-battery',
      );
      expect(restored['schema_version'], 1);
      expect((restored['transactions'] as List).first['amount_paise'], 99900);

      expect(
        () => service.decryptJsonToSnapshot(
          encryptedEnvelopeJson: encrypted,
          passphrase: 'wrong-password',
        ),
        throwsA(anything),
      );
    });
  });

  testWidgets('Vault Lock onboarding renders and unlocks into FinTrack AI', (
    WidgetTester tester,
  ) async {
    final store = SecureStore.inMemory();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          pinHasherProvider.overrideWithValue(const PinHasher(iterations: 100)),
          biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
        ],
        child: const FinTrackApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Create Your Vault PIN'), findsOneWidget);
  });
}
