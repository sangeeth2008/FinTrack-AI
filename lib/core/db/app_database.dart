import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;
import 'models.dart';

class AppDatabase {
  final sqlcipher.Database _db;

  AppDatabase._(this._db);

  static const List<AccountModel> defaultAccounts = [
    AccountModel(
      id: 'acc_upi_primary',
      name: 'Primary Bank & UPI',
      type: 'upi',
      initialBalancePaise: 0,
      colorValue: 0xFF10E5A0,
    ),
    AccountModel(
      id: 'acc_cash',
      name: 'Cash Wallet',
      type: 'cash',
      initialBalancePaise: 0,
      colorValue: 0xFFE8C468,
    ),
    AccountModel(
      id: 'acc_savings',
      name: 'Savings Vault',
      type: 'bank',
      initialBalancePaise: 0,
      colorValue: 0xFF00F2FF,
    ),
  ];

  static const List<CategoryModel> defaultCategories = [
    CategoryModel(
      id: 'cat_food',
      name: 'Food & Dining',
      iconKey: 'restaurant',
      colorValue: 0xFFFF7A59,
      monthlyBudgetPaise: 800000, // ₹8,000
    ),
    CategoryModel(
      id: 'cat_tech',
      name: 'Tech & Components',
      iconKey: 'memory',
      colorValue: 0xFF00F2FF,
      monthlyBudgetPaise: 600000, // ₹6,000
    ),
    CategoryModel(
      id: 'cat_commute',
      name: 'Commute & Auto',
      iconKey: 'directions_car',
      colorValue: 0xFFE8C468,
      monthlyBudgetPaise: 300000, // ₹3,000
    ),
    CategoryModel(
      id: 'cat_college',
      name: 'College & Books',
      iconKey: 'school',
      colorValue: 0xFFA78BFA,
      monthlyBudgetPaise: 400000,
    ),
    CategoryModel(
      id: 'cat_subscriptions',
      name: 'Subscriptions',
      iconKey: 'autorenew',
      colorValue: 0xFFFF5C7A,
      monthlyBudgetPaise: 150000,
    ),
    CategoryModel(
      id: 'cat_entertainment',
      name: 'Entertainment',
      iconKey: 'movie',
      colorValue: 0xFFF472B6,
      monthlyBudgetPaise: 250000,
    ),
    CategoryModel(
      id: 'cat_utilities',
      name: 'Bills & Recharge',
      iconKey: 'bolt',
      colorValue: 0xFF38BDF8,
      monthlyBudgetPaise: 200000,
    ),
    CategoryModel(
      id: 'cat_other',
      name: 'Other Expense',
      iconKey: 'category',
      colorValue: 0xFF94A3B8,
      monthlyBudgetPaise: 200000,
    ),
    CategoryModel(
      id: 'cat_income_salary',
      name: 'Income / Stipend',
      iconKey: 'payments',
      colorValue: 0xFF10E5A0,
      monthlyBudgetPaise: 0,
      isIncome: true,
    ),
    CategoryModel(
      id: 'cat_income_refund',
      name: 'Split Repayment & Refund',
      iconKey: 'call_received',
      colorValue: 0xFF34D399,
      monthlyBudgetPaise: 0,
      isIncome: true,
    ),
  ];

