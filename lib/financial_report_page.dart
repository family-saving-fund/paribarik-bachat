
import 'package:flutter/material.dart';
import 'nepali_digits.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'financial_ledger_service.dart';
import 'fund_service.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import 'dart:convert';

class FinancialReportPage extends StatefulWidget {
  final String memberUid;
  final String memberName;
  final String role;
  final String pageTitle;

  const FinancialReportPage({
    super.key,
    required this.memberUid,
    required this.memberName,
    required this.role,
    this.pageTitle = 'रिपोर्ट तथा विवरण',
  });

  @override
  State<FinancialReportPage> createState() =>
      _FinancialReportPageState();
}

class _FinancialReportPageState extends State<FinancialReportPage> {
  String? _selectedMonth;
  String get memberUid => widget.memberUid;
  String get memberName => widget.memberName;
  String get role => widget.role;
    
  static const Map<String, int> _bsMonthNumbers = {
    'बैशाख': 1, 'वैशाख': 1, 'जेठ': 2, 'असार': 3,
    'साउन': 4, 'श्रावण': 4, 'भदौ': 5, 'भाद्र': 5,
    'असोज': 6, 'कार्तिक': 7, 'मंसिर': 8, 'पुष': 9,
    'पौष': 9, 'माघ': 10, 'फागुन': 11, 'चैत': 12, 'चैत्र': 12,
  };

  String? _monthKeyFromBsDate(String bsDate) {
    final normalized = toWesternDigits(bsDate).trim();
    if (normalized.isEmpty) return null;
    final numeric = RegExp(r'^(20\d{2})[-/](\d{1,2})(?:[-/]\d{1,2})?$')
        .firstMatch(normalized);
    if (numeric != null) {
      final year = int.tryParse(numeric.group(1)!);
      final month = int.tryParse(numeric.group(2)!);
      if (year != null && month != null && month >= 1 && month <= 12) {
        return '$year-${month.toString().padLeft(2, '0')}';
      }
    }

    final yearMatch = RegExp(r'(20\d{2})').firstMatch(normalized);
    if (yearMatch == null) return null;
    final year = int.tryParse(yearMatch.group(1)!);
    if (year == null) return null;
    int? month;
    for (final entry in _bsMonthNumbers.entries) {
      if (normalized.contains(entry.key)) {
        month = entry.value;
        break;
      }
    }
    if (month == null) return null;
    return '$year-${month.toString().padLeft(2, '0')}';
  }

  int? _getBsMonthOrder(String bsDate) {
    final key = _monthKeyFromBsDate(bsDate);
    if (key == null) return null;
    final parts = key.split('-');
    if (parts.length != 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return null;
    return year * 12 + month;
  }

  String? _recordMonthKey(Map<String, dynamic> data) {
    if (data['transactionType']?.toString() == 'monthly_payment') {
      final metadata = data['metadata'] is Map
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : <String, dynamic>{};
      final contributionMonth = metadata['monthKey']?.toString() ?? '';
      final normalizedContributionMonth = _monthKeyFromBsDate(contributionMonth);
      if (normalizedContributionMonth != null) return normalizedContributionMonth;
    }
    return _monthKeyFromBsDate(data['bsDate']?.toString() ?? '');
  }

  String _monthLabel(String key) {
    const months = [
      'बैशाख', 'जेठ', 'असार', 'साउन', 'भदौ', 'असोज',
      'कार्तिक', 'मंसिर', 'पुष', 'माघ', 'फागुन', 'चैत',
    ];
    final parts = key.split('-');
    if (parts.length != 2) return toNepaliDigits(key);
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return toNepaliDigits(key);
    }
    return '${toNepaliDigits(year.toString())} ${months[month - 1]}';
  }

