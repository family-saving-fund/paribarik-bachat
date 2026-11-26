import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'nepali_digits.dart';

class MonthlyFinancialReportPage extends StatefulWidget {
  const MonthlyFinancialReportPage({super.key});

  @override
  State<MonthlyFinancialReportPage> createState() =>
      _MonthlyFinancialReportPageState();
}

class _MonthlyFinancialReportPageState extends State<MonthlyFinancialReportPage> {
  late Future<Map<String, dynamic>> _reportFuture;
  String? _selectedMonth;

  static const _months = [
    'बैशाख', 'जेठ', 'असार', 'साउन', 'भदौ', 'असोज',
    'कार्तिक', 'मंसिर', 'पुष', 'माघ', 'फागुन', 'चैत',
  ];
  static const _monthNumbers = <String, int>{
    'बैशाख': 1, 'वैशाख': 1, 'जेठ': 2, 'असार': 3,
    'साउन': 4, 'श्रावण': 4, 'भदौ': 5, 'भाद्र': 5,
    'असोज': 6, 'कार्तिक': 7, 'मंसिर': 8, 'पुष': 9,
    'पौष': 9, 'माघ': 10, 'फागुन': 11, 'चैत': 12, 'चैत्र': 12,
  };

  double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  String? _monthKey(dynamic value) {
    if (value == null) return null;
    final raw = toWesternDigits(value.toString()).trim();
    if (raw.isEmpty) return null;
    final numeric = RegExp(r'^(20\d{2})[-/](\d{1,2})(?:[-/]\d{1,2})?$')
        .firstMatch(raw);
    if (numeric != null) {
      final year = int.tryParse(numeric.group(1)!);
      final month = int.tryParse(numeric.group(2)!);
      if (year != null && month != null && month >= 1 && month <= 12) {
        return '$year-${month.toString().padLeft(2, '0')}';
      }
    }
    final yearMatch = RegExp(r'(20\d{2})').firstMatch(raw);
    if (yearMatch == null) return null;
    final year = int.tryParse(yearMatch.group(1)!);
    if (year == null) return null;
    for (final entry in _monthNumbers.entries) {
      if (raw.contains(entry.key)) {
        return '$year-${entry.value.toString().padLeft(2, '0')}';
      }
    }
    return null;
  }

