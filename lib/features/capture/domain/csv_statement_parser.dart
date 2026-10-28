import '../../../core/db/models.dart';
import '../../../core/gemini/gemini_service.dart';
import 'sms_regex_parser.dart';

class CsvStatementParser {
  static List<ParsedTransactionDraft> parseCsvContent(String csvContent) {
    final rows = _parseCsvRows(csvContent.trim());
    if (rows.length < 2) return const [];

    // Locate header row
    int headerRowIndex = 0;
    for (var i = 0; i < rows.length && i < 10; i++) {
      final joined = rows[i].map((e) => e.toLowerCase()).join(' ');
      if (joined.contains('date') &&
          (joined.contains('amount') ||
              joined.contains('debit') ||
              joined.contains('withdrawal') ||
              joined.contains('narration') ||
              joined.contains('description'))) {
        headerRowIndex = i;
        break;
      }
    }

    final headers = rows[headerRowIndex]
        .map((e) => e.trim().toLowerCase())
        .toList();

    int dateIdx = _findHeader(headers, ['date', 'txn date', 'value date']);
    int descIdx = _findHeader(headers, [
      'description',
      'narration',
      'particulars',
      'remarks',
      'merchant',
      'payee',
    ]);
    int debitIdx = _findHeader(headers, [
      'debit',
      'withdrawal',
      'dr',
      'spent',
    ]);
    int creditIdx = _findHeader(headers, [
      'credit',
      'deposit',
      'cr',
      'received',
    ]);
    int amountIdx = _findHeader(headers, ['amount', 'txn amount']);
    int typeIdx = _findHeader(headers, ['type', 'dr/cr', 'cr/dr']);
    int refIdx = _findHeader(headers, [
      'ref',
      'reference',
      'chq',
      'utr',
      'txn id',
    ]);

    if (descIdx == -1 && headers.length >= 2) descIdx = 1;
    if (dateIdx == -1) dateIdx = 0;

    final drafts = <ParsedTransactionDraft>[];

    for (var i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i].map((e) => e.trim()).toList();
      if (row.isEmpty) continue;

      final description = _safeCell(row, descIdx).isEmpty
          ? 'Statement Entry'
          : _safeCell(row, descIdx);
      final rawDate = _safeCell(row, dateIdx);
      final occurredAt = _parseDate(rawDate) ?? DateTime.now();
      final ref = _safeCell(row, refIdx);

      double debitVal = _parseMoney(_safeCell(row, debitIdx));
      double creditVal = _parseMoney(_safeCell(row, creditIdx));
      TxnType? type;
      double finalRupees = 0;

      if (debitVal > 0) {
        type = TxnType.debit;
        finalRupees = debitVal;
      } else if (creditVal > 0) {
        type = TxnType.credit;
        finalRupees = creditVal;
      } else if (amountIdx != -1) {
        final rawAmt = _safeCell(row, amountIdx);
        final amt = _parseMoney(rawAmt);
        if (amt != 0) {
          final rawType = _safeCell(row, typeIdx).toLowerCase();
          final isCredit = rawType.contains('cr') ||
              rawType.contains('credit') ||
              rawAmt.startsWith('+');
          final isDebit = rawType.contains('dr') ||
              rawType.contains('debit') ||
              rawAmt.startsWith('-');
          type = isCredit && !isDebit ? TxnType.credit : TxnType.debit;
          finalRupees = amt.abs();
        }
      }

      if (type == null || finalRupees <= 0) continue;

      final paise = (finalRupees * 100).round();
      final categoryId = SmsRegexParser.inferCategoryId(
        text: description,
        type: type,
      );

      drafts.add(
        ParsedTransactionDraft(
          title: description.length > 36
              ? '${description.substring(0, 36)}…'
              : description,
          amountPaise: paise,
          type: type,
          categoryId: categoryId,
          occurredAt: occurredAt,
          paymentMode: description.toUpperCase().contains('UPI')
              ? PaymentMode.upi
              : PaymentMode.netBanking,
          counterparty: description,
          referenceId: ref.isEmpty ? null : ref,
          source: TxnSource.statement,
        ),
      );
    }

    return drafts;
  }

  static List<List<String>> _parseCsvRows(String input) {
    final rows = <List<String>>[];
    final lines = input.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final cells = <String>[];
      final buffer = StringBuffer();
      var inQuotes = false;
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          inQuotes = !inQuotes;
        } else if (ch == ',' && !inQuotes) {
          cells.add(buffer.toString());
          buffer.clear();
        } else {
          buffer.write(ch);
        }
      }
      cells.add(buffer.toString());
      rows.add(cells);
    }
    return rows;
  }

  static int _findHeader(List<String> headers, List<String> candidates) {
    for (var i = 0; i < headers.length; i++) {
      for (final c in candidates) {
        if (headers[i].contains(c)) return i;
      }
    }
    return -1;
  }

  static String _safeCell(List<String> row, int idx) {
    if (idx < 0 || idx >= row.length) return '';
    return row[idx];
  }

  static double _parseMoney(String raw) {
    if (raw.isEmpty) return 0;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  static DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;

    final parts = raw.split(RegExp(r'[/\-\s]'));
    if (parts.length >= 3) {
      final p0 = int.tryParse(parts[0]);
      final p1 = int.tryParse(parts[1]);
      final p2 = int.tryParse(parts[2]);
      if (p0 != null && p1 != null && p2 != null) {
        final year = p2 < 100 ? 2000 + p2 : p2;
        if (p0 > 1900) {
          return DateTime(p0, p1.clamp(1, 12), p2.clamp(1, 31));
        }
        return DateTime(year, p1.clamp(1, 12), p0.clamp(1, 31));
      }
    }
    return null;
  }
}