    // Ledger बाट संस्थाको वास्तविक आम्दानी गणना गर्ने
  double _calculateInstitutionIncome(
    List<Map<String, dynamic>> records,
  ) {
    double totalIncome = 0;

    for (final data in records) {
      if (data['status'] != 'approved' ||
          data['isTest'] == true) {
        continue;
      }

      final metadata = data['metadata'] is Map
          ? Map<String, dynamic>.from(data['metadata'])
          : <String, dynamic>{};

      final type = data['transactionType']?.toString() ?? '';

      if (type == 'monthly_payment') {
        totalIncome +=
            (metadata['personalSavingsAmount'] as num? ?? 0) +
            (metadata['savingsPenaltyAmount'] as num? ?? 0);
      } else if (type == 'donation') {
        totalIncome +=
            metadata['institutionSavingsAmount'] as num? ?? 0;
      } else if (type == 'loan_repayment') {
        totalIncome +=
            metadata['interestPaid'] as num? ?? 0;
      } else if (type == 'other_income' &&
          metadata['fundType'] == 'savings') {
        totalIncome += (data['amount'] as num? ?? 0);
      }
    }

    return totalIncome;
  }
    
    Future<double> _calculateInstitutionIncomeFromFirestore({
  String? monthKey,
  bool beforeMonth = false,
}) async {
  final targetOrder = monthKey == null
      ? null
      : _getBsMonthOrder(monthKey);

  bool includeMonth(int? order) {
    if (targetOrder == null) return true;
    if (order == null) return false;

    return beforeMonth
        ? order < targetOrder
        : order == targetOrder;
  }

  int? getOrderFromTimestamp(dynamic value) {
    if (value is! Timestamp) return null;

    final bsDate =
        NepaliDateTime.fromDateTime(value.toDate());

    return (bsDate.year * 12) + bsDate.month;
  }

  double totalIncome = 0;

  final savingsSnapshot = await FirebaseFirestore.instance
      .collection('monthly_savings')
      .get();

  for (final doc in savingsSnapshot.docs) {
    final data = doc.data();
    if (data['isTest'] == true) continue;

    final key = data['monthKey']?.toString() ?? '';
    final order = _getBsMonthOrder(key);

    if (!includeMonth(order)) continue;

    totalIncome +=
        (data['savingsPaid'] as num? ?? 0).toDouble();

    totalIncome +=
        (data['normalSavingsPenaltyPaid'] as num? ?? 0)
            .toDouble();

    totalIncome +=
        (data['specialSavingsPenaltyPaid'] as num? ?? 0)
            .toDouble();
  }

  final donationSnapshot = await FirebaseFirestore.instance
      .collection('fund_transactions')
      .where('fundType', isEqualTo: 'savings')
      .where('category', isEqualTo: 'donation')
      .get();

  for (final doc in donationSnapshot.docs) {
    final data = doc.data();

    if (data['isTest'] == true) continue;

    final order = _getBsMonthOrder(data['bsDate']?.toString() ?? '') ??
        getOrderFromTimestamp(data['createdAt']);

    if (!includeMonth(order)) continue;

    totalIncome +=
        (data['amount'] as num? ?? 0).toDouble();
  }

  final otherIncomeSnapshot = await FirebaseFirestore.instance
      .collection('fund_transactions')
      .where('fundType', isEqualTo: 'savings')
      .where('category', isEqualTo: 'other_income')
      .get();

  for (final doc in otherIncomeSnapshot.docs) {
    final data = doc.data();
    if (data['isTest'] == true || data['status'] != 'approved') continue;
    final order = _getBsMonthOrder(data['bsDate']?.toString() ?? '') ??
        getOrderFromTimestamp(data['createdAt']);
    if (!includeMonth(order)) continue;
    totalIncome += (data['amount'] as num? ?? 0).toDouble();
  }

  final bankInterestSnapshot = await FirebaseFirestore.instance
      .collection('bank_interest_transactions')
      .where('fundType', isEqualTo: 'general')
      .where('incomeCategory', isEqualTo: 'bank_interest')
      .get();

  for (final doc in bankInterestSnapshot.docs) {
    final data = doc.data();
    if (data['isTest'] == true || data['isInstitutionIncome'] == false) continue;
    final order = _getBsMonthOrder(data['endBsDate']?.toString() ?? '') ??
        getOrderFromTimestamp(data['createdAt']);
    if (!includeMonth(order)) continue;
    totalIncome += (data['amount'] as num? ?? 0).toDouble();
  }

  final installmentSnapshot =
      await FirebaseFirestore.instance
          .collection('loan_installments')
          .where('status', isEqualTo: 'approved')
          .get();

  for (final doc in installmentSnapshot.docs) {
    final data = doc.data();

    if (data['isTest'] == true) continue;

    final order = _getBsMonthOrder(
          data['paymentBsDate']?.toString() ?? data['bsDate']?.toString() ?? '',
        ) ??
        getOrderFromTimestamp(data['approvedAt']);

    if (!includeMonth(order)) continue;

    totalIncome +=
        (data['interestPaid'] as num? ?? 0).toDouble();
  }

  return totalIncome;
}
    