  String _monthLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return toNepaliDigits(key);
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return toNepaliDigits(key);
    }
    return 'वि.सं. ${toNepaliDigits(year.toString())} ${_months[month - 1]}';
  }

  Map<String, double> _emptyTotals() => {
        'memberSavings': 0,
        'insuranceContributions': 0,
        'savingsPenalties': 0,
        'insurancePenalties': 0,
        'savingsDonation': 0,
        'insuranceDonation': 0,
        'savingsOtherIncome': 0,
        'insuranceOtherIncome': 0,
        'generalBankInterest': 0,
        'insuranceBankInterest': 0,
        'memberInterest': 0,
        'generalExpenses': 0,
        'insuranceExpenses': 0,
      };

  Future<Map<String, dynamic>> _loadReport() async {
    final db = FirebaseFirestore.instance;
    final snapshots = await Future.wait([
      db.collection('monthly_savings').get(),
      db.collection('fund_transactions').get(),
      db.collection('bank_interest_transactions').get(),
      db.collection('financial_ledger').where('status', isEqualTo: 'approved').get(),
      db.collection('payments').get(),
      db.collection('loan_installments').where('status', isEqualTo: 'approved').get(),
    ]);
    final byMonth = <String, Map<String, double>>{};
    Map<String, double> totalsFor(String key) =>
        byMonth.putIfAbsent(key, _emptyTotals);

    for (final doc in (snapshots[0] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final data = doc.data();
      if (data['isTest'] == true) continue;
      final key = _monthKey(data['monthKey']);
      if (key == null) continue;
      final totals = totalsFor(key);
      totals['memberSavings'] = totals['memberSavings']! + _number(data['savingsPaid']);
      totals['insuranceContributions'] =
          totals['insuranceContributions']! + _number(data['insurancePaid']);
      totals['savingsPenalties'] = totals['savingsPenalties']! +
          _number(data['normalSavingsPenaltyPaid']) +
          _number(data['specialSavingsPenaltyPaid']);
      totals['insurancePenalties'] = totals['insurancePenalties']! +
          _number(data['normalInsurancePenaltyPaid']) +
          _number(data['specialInsurancePenaltyPaid']);
    }

    // दान र ऋण ब्याजको मिति financial_ledger मा रहेको BS मिति हो।
    // यी ID राखेर पुराना ledger नभएका रेकर्ड मात्र fallback मा थपिन्छन्।
    final ledgerDonationIds = <String>{};
    final ledgerInstallmentIds = <String>{};
    for (final doc in (snapshots[3] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final data = doc.data();
      if (data['isTest'] == true) continue;
      final key = _monthKey(data['bsDate']);
      if (key == null) continue;
      final totals = totalsFor(key);
      final metadata = data['metadata'] is Map
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : <String, dynamic>{};
      switch (data['transactionType']?.toString()) {
        case 'donation': {
          final sourceId = data['sourceDocumentId']?.toString() ?? '';
          if (sourceId.isNotEmpty) ledgerDonationIds.add(sourceId);
          totals['savingsDonation'] = totals['savingsDonation']! +
              _number(metadata['institutionSavingsAmount']);
          totals['insuranceDonation'] = totals['insuranceDonation']! +
              _number(metadata['insuranceAmount']);
          break;
        }
        case 'loan_repayment': {
          final sourceId = data['sourceDocumentId']?.toString() ?? '';
          if (sourceId.isNotEmpty) ledgerInstallmentIds.add(sourceId);
          totals['memberInterest'] = totals['memberInterest']! +
              _number(metadata['interestPaid']);
          break;
        }
      }
    }

    // पुराना donation ledger नबनेको अवस्थामा approved payment बाट मात्र थप्ने।
    for (final doc in (snapshots[4] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final data = doc.data();
      if (data['isTest'] == true || data['status'] != 'approved' ||
          data['paymentType']?.toString() != 'donation') continue;
      final paymentId = data['paymentId']?.toString() ?? doc.id;
      if (ledgerDonationIds.contains(paymentId)) continue;
      final key = _monthKey(data['bsDate']);
      if (key == null) continue;
      final totals = totalsFor(key);
      final amount = _number(data['approvedAmount'] ?? data['amount']);
      final insurancePart = data['donationInsuranceAmount'] is num
          ? _number(data['donationInsuranceAmount'])
          : (amount / 2).floorToDouble();
      final savingsPart = data['donationInstitutionAmount'] is num
          ? _number(data['donationInstitutionAmount'])
          : amount - insurancePart;
      totals['savingsDonation'] = totals['savingsDonation']! + savingsPart;
      totals['insuranceDonation'] = totals['insuranceDonation']! + insurancePart;
    }

    // पुराना loan ledger नभएका approved किस्ताबाट ब्याज मात्र थप्ने; साँवा होइन।
    for (final doc in (snapshots[5] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final data = doc.data();
      if (data['isTest'] == true) continue;
      if (ledgerInstallmentIds.contains(doc.id)) continue;
      final key = _monthKey(data['paymentBsDate'] ?? data['bsDate']);
      if (key == null) continue;
      final totals = totalsFor(key);
      totals['memberInterest'] = totals['memberInterest']! + _number(data['interestPaid']);
    }

    for (final doc in (snapshots[1] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final data = doc.data();
      if (data['isTest'] == true) continue;
      final key = _monthKey(data['bsDate']);
      if (key == null) continue;
      final totals = totalsFor(key);
      final amount = _number(data['amount']);
      final fundType = data['fundType']?.toString() ?? '';
      final category = data['category']?.toString() ?? '';
      if (category == 'other_income' && data['status'] == 'approved') {
        if (fundType == 'savings') {
          totals['savingsOtherIncome'] = totals['savingsOtherIncome']! + amount;
        } else if (fundType == 'insurance') {
          totals['insuranceOtherIncome'] = totals['insuranceOtherIncome']! + amount;
        }
      } else if (fundType == 'expense' && data['status'] == 'disbursed') {
        if (category == 'insurance_claim_payout') {
          totals['insuranceExpenses'] = totals['insuranceExpenses']! + amount;
        } else {
          totals['generalExpenses'] = totals['generalExpenses']! + amount;
        }
      }
    }

    for (final doc in (snapshots[2] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final data = doc.data();
      if (data['isTest'] == true || data['isInstitutionIncome'] == false) continue;
      final key = _monthKey(data['endBsDate']);
      if (key == null) continue;
      final totals = totalsFor(key);
      final amount = _number(data['amount']);
      if (data['fundType'] == 'general') {
        totals['generalBankInterest'] = totals['generalBankInterest']! + amount;
      } else if (data['fundType'] == 'insurance') {
        totals['insuranceBankInterest'] = totals['insuranceBankInterest']! + amount;
      }
    }

    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    final selected = _selectedMonth;
    final chosen = selected != null && byMonth.containsKey(selected)
        ? selected
        : (months.isNotEmpty ? months.first : null);
    return {
      'months': months,
      'selectedMonth': chosen,
      'totals': chosen == null ? _emptyTotals() : byMonth[chosen]!,
    };
  }

  double _generalNet(Map<String, double> d) =>
      d['memberSavings']! + d['savingsPenalties']! +
      d['savingsDonation']! + d['savingsOtherIncome']! +
      d['generalBankInterest']! + d['memberInterest']! -
      d['generalExpenses']!;

  double _insuranceNet(Map<String, double> d) =>
      d['insuranceContributions']! + d['insurancePenalties']! +
      d['insuranceDonation']! + d['insuranceOtherIncome']! +
      d['insuranceBankInterest']! - d['insuranceExpenses']!;

  String _money(num value) => 'रु. ${toNepaliDigits(value.round().toString())}';

  Future<void> _exportPdf(String month, Map<String, double> totals) async {
    final fontData = await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final pdf = pw.Document();
    final totalIncome = totals['memberSavings']! + totals['insuranceContributions']! +
        totals['savingsPenalties']! + totals['insurancePenalties']! +
        totals['savingsDonation']! + totals['insuranceDonation']! +
        totals['savingsOtherIncome']! + totals['insuranceOtherIncome']! +
        totals['generalBankInterest']! + totals['insuranceBankInterest']! +
        totals['memberInterest']!;
    final totalExpenses = totals['generalExpenses']! + totals['insuranceExpenses']!;
    final totalOtherIncome = totals['savingsDonation']! + totals['insuranceDonation']! +
        totals['savingsOtherIncome']! + totals['insuranceOtherIncome']!;
    final totalInterest = totals['generalBankInterest']! +
        totals['insuranceBankInterest']! + totals['memberInterest']!;
    final rows = <List<String>>[
      ['सदस्यहरूको मासिक बचत', _money(totals['memberSavings']!)],
      ['बचत कोष जरिमाना', _money(totals['savingsPenalties']!)],
      ['बीमा योगदान', _money(totals['insuranceContributions']!)],
      ['बीमा जरिमाना', _money(totals['insurancePenalties']!)],
      ['दान — बचत कोष', _money(totals['savingsDonation']!)],
      ['दान — बीमा कोष', _money(totals['insuranceDonation']!)],
      ['अन्य आम्दानी — बचत कोष', _money(totals['savingsOtherIncome']!)],
      ['अन्य आम्दानी — बीमा कोष', _money(totals['insuranceOtherIncome']!)],
      ['कुल अन्य आम्दानी (दानसहित)', _money(totalOtherIncome)],
      ['बैंक ब्याज — बचत कोष', _money(totals['generalBankInterest']!)],
      ['बैंक ब्याज — बीमा कोष', _money(totals['insuranceBankInterest']!)],
      ['ऋणबाट प्राप्त ब्याज', _money(totals['memberInterest']!)],
      ['कुल ब्याज आम्दानी', _money(totalInterest)],
      ['खर्च — बचत कोष', _money(totals['generalExpenses']!)],
      ['खर्च — बीमा कोष', _money(totals['insuranceExpenses']!)],
      ['कुल आम्दानी', _money(totalIncome)],
      ['कुल खर्च', _money(totalExpenses)],
      ['बचत कोषको खुद परिणाम', _money(_generalNet(totals))],
      ['बीमा कोषको खुद परिवर्तन', _money(_insuranceNet(totals))],
    ];
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      build: (_) => [
        pw.Center(child: pw.Text('पारिवारिक बचत कोष', style: pw.TextStyle(font: font, fontSize: 18, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 5),
        pw.Center(child: pw.Text('मासिक आर्थिक प्रतिवेदन — ${_monthLabel(month)}', style: pw.TextStyle(font: font, fontSize: 13))),
        pw.SizedBox(height: 18),
        pw.Table.fromTextArray(
          headers: ['विवरण', 'रकम'],
          data: rows,
          headerStyle: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
          cellStyle: pw.TextStyle(font: font, fontSize: 10),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          cellAlignment: pw.Alignment.centerLeft,
          cellPadding: const pw.EdgeInsets.all(7),
        ),
        pw.SizedBox(height: 10),
        pw.Text('नोट: बीमा कोषको रकम बचत कोषको नाफा/नोक्सानमा मिसाइएको छैन। साँवा ऋण फिर्ता आम्दानीमा गणना गरिएको छैन; ऋण ब्याज मात्र आम्दानी हो।', style: pw.TextStyle(font: font, fontSize: 9)),
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  @override
  void initState() {
    super.initState();
    _reportFuture = _loadReport();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('मासिक प्रतिवेदन'),
        backgroundColor: const Color(0xFF101B3A),
        foregroundColor: const Color(0xFFE8C56A),
        actions: [
          IconButton(
            tooltip: 'फेरि लोड गर्नुहोस्',
            onPressed: () => setState(() => _reportFuture = _loadReport()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('मासिक प्रतिवेदन लोड हुन सकेन: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final months = data['months'] as List<String>;
          final month = data['selectedMonth'] as String?;
          final totals = Map<String, double>.from(data['totals'] as Map);
          if (months.isEmpty || month == null) {
            return const Center(child: Text('अहिलेसम्म मासिक प्रतिवेदनका लागि वित्तीय कारोबार छैन।'));
          }
          final generalNet = _generalNet(totals);
          final insuranceNet = _insuranceNet(totals);
          final totalIncome = totals['memberSavings']! + totals['insuranceContributions']! +
              totals['savingsPenalties']! + totals['insurancePenalties']! +
              totals['savingsDonation']! + totals['insuranceDonation']! +
              totals['savingsOtherIncome']! + totals['insuranceOtherIncome']! +
              totals['generalBankInterest']! + totals['insuranceBankInterest']! +
              totals['memberInterest']!;
          final totalExpenses = totals['generalExpenses']! + totals['insuranceExpenses']!;
          final totalOtherIncome = totals['savingsDonation']! + totals['insuranceDonation']! +
              totals['savingsOtherIncome']! + totals['insuranceOtherIncome']!;
          final totalInterest = totals['generalBankInterest']! +
              totals['insuranceBankInterest']! + totals['memberInterest']!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                value: month,
                decoration: const InputDecoration(labelText: 'नेपाली महिना छान्नुहोस्', border: OutlineInputBorder()),
                items: months.map((m) => DropdownMenuItem(value: m, child: Text(_monthLabel(m)))).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedMonth = value;
                    _reportFuture = _loadReport();
                  });
                },
              ),
              const SizedBox(height: 14),
              Card(
                color: const Color(0xFFE8EEF8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_monthLabel(month), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 5),
                    const Text('सबै कारोबार नेपाली महिनाअनुसार छुट्याइएको छ। बचत र बीमा कोषको हिसाब अलग राखिएको छ।'),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                _row('सदस्यहरूको मासिक बचत', totals['memberSavings']!),
                _row('बचत कोष जरिमाना', totals['savingsPenalties']!),
                _row('बीमा योगदान', totals['insuranceContributions']!),
                _row('बीमा जरिमाना', totals['insurancePenalties']!),
                const Divider(),
                _row('दान — बचत कोष', totals['savingsDonation']!),
                _row('दान — बीमा कोष', totals['insuranceDonation']!),
                _row('अन्य आम्दानी — बचत कोष', totals['savingsOtherIncome']!),
                _row('अन्य आम्दानी — बीमा कोष', totals['insuranceOtherIncome']!),
                _row('कुल अन्य आम्दानी (दानसहित)', totalOtherIncome, bold: true),
                const Divider(),
                _row('बैंक ब्याज — बचत कोष', totals['generalBankInterest']!),
                _row('बैंक ब्याज — बीमा कोष', totals['insuranceBankInterest']!),
                _row('ऋणबाट प्राप्त ब्याज', totals['memberInterest']!),
                _row('कुल ब्याज आम्दानी', totalInterest, bold: true),
                const Divider(),
                _row('कुल आम्दानी', totalIncome, bold: true),
                _row('खर्च — बचत कोष', totals['generalExpenses']!, color: Colors.red),
                _row('खर्च — बीमा कोष', totals['insuranceExpenses']!, color: Colors.red),
                _row('कुल खर्च', totalExpenses, color: Colors.red, bold: true),
              ]))),
              const SizedBox(height: 10),
              _resultCard('बचत कोषको खुद नाफा / नोक्सान', generalNet),
              const SizedBox(height: 10),
              _resultCard('बीमा कोषको खुद परिवर्तन (अलग)', insuranceNet),
              const SizedBox(height: 14),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => _exportPdf(month, totals),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('मासिक PDF प्रतिवेदन निकाल्नुहोस्'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, num value, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          Text(_money(value), style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.bold, color: color)),
        ]),
      );

  Widget _resultCard(String title, double value) {
    final positive = value > 0;
    final negative = value < 0;
    final color = negative
        ? Colors.red
        : positive
            ? const Color(0xFF167D46)
            : Colors.blueGrey;
    return Card(
      color: negative
          ? const Color(0xFFFFEBEE)
          : positive
              ? const Color(0xFFE8F5E9)
              : const Color(0xFFF1F3F5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 7),
          Text(_money(value.abs()), style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: color)),
          Text(positive ? 'सकारात्मक' : negative ? 'नकारात्मक' : 'शून्य'),
        ]),
      ),
    );
  }
}