  static Future<AppDatabase> openEncrypted({required String password}) async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'fintrack_vault_v1.db');
    final db = await sqlcipher.openDatabase(
      dbPath,
      password: password,
      version: 1,
      onCreate: _onCreate,
    );
    return AppDatabase._(db);
  }

  static Future<AppDatabase> wrapForTesting(sqlcipher.Database db) async {
    await _onCreate(db, 1);
    return AppDatabase._(db);
  }

  static Future<void> _onCreate(sqlcipher.Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        initial_balance_paise INTEGER NOT NULL DEFAULT 0,
        color_value INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon_key TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        monthly_budget_paise INTEGER NOT NULL DEFAULT 0,
        is_income INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY,
        amount_paise INTEGER NOT NULL,
        type TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'INR',
        title TEXT NOT NULL,
        counterparty TEXT NOT NULL,
        category_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        occurred_at_ms INTEGER NOT NULL,
        payment_mode TEXT NOT NULL,
        reference_id TEXT,
        source TEXT NOT NULL,
        dedupe_hash TEXT NOT NULL,
        tags_json TEXT NOT NULL DEFAULT '[]',
        note TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_txn_occurred ON transactions(occurred_at_ms DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_txn_dedupe ON transactions(dedupe_hash)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_txn_ref ON transactions(reference_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS split_shares (
        id TEXT PRIMARY KEY,
        transaction_id TEXT NOT NULL,
        friend_name TEXT NOT NULL,
        friend_upi_vpa TEXT,
        share_paise INTEGER NOT NULL,
        is_settled INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        settled_at_ms INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS impulse_items (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        price_paise INTEGER NOT NULL,
        category_id TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        unlock_at_ms INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'locked',
        reason_note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS merchant_rules (
        normalized_merchant TEXT PRIMARY KEY,
        category_id TEXT NOT NULL
      )
    ''');

    for (final acc in defaultAccounts) {
      await db.insert(
        'accounts',
        acc.toMap(),
        conflictAlgorithm: sqlcipher.ConflictAlgorithm.ignore,
      );
    }
    for (final cat in defaultCategories) {
      await db.insert(
        'categories',
        cat.toMap(),
        conflictAlgorithm: sqlcipher.ConflictAlgorithm.ignore,
      );
    }
  }

  Future<List<AccountModel>> getAccounts() async {
    final rows = await _db.query('accounts');
    return rows.map(AccountModel.fromMap).toList();
  }

  Future<void> updateAccountInitialBalance(
    String accountId,
    int initialBalancePaise,
  ) async {
    await _db.update(
      'accounts',
      {'initial_balance_paise': initialBalancePaise},
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  Future<List<CategoryModel>> getCategories() async {
    final rows = await _db.query('categories');
    return rows.map(CategoryModel.fromMap).toList();
  }

  Future<void> updateCategoryBudget(
    String categoryId,
    int monthlyBudgetPaise,
  ) async {
    await _db.update(
      'categories',
      {'monthly_budget_paise': monthlyBudgetPaise},
      where: 'id = ?',
      whereArgs: [categoryId],
    );
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final rows = await _db.query(
      'transactions',
      orderBy: 'occurred_at_ms DESC',
    );
    return rows.map(TransactionModel.fromMap).toList();
  }

  Future<bool> existsByDedupeHashOrRef({
    required String dedupeHash,
    String? referenceId,
  }) async {
    if (referenceId != null && referenceId.trim().length >= 6) {
      final refRows = await _db.query(
        'transactions',
        columns: ['id'],
        where: 'reference_id = ?',
        whereArgs: [referenceId.trim()],
        limit: 1,
      );
      if (refRows.isNotEmpty) return true;
    }
    final hashRows = await _db.query(
      'transactions',
      columns: ['id'],
      where: 'dedupe_hash = ?',
      whereArgs: [dedupeHash],
      limit: 1,
    );
    return hashRows.isNotEmpty;
  }

  Future<void> upsertTransaction(TransactionModel txn) async {
    await _db.insert(
      'transactions',
      txn.toMap(),
      conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
    );
    final normMerchant = txn.counterparty
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normMerchant.length >= 3) {
      await _db.insert(
        'merchant_rules',
        {
          'normalized_merchant': normMerchant,
          'category_id': txn.categoryId,
        },
        conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
      );
    }
  }

  Future<int> insertTransactionsBatchDeduplicated(
    List<TransactionModel> txns,
  ) async {
    var inserted = 0;
    for (final txn in txns) {
      final isDupe = await existsByDedupeHashOrRef(
        dedupeHash: txn.dedupeHash,
        referenceId: txn.referenceId,
      );
      if (!isDupe) {
        await upsertTransaction(txn);
        inserted++;
      }
    }
    return inserted;
  }

  Future<void> deleteTransaction(String id) async {
    await _db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    await _db.delete(
      'split_shares',
      where: 'transaction_id = ?',
      whereArgs: [id],
    );
  }

  Future<String?> lookupLearnedCategory(String counterparty) async {
    final norm = counterparty
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (norm.length < 3) return null;
    final rows = await _db.query(
      'merchant_rules',
      where: 'normalized_merchant = ?',
      whereArgs: [norm],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['category_id'] as String?;
  }

  Future<List<SplitShareModel>> getSplitShares() async {
    final rows = await _db.query(
      'split_shares',
      orderBy: 'is_settled ASC, created_at_ms DESC',
    );
    return rows.map(SplitShareModel.fromMap).toList();
  }

  Future<void> insertSplitShare(SplitShareModel share) async {
    await _db.insert(
      'split_shares',
      share.toMap(),
      conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
    );
  }

  Future<void> markSplitSettled(String splitId, DateTime settledAt) async {
    await _db.update(
      'split_shares',
      {
        'is_settled': 1,
        'settled_at_ms': settledAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [splitId],
    );
  }

  Future<List<ImpulseItemModel>> getImpulseItems() async {
    final rows = await _db.query(
      'impulse_items',
      orderBy: 'created_at_ms DESC',
    );
    return rows.map(ImpulseItemModel.fromMap).toList();
  }

  Future<void> upsertImpulseItem(ImpulseItemModel item) async {
    await _db.insert(
      'impulse_items',
      item.toMap(),
      conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
    );
  }

  Future<void> updateImpulseStatus(String id, String status) async {
    await _db.update(
      'impulse_items',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>> exportSnapshot() async {
    final accounts = await _db.query('accounts');
    final categories = await _db.query('categories');
    final transactions = await _db.query('transactions');
    final splits = await _db.query('split_shares');
    final impulse = await _db.query('impulse_items');

    return {
      'schema_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'accounts': accounts,
      'categories': categories,
      'transactions': transactions,
      'split_shares': splits,
      'impulse_items': impulse,
    };
  }

  Future<void> restoreSnapshot(Map<String, dynamic> snapshot) async {
    await _db.transaction((txn) async {
      for (final row in (snapshot['accounts'] as List? ?? const [])) {
        await txn.insert(
          'accounts',
          Map<String, Object?>.from(row as Map),
          conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
        );
      }
      for (final row in (snapshot['categories'] as List? ?? const [])) {
        await txn.insert(
          'categories',
          Map<String, Object?>.from(row as Map),
          conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
        );
      }
      for (final row in (snapshot['transactions'] as List? ?? const [])) {
        await txn.insert(
          'transactions',
          Map<String, Object?>.from(row as Map),
          conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
        );
      }
      for (final row in (snapshot['split_shares'] as List? ?? const [])) {
        await txn.insert(
          'split_shares',
          Map<String, Object?>.from(row as Map),
          conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
        );
      }
      for (final row in (snapshot['impulse_items'] as List? ?? const [])) {
        await txn.insert(
          'impulse_items',
          Map<String, Object?>.from(row as Map),
          conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> close() => _db.close();
}