  Future<pw.Font> _loadNepaliFont() async {
  final fontData = await rootBundle.load(
  'assets/fonts/NotoSansDevanagari-Regular.ttf',
  );

  return pw.Font.ttf(fontData);
}
    
  String _formatExpenseBsDate(
  dynamic bsDate,
  dynamic expenseDate,
) {
  NepaliDateTime? date;

  if (bsDate is String && bsDate.isNotEmpty) {
    final parts = bsDate.split('-');

    if (parts.length == 3) {
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);

      if (year != null && month != null && day != null) {
        date = NepaliDateTime(year, month, day);
      }
    }
  }

  if (date == null && expenseDate is Timestamp) {
    date = NepaliDateTime.fromDateTime(
      expenseDate.toDate(),
    );
  }

  if (date == null) {
    return '';
  }

  const months = [
    'बैशाख', 'जेठ', 'असार', 'साउन',
    'भदौ', 'असोज', 'कार्तिक', 'मंसिर',
    'पुष', 'माघ', 'फागुन', 'चैत',
  ];

  const weekdays = [
    'आइतबार', 'सोमबार', 'मंगलबार', 'बुधबार',
    'बिहिबार', 'शुक्रबार', 'शनिबार',
  ];

  return '${date.year} साल ${months[date.month - 1]} '
      '${date.day} गते ${weekdays[date.weekday - 1]}';
}
       
Future<void> _generateMonthlyPdf(
  List<Map<String, dynamic>> records,
  bool isAdmin, {
  double openingBalance = 0,
  double monthlyIncome = 0,
  double monthlyExpenses = 0,
}) async {
    
      final loanSnapshot = await FirebaseFirestore.instance
      .collection('loans')
      .get();

  final installmentSnapshot = await FirebaseFirestore.instance
      .collection('loan_installments')
      .get();

  final selectedLoanMonthOrder = _selectedMonth == null
      ? null
      : _getBsMonthOrder(_selectedMonth!);

  int? getBsOrderFromTimestamp(dynamic value) {
    if (value is! Timestamp) return null;

    final bsDate = NepaliDateTime.fromDateTime(value.toDate());
    return (bsDate.year * 12) + bsDate.month;
  }

  double outstandingLoanPrincipal = 0;

  for (final doc in loanSnapshot.docs) {
    final data = doc.data();
    final disbursedAt = data['disbursedAt'];
    final disbursedMonthOrder =
        getBsOrderFromTimestamp(disbursedAt);

    if (disbursedMonthOrder == null) continue;

    if (selectedLoanMonthOrder != null &&
        disbursedMonthOrder > selectedLoanMonthOrder) {
      continue;
    }

    outstandingLoanPrincipal +=
        (data['disbursedAmount'] as num? ?? 0).toDouble();
  }

  for (final doc in installmentSnapshot.docs) {
    final data = doc.data();

    if (data['status'] != 'approved') continue;

    final approvedMonthOrder =
        getBsOrderFromTimestamp(data['approvedAt']);

    if (approvedMonthOrder == null) continue;

    if (selectedLoanMonthOrder != null &&
        approvedMonthOrder > selectedLoanMonthOrder) {
      continue;
    }

    outstandingLoanPrincipal -=
        (data['principalPaid'] as num? ?? 0).toDouble();
  }

  if (outstandingLoanPrincipal < 0) {
    outstandingLoanPrincipal = 0;
  }
    
  final fontData = await rootBundle.load(
    'assets/fonts/NotoSansDevanagari-Regular.ttf',
  );

  final fontBase64 = base64Encode(
    fontData.buffer.asUint8List(),
  );
    
      final logoData = await rootBundle.load(
    'assets/official_logo.png',
  );

  final logoBase64 = base64Encode(
    logoData.buffer.asUint8List(),
  );

  String escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
    
    final memberSavingsSnapshot = await FirebaseFirestore.instance
      .collection('monthly_savings')
      .get();

  final memberSnapshot = await FirebaseFirestore.instance
      .collection('member')
      .get();

  final memberNames = <String, String>{};

  for (final doc in memberSnapshot.docs) {
    memberNames[doc.id] = doc.data()['name']?.toString() ?? '';
  }

  final memberSavingsTotals = <String, Map<String, double>>{};

  for (final doc in memberSavingsSnapshot.docs) {
    final data = doc.data();
    final uid = data['memberUid']?.toString() ?? '';
    final monthKey = data['monthKey']?.toString() ?? '';

    if (uid.isEmpty) continue;
    if (!isAdmin && uid != memberUid) continue;
    if (_selectedMonth != null && monthKey != _selectedMonth) {
      continue;
    }

    final totals = memberSavingsTotals.putIfAbsent(
      uid,
      () => {
        'savings': 0.0,
        'penalty': 0.0,
      },
    );

    totals['savings'] =
        totals['savings']! +
        ((data['savingsPaid'] as num?) ?? 0).toDouble();

    totals['penalty'] =
        totals['penalty']! +
        ((data['normalSavingsPenaltyPaid'] as num?) ?? 0).toDouble() +
        ((data['specialSavingsPenaltyPaid'] as num?) ?? 0).toDouble();
  }

  final memberSavingsEntries = memberSavingsTotals.entries.toList()
    ..sort((a, b) =>
        (memberNames[a.key] ?? '').compareTo(memberNames[b.key] ?? ''));

  final memberSavingsRowsHtml = memberSavingsEntries.map((entry) {
    final name = escapeHtml(memberNames[entry.key] ?? 'नाम उपलब्ध छैन');
    final savings = entry.value['savings']!;
    final penalty = entry.value['penalty']!;
    final total = savings + penalty;

    return '''
      <tr>
        <td>$name</td>
        <td>रु. ${savings.toStringAsFixed(2)}</td>
        <td>रु. ${penalty.toStringAsFixed(2)}</td>
        <td>रु. ${total.toStringAsFixed(2)}</td>
      </tr>
    ''';
  }).join();

  final tableRows = records.map((data) {

    final rawBsDate = data['bsDate']?.toString() ?? '';

final formattedBsDate =
    data['transactionType']?.toString() == 'खर्च'
        ? _formatExpenseBsDate(
            data['bsDate'],
            data['createdAt'],
          )
        : rawBsDate;

final date = escapeHtml(
  formattedBsDate.isNotEmpty
      ? formattedBsDate
      : rawBsDate,
);
      
    final name = escapeHtml(
      data['memberName']?.toString() ?? '',
    );
    final type = escapeHtml(
      data['transactionType']?.toString() ?? '',
    );
    final description = escapeHtml(
      data['description']?.toString() ?? '',
    );
    final status = escapeHtml(
      data['status']?.toString() ?? '',
    );

    final amount = data['amount'] is num
        ? (data['amount'] as num).toStringAsFixed(2)
        : '0.00';

    return '''
      <tr>
        <td>$date</td>
        <td>$name</td>
        <td>$type</td>
        <td>$description</td>
        <td>रु. $amount</td>
        <td>$status</td>
      </tr>
    ''';
  }).join();
    
      final institutionSavings =
   openingBalance + monthlyIncome - monthlyExpenses;
    
    final availableFund =
    (institutionSavings - outstandingLoanPrincipal).clamp(0.0, double.infinity);

  final financialSummaryHtml = isAdmin
      ? '''
        <h3>Financial Summary (आर्थिक सारांश)</h3>    
        <table>
          <tbody>
            <tr>
              <td>Opening Balance</td>
              <td>रु. ${openingBalance.toStringAsFixed(2)}</td>
            </tr>
            <tr>
              <td>Total Income</td>
              <td>रु. ${monthlyIncome.toStringAsFixed(2)}</td>
            </tr>
            <tr>
              <td>Total Expenses</td>
              <td>रु. ${monthlyExpenses.toStringAsFixed(2)}</td>
            </tr>
            <tr>
              <td>Institution Savings</td>
              <td>रु. ${institutionSavings.toStringAsFixed(2)}</td>
            </tr>
                        <tr>
              <td>Outstanding Loan Principal</td>
              <td>रु. ${outstandingLoanPrincipal.toStringAsFixed(2)}</td>
            </tr>
            <tr>
              <td>Available Fund</td>
              <td>रु. ${availableFund.toStringAsFixed(2)}</td>
            </tr>
            <tr>
              <td>Closing Balance</td>
              <td>रु. ${institutionSavings.toStringAsFixed(2)}</td>
            </tr>
          </tbody>
        </table>
      '''
      : '';

  final html = '''
  <!DOCTYPE html>
  <html lang="ne">
  <head>
    <meta charset="UTF-8">
    <style>
      @font-face {
        font-family: NepaliFont;
        src: url(data:font/ttf;base64,$fontBase64)
             format('truetype');
      }

      * {
        font-family: NepaliFont;
        box-sizing: border-box;
      }

      body {
        padding: 18px;
        color: #222222;
        font-size: 11px;
      }
      
      body::before {
        content: "";
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-image: url("data:image/png;base64,$logoBase64");
        background-repeat: no-repeat;
        background-position: center center;
        background-size: 85% auto;
        opacity: 0.07;
        z-index: -1;
        pointer-events: none;
      }

      h2 {
        text-align: center;
        font-size: 22px;
        margin-bottom: 8px;
      }

      .subtitle {
        font-size: 14px;
        margin-bottom: 8px;
      }

      table {
        width: 100%;
        border-collapse: collapse;
        table-layout: fixed;
      }

      th, td {
        border: 1px solid #888888;
        padding: 6px 4px;
        text-align: left;
        overflow-wrap: break-word;
        font-size: 9px;
      }

      th {
        background: #eeeeee;
      }

      tr {
        page-break-inside: avoid;
      }

      @page {
        size: A4;
        margin: 12mm;
      }
    </style>
  </head>
  <body>
    <h2>पारिवारिक बचत कोष</h2>

    <div class="subtitle">
      ${isAdmin ? 'सम्पूर्ण आर्थिक विवरण' : 'सदस्यको आर्थिक विवरण'}
    </div>
    
      <div style="text-align: center; margin-bottom: 12px;">
    <img
      src="data:image/png;base64,$logoBase64"
      style="width: 75px; height: 75px; object-fit: contain;"
    />
    <h2 style="margin: 6px 0; color: #101B3A;">
      पारिवारिक बचत कोष
    </h2>
    <h3 style="margin: 4px 0;">
      मासिक आर्थिक प्रतिवेदन
    </h3>
  </div>

  <div class="subtitle">
      महिना: ${escapeHtml(_selectedMonth == null ? 'सबै महिना' : _monthLabel(_selectedMonth!))}
    </div>

    <div class="subtitle">
      महिना: ${escapeHtml(_selectedMonth == null ? 'सबै महिना' : _monthLabel(_selectedMonth!))}
    </div>
    
 $financialSummaryHtml
     <h3>सदस्यगत बचत तथा जरिवाना विवरण</h3>

    <table>
      <thead>
        <tr>
          <th>सदस्यको नाम</th>
          <th>नियमित बचत</th>
          <th>बचत जरिवाना</th>
          <th>जम्मा</th>
        </tr>
      </thead>
      <tbody>
        $memberSavingsRowsHtml
      </tbody>
    </table>

    <table>
      <thead>
        <tr>
          <th>मिति</th>
          <th>सदस्य</th>
          <th>कारोबार</th>
          <th>विवरण</th>
          <th>रकम</th>
          <th>स्थिति</th>
        </tr>
      </thead>
      <tbody>
        $tableRows
      </tbody>
    </table>
  </body>
  </html>
  ''';

  final converter = HtmlToPdfConverter();

  final pdfBytes = await converter.convertHtmlToPdfBytes(
    html: html,
  );

  await Printing.layoutPdf(
    onLayout: (format) async => pdfBytes,
  );
}

  
  @override
  Widget build(BuildContext context) {
    final bool isAdmin = role.toLowerCase() == 'admin';
    final ledgerService = FinancialLedgerService();

    final Stream<QuerySnapshot<Map<String, dynamic>>> ledgerStream =
        isAdmin
            ? ledgerService.watchAllLedger()
            : ledgerService.watchMemberLedger(
                memberUid: memberUid,
              );
  final expenseStream = FirebaseFirestore.instance
        .collection('fund_transactions')
        .where('fundType', isEqualTo: 'expense')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pageTitle),
        backgroundColor: const Color(0xFFFFB02E),
        foregroundColor: const Color(0xFF102A43),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAdmin ? 'सम्पूर्ण आर्थिक विवरण' : memberName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  isAdmin
                      ? 'सबै सदस्यका वित्तीय कारोबार'
                      : 'तपाईंको वित्तीय कारोबार',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<
                QuerySnapshot<Map<String, dynamic>>>(
              stream: ledgerStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('विवरण लोड गर्न समस्या भयो।'),
                  );
                }

                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final records = snapshot.data?.docs ?? [];

                final availableMonths = records
                    .map((doc) => _recordMonthKey(doc.data()))
                    .whereType<String>()
                    .toSet()
                    .toList()
                  ..sort((a, b) => b.compareTo(a));

                final filteredRecords = _selectedMonth == null
                    ? records
                    : records.where((doc) {
                        return _recordMonthKey(doc.data()) == _selectedMonth;
                      }).toList();

                return StreamBuilder<
    QuerySnapshot<Map<String, dynamic>>>(
  stream: isAdmin ? expenseStream : const Stream.empty(),
  builder: (context, expenseSnapshot) {
    if (isAdmin && expenseSnapshot.hasError) {
      return const Center(
        child: Text('खर्च विवरण लोड गर्न समस्या भयो।'),
      );
    }

    if (isAdmin &&
    expenseSnapshot.connectionState ==
        ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

final expenseRecords = expenseSnapshot.data?.docs ?? [];
      
      final normalizedExpenseRecords = isAdmin
    ? expenseRecords
        .where((doc) {
          final data = doc.data();
          return data['category'] == 'expense_withdrawal' &&
              data['status'] == 'disbursed' &&
              data['isTest'] != true;
        })
        .map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'bsDate': data['bsDate'] ?? '',
            'memberName': 'संस्था',
            'transactionType': 'खर्च',
            'description':
                data['title'] ?? data['description'] ?? '',
            'status': data['status'] ?? '',
              'amount': data['amount'] ?? 0,
         'createdAt': data['createdAt'] ?? data['expenseDate'],
          };
        })
     .toList()
    : <Map<String, dynamic>>[];
      
      final reportAvailableMonths = <String>{
  ...availableMonths,
  ...normalizedExpenseRecords
      .map((data) => _monthKeyFromBsDate(data['bsDate']?.toString() ?? ''))
      .whereType<String>(),
}.toList()
  ..sort((a, b) => b.compareTo(a));

final filteredExpenseRecords = _selectedMonth == null
    ? normalizedExpenseRecords
    : normalizedExpenseRecords.where((data) {
        final date = data['bsDate']?.toString() ?? '';
        return _monthKeyFromBsDate(date) == _selectedMonth;
      }).toList();
      
      final monthlyIncome = 0.0;

final monthlyExpenses = isAdmin
    ? filteredExpenseRecords.fold<double>(
        0,
        (total, data) =>
            total + ((data['amount'] as num?) ?? 0).toDouble(),
      )
    : 0.0;
   final selectedMonthOrder = _selectedMonth == null
    ? null
    : _getBsMonthOrder(_selectedMonth!);

final previousMonthRecords = selectedMonthOrder == null
    ? <Map<String, dynamic>>[]
    : records
        .map((doc) => doc.data())
        .where((data) {
          final monthKey = _recordMonthKey(data);
          final order = monthKey == null ? null : _getBsMonthOrder(monthKey);
          return order != null && order < selectedMonthOrder;
        })
        .toList();

final previousMonthExpenses = selectedMonthOrder == null
    ? <Map<String, dynamic>>[]
    : normalizedExpenseRecords.where((data) {
        final date = data['bsDate']?.toString() ?? '';
        final order = _getBsMonthOrder(date);
        return order != null && order < selectedMonthOrder;
      }).toList();

final openingBalance = 0.0;
      
      final reportRecords = <Map<String, dynamic>>[
  ...filteredRecords.map((doc) => doc.data()),
  ...filteredExpenseRecords,
];

reportRecords.sort((a, b) {
  final dateA = a['createdAt'];
  final dateB = b['createdAt'];

  final timeA = dateA is Timestamp
      ? dateA
      : Timestamp(0, 0);

  final timeB = dateB is Timestamp
      ? dateB
      : Timestamp(0, 0);

  return timeB.compareTo(timeA);
});
      
    return Column(
                  children: [
 if (reportAvailableMonths.isNotEmpty)
                      Padding(
 padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: DropdownButtonFormField<String>(
                          value: reportAvailableMonths.contains(_selectedMonth)
                              ? _selectedMonth
                              : null,
             decoration: const InputDecoration(
                labelText: 'महिना छान्नुहोस्',
                border: OutlineInputBorder(),
                          ),
                          hint: const Text('सबै महिना'),
           items: reportAvailableMonths.map((month) {
              return DropdownMenuItem<String>(
                              value: month,
                              child: Text(_monthLabel(month)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedMonth = value;
                            });
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                            
                          onPressed: filteredRecords.isEmpty &&
        filteredExpenseRecords.isEmpty
    ? null
    : () async {
        final income = isAdmin
            ? await _calculateInstitutionIncomeFromFirestore(
                monthKey: _selectedMonth,
              )
            : 0.0;

        final opening = isAdmin && _selectedMonth != null
            ? await _calculateInstitutionIncomeFromFirestore(
                monthKey: _selectedMonth,
                beforeMonth: true,
              ) -
                previousMonthExpenses.fold<double>(
                  0,
                  (total, data) =>
                      total +
                      ((data['amount'] as num?) ?? 0).toDouble(),
                )
            : 0.0;
        
                final paymentSnapshot = await FirebaseFirestore.instance
            .collection('payments')
            .get();

        final approvedPayments = paymentSnapshot.docs.where((doc) {
          final data = doc.data();

          if (data['status'] != 'approved') return false;

          final paymentType = data['paymentType']?.toString() ?? '';
          if (paymentType != 'full' && paymentType != 'partial') {
            return false;
          }

          if (!isAdmin && data['memberUid'] != memberUid) {
            return false;
          }

          final monthKeys = (data['monthKeys'] as List?) ?? [];
          if (_selectedMonth != null &&
              !monthKeys.contains(_selectedMonth)) {
            return false;
          }

          return true;
        }).toList();

        final paymentIds = approvedPayments
            .map((doc) =>
                doc.data()['paymentId']?.toString() ?? doc.id)
            .toSet();

        final pdfRecords = reportRecords.where((record) {
          if (record['transactionType'] != 'monthly_payment') {
            return true;
          }

          final sourceId =
              record['sourceDocumentId']?.toString() ?? '';
          return !paymentIds.contains(sourceId);
        }).toList();

        for (final doc in approvedPayments) {
          final data = doc.data();

          final approvedAmount =
              data['approvedAmount'] ?? data['amount'] ?? 0;

          pdfRecords.add({
            'transactionType': 'monthly_payment',
            'memberName': data['memberName']?.toString() ?? '',
            'memberUid': data['memberUid']?.toString() ?? '',
            'bsDate': data['bsDate']?.toString() ?? '',
            'amount': approvedAmount is num
                ? approvedAmount.toDouble()
                : 0.0,
            'description': 'स्वीकृत मासिक भुक्तानी',
          });
        }

         await _generateMonthlyPdf(
          pdfRecords,
          isAdmin,
          openingBalance: opening,
          monthlyIncome: income,
          monthlyExpenses: monthlyExpenses.toDouble(),
        );
      },
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text(
                            'PDF रिपोर्ट निकाल्नुहोस्',
                          ),
                        ),
                      ),
                    ),
                    Expanded(
        child: filteredRecords.isEmpty &&
        filteredExpenseRecords.isEmpty
    ? const Center(
                              child: Text(
 'अहिलेसम्म कुनै वित्तीय कारोबार भेटिएन।',
                              ),
                            )
 : ListView.builder(
  padding: const EdgeInsets.all(12),
   itemCount: reportRecords.length,
itemBuilder: (context, index) {
  final data = reportRecords[index];

                                final String type =
                                    data['transactionType']
                                            ?.toString() ??
                                        '';
                                final String displayType = switch (type) {
                                  'monthly_payment' => 'मासिक बचत भुक्तानी',
                                  'donation' => 'चन्दा / दान',
                                  'loan_repayment' => 'ऋण ब्याज भुक्तानी',
                                  'other_income' => 'अन्य आम्दानी',
                                  'खर्च' => 'कोष खर्च',
                                  _ => type,
                                };

                                final String name =
                                    data['memberName']?.toString() ??
                                        '';

                                final String bsDate =
                                    data['bsDate']?.toString() ?? '';

                                final String description =
                                    data['description']?.toString() ??
                                        '';

                                final num amount =
                                    data['amount'] is num
                                        ? data['amount'] as num
                                        : 0;

                                return Card(
                                  margin: const EdgeInsets.only(
                                    bottom: 10,
                                  ),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor:
                                          Color(0xFFE8F5E9),
                                      child: Icon(
                                        Icons.receipt_long,
                                        color: Color(0xFF167D46),
                                      ),
                                    ),
                                    title: Text(
                                      displayType.isEmpty
                                          ? 'वित्तीय कारोबार'
                                          : displayType,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (isAdmin &&
                                            name.isNotEmpty)
                                          Text('सदस्य: $name'),
                                        if (bsDate.isNotEmpty)
                                          Text('मिति: ${toNepaliDigits(bsDate)}'),
                                        if (description.isNotEmpty)
                                          Text(description),
                                      ],
                                    ),
                                    trailing: Text(
                                      'रु. ${amount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF167D46),
                                      ),
                                    ),
                                    isThreeLine: true,
                                  ),
                                );
                              },
                            ),
                    ),
                                    ],
                );
              },
            );
          },
        ),
      ),
        ],
      ),
    );
  }
}
