import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'fund_service.dart';
import 'financial_report_page.dart';
import 'nepali_digits.dart';

String _reportMonthLabel(String key) {
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

class AdminFinancialAccountsPage extends StatefulWidget {
  const AdminFinancialAccountsPage({super.key});

  @override
  State<AdminFinancialAccountsPage> createState() =>
      _AdminFinancialAccountsPageState();
}

class _AdminFinancialAccountsPageState
    extends State<AdminFinancialAccountsPage> {
  late Future<Map<String, num>> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = _loadReport();
  }

  double _amount(dynamic value) => value is num ? value.toDouble() : 0;

  Future<Map<String, num>> _loadReport() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('monthly_savings').get(),
      db.collection('fund_transactions').get(),
      db.collection('bank_interest_transactions').get(),
      db.collection('loan_installments').where('status', isEqualTo: 'approved').get(),
    ]);

    var memberSavings = 0.0;
    var savingsPenalties = 0.0;
    for (final doc in (results[0] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final data = doc.data();
      if (data['isTest'] == true) continue;
      memberSavings += _amount(data['savingsPaid']);
      savingsPenalties += _amount(data['normalSavingsPenaltyPaid']);
      savingsPenalties += _amount(data['specialSavingsPenaltyPaid']);
    }

    var savingsOtherIncome = 0.0;
    var insuranceOtherIncome = 0.0;
    var generalExpenses = 0.0;
    var insuranceExpenses = 0.0;
    for (final doc in (results[1] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final data = doc.data();
      if (data['isTest'] == true) continue;
      final amount = _amount(data['amount']);
      final fundType = data['fundType']?.toString() ?? '';
      final category = data['category']?.toString() ?? '';
      if (category == 'donation' ||
          (category == 'other_income' && data['status'] == 'approved')) {
        if (fundType == 'savings') savingsOtherIncome += amount;
        if (fundType == 'insurance') insuranceOtherIncome += amount;
      }
      if (fundType == 'expense' && data['status'] == 'disbursed') {
        if (category == 'insurance_claim_payout') {
          insuranceExpenses += amount;
        } else {
          generalExpenses += amount;
        }
      }
    }

    var generalBankInterest = 0.0;
    var insuranceBankInterest = 0.0;
    for (final doc in (results[2] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final data = doc.data();
      if (data['isInstitutionIncome'] == false || data['isTest'] == true) continue;
      final amount = _amount(data['amount']);
      if (data['fundType'] == 'general') generalBankInterest += amount;
      if (data['fundType'] == 'insurance') insuranceBankInterest += amount;
    }

    var memberInterest = 0.0;
    for (final doc in (results[3] as QuerySnapshot<Map<String, dynamic>>).docs) {
      final data = doc.data();
      if (data['isTest'] == true) continue;
      memberInterest += _amount(data['interestPaid']);
    }

    final insuranceBalance = await FundService().calculateInsuranceFundBalance();
    final totalOtherIncome = savingsOtherIncome + insuranceOtherIncome;
    final totalInterest = generalBankInterest + insuranceBankInterest + memberInterest;
    final totalExpenses = generalExpenses + insuranceExpenses;
    // बीमा कोषको आम्दानी, ब्याज र खर्चलाई बचत कोषको नाफा/नोक्सानमा मिसाइएको छैन।
    final profitLoss = memberSavings + savingsPenalties + savingsOtherIncome +
        generalBankInterest + memberInterest - generalExpenses;

    return {
      'memberSavings': memberSavings,
      'insuranceBalance': insuranceBalance,
      'savingsOtherIncome': savingsOtherIncome,
      'insuranceOtherIncome': insuranceOtherIncome,
      'totalOtherIncome': totalOtherIncome,
      'generalBankInterest': generalBankInterest,
      'insuranceBankInterest': insuranceBankInterest,
      'memberInterest': memberInterest,
      'totalInterest': totalInterest,
      'savingsPenalties': savingsPenalties,
      'generalExpenses': generalExpenses,
      'insuranceExpenses': insuranceExpenses,
      'totalExpenses': totalExpenses,
      'profitLoss': profitLoss,
    };
  }

  String _money(num value) => 'रु. ${toNepaliDigits(value.round().toString())}';

  Widget _row(String label, num value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
          ),
          Text(
            _money(value),
            style: TextStyle(
              color: color ?? const Color(0xFF263238),
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('आर्थिक हिसाब'),
        backgroundColor: const Color(0xFF101B3A),
        foregroundColor: const Color(0xFFE8C56A),
        actions: [
          IconButton(
            tooltip: 'फेरि हिसाब गर्नुहोस्',
            onPressed: () => setState(() => _reportFuture = _loadReport()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, num>>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('आर्थिक हिसाब लोड हुन सकेन: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final profit = data['profitLoss'] ?? 0;
          final isProfit = profit >= 0;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(0xFFE8EEF8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('कोषको आर्थिक अवस्था', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      const SizedBox(height: 6),
                      const Text('बीमा कोषलाई बचत कोषको नाफा/नोक्सानबाट अलग राखिएको छ।'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _row('सदस्यहरूको कुल मासिक बचत', data['memberSavings'] ?? 0),
                      const Divider(height: 1),
                      _row('कुल बीमा कोष मौज्दात', data['insuranceBalance'] ?? 0, color: const Color(0xFF2469B3)),
                      const Divider(height: 1),
                      _row('अन्य आम्दानी — बचत कोष', data['savingsOtherIncome'] ?? 0),
                      _row('अन्य आम्दानी — बीमा कोष', data['insuranceOtherIncome'] ?? 0),
                      _row('कुल अन्य आम्दानी (दानसहित)', data['totalOtherIncome'] ?? 0, bold: true),
                      const Divider(height: 1),
                      _row('बैंक ब्याज — बचत कोष', data['generalBankInterest'] ?? 0),
                      _row('बैंक ब्याज — बीमा कोष', data['insuranceBankInterest'] ?? 0),
                      _row('सदस्यबाट प्राप्त ऋण ब्याज', data['memberInterest'] ?? 0),
                      _row('कुल ब्याज आम्दानी', data['totalInterest'] ?? 0, bold: true),
                      const Divider(height: 1),
                      _row('बचत कोष जरिमाना आम्दानी', data['savingsPenalties'] ?? 0),
                      _row('बचत कोष खर्च', data['generalExpenses'] ?? 0, color: Colors.red),
                      _row('बीमा कोष खर्च / दाबी भुक्तानी', data['insuranceExpenses'] ?? 0, color: Colors.red),
                      _row('कुल कोष खर्च', data['totalExpenses'] ?? 0, color: Colors.red, bold: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: isProfit ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isProfit ? 'बचत कोषको नाफा' : 'बचत कोषको नोक्सान', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      const SizedBox(height: 8),
                      Text(
                        _money(profit.abs()),
                        style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: isProfit ? const Color(0xFF167D46) : Colors.red),
                      ),
                      const SizedBox(height: 6),
                      const Text('सूत्र: सदस्य बचत + बचततर्फको अन्य आम्दानी + बचततर्फको ब्याज + सदस्य ब्याज + बचत जरिमाना − बचत कोष खर्च। बीमा कोष यसमा समावेश छैन।'),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MemberReportsPage extends StatefulWidget {
  const MemberReportsPage({super.key});

  @override
  State<MemberReportsPage> createState() => _MemberReportsPageState();
}

class _MemberReportsPageState extends State<MemberReportsPage> {
  String? _selectedUid;
  bool _saving = false;

  int _monthOrder(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 12 + (int.tryParse(parts[1]) ?? 0);
  }

  Future<void> _saveReport({
    required String uid,
    required String name,
    required List<Map<String, dynamic>> months,
    required int savings,
    required int insurance,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Admin login भेटिएन।');
      final admin = await db.collection('member').doc(user.uid).get();
      final adminName = admin.data()?['name']?.toString() ?? 'Admin';
      final reportRef = db.collection('member_report_history').doc();
      final auditRef = db.collection('admin_audit_logs').doc('member_report_${reportRef.id}');
      final batch = db.batch();
      batch.set(reportRef, {
        'memberUid': uid,
        'memberName': name,
        'totalSavings': savings,
        'totalInsurance': insurance,
        'months': months,
        'monthCount': months.length,
        'generatedByUid': user.uid,
        'generatedByName': adminName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(auditRef, {
        'eventId': auditRef.id,
        'adminUid': user.uid,
        'adminName': adminName,
        'action': 'member_report_generated',
        'targetCollection': 'member_report_history',
        'targetDocumentId': reportRef.id,
        'description': '$name को सदस्यगत प्रतिवेदन तयार गरियो।',
        'memberUid': uid,
        'memberName': name,
        'amount': savings + insurance,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('सदस्य प्रतिवेदन इतिहासमा सुरक्षित भयो।'), backgroundColor: Colors.green),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('प्रतिवेदन सुरक्षित हुन सकेन: $error'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('सदस्यगत प्रतिवेदन'), backgroundColor: const Color(0xFF101B3A), foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('member').snapshots(),
        builder: (context, membersSnapshot) {
          if (membersSnapshot.hasError) return const Center(child: Text('सदस्य सूची लोड भएन।'));
          if (!membersSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          final members = membersSnapshot.data!.docs;
          if (members.isEmpty) return const Center(child: Text('सदस्य भेटिएनन्।'));
          var selected = members.first;
          for (final member in members) {
            if (member.id == _selectedUid) {
              selected = member;
              break;
            }
          }
          if (_selectedUid != selected.id) _selectedUid = selected.id;
          final selectedName = selected.data()['name']?.toString() ?? 'नाम छैन';
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  value: selected.id,
                  decoration: const InputDecoration(labelText: 'सदस्य छान्नुहोस्', border: OutlineInputBorder()),
                  items: members.map((doc) => DropdownMenuItem(value: doc.id, child: Text(doc.data()['name']?.toString() ?? 'नाम छैन'))).toList(),
                  onChanged: (value) => setState(() => _selectedUid = value),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  key: ValueKey(selected.id),
                  stream: db.collection('monthly_savings').where('memberUid', isEqualTo: selected.id).snapshots(),
                  builder: (context, recordsSnapshot) {
                    if (recordsSnapshot.hasError) return const Center(child: Text('सदस्यको विवरण लोड भएन।'));
                    if (!recordsSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final months = <String, Map<String, int>>{};
                    for (final doc in recordsSnapshot.data!.docs) {
                      final data = doc.data();
                      if (data['isTest'] == true) continue;
                      final key = data['monthKey']?.toString() ?? '';
                      if (key.isEmpty) continue;
                      final row = months.putIfAbsent(key, () => {'savings': 0, 'insurance': 0});
                      row['savings'] = row['savings']! + ((data['savingsPaid'] as num?)?.toInt() ?? 0);
                      row['insurance'] = row['insurance']! + ((data['insurancePaid'] as num?)?.toInt() ?? 0);
                    }
                    final keys = months.keys.toList()..sort((a, b) => _monthOrder(a).compareTo(_monthOrder(b)));
                    final monthData = keys.map((key) => <String, dynamic>{'monthKey': key, 'savings': months[key]!['savings'], 'insurance': months[key]!['insurance']}).toList();
                    final savings = monthData.fold<int>(0, (sum, row) => sum + (row['savings'] as int));
                    final insurance = monthData.fold<int>(0, (sum, row) => sum + (row['insurance'] as int));
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Card(color: const Color(0xFFE8EEF8), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(selectedName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), const SizedBox(height: 8), Text('कुल बचत: रु. ${toNepaliDigits(savings.toString())}'), Text('कुल बीमा: रु. ${toNepaliDigits(insurance.toString())}')]))),
                        const SizedBox(height: 8),
                        if (monthData.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('मासिक विवरण भेटिएन।'))),
                        ...monthData.map((row) => Card(child: ListTile(title: Text(_reportMonthLabel(row['monthKey'] as String)), subtitle: Text('बचत: रु. ${toNepaliDigits((row['savings'] as int).toString())}'), trailing: Text('बीमा: रु. ${toNepaliDigits((row['insurance'] as int).toString())}')))),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FinancialReportPage(
                                memberUid: selected.id,
                                memberName: selectedName,
                                role: 'member',
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('विस्तृत सदस्य वित्तीय प्रतिवेदन'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _saving || monthData.isEmpty ? null : () => _saveReport(uid: selected.id, name: selectedName, months: monthData, savings: savings, insurance: insurance),
                          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'सुरक्षित हुँदैछ...' : 'प्रतिवेदन इतिहासमा सुरक्षित गर्नुहोस्'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MemberReportHistoryPage extends StatelessWidget {
  const MemberReportHistoryPage({super.key});

  String _date(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return toNepaliDigits('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');
    }
    return 'मिति उपलब्ध छैन';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('सदस्य प्रतिवेदन इतिहास'), backgroundColor: const Color(0xFF101B3A), foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('member_report_history').orderBy('createdAt', descending: true).limit(200).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('प्रतिवेदन इतिहास लोड हुन सकेन।'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return const Center(child: Text('अहिलेसम्म कुनै प्रतिवेदन सुरक्षित गरिएको छैन।'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data();
              final months = (data['months'] as List?) ?? const [];
              return Card(
                child: ExpansionTile(
                  leading: const CircleAvatar(child: Icon(Icons.history)),
                  title: Text(data['memberName']?.toString() ?? 'सदस्य', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('तयार मिति: ${_date(data['createdAt'])}  •  ${months.length} महिना'),
                  children: [
                    ListTile(title: const Text('कुल बचत'), trailing: Text('रु. ${toNepaliDigits((data['totalSavings'] ?? 0).toString())}')),
                    ListTile(title: const Text('कुल बीमा'), trailing: Text('रु. ${toNepaliDigits((data['totalInsurance'] ?? 0).toString())}')),
                    ...months.map((raw) {
                      final row = Map<String, dynamic>.from(raw as Map);
                      return ListTile(
                        dense: true,
                        title: Text(_reportMonthLabel(row['monthKey']?.toString() ?? '')),
                        subtitle: Text('बचत: रु. ${toNepaliDigits((row['savings'] ?? 0).toString())}'),
                        trailing: Text('बीमा: रु. ${toNepaliDigits((row['insurance'] ?? 0).toString())}'),
                      );
                    }),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AdminAuditHistoryPage extends StatelessWidget {
  const AdminAuditHistoryPage({super.key});

  String _date(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      return toNepaliDigits('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}');
    }
    return 'मिति उपलब्ध छैन';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Audit History'), backgroundColor: const Color(0xFF101B3A), foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('admin_audit_logs').orderBy('createdAt', descending: true).limit(300).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Audit history लोड हुन सकेन।'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return const Center(child: Text('अहिलेसम्म कुनै Admin गतिविधि छैन।'));
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final data = snapshot.data!.docs[index].data();
              final amount = data['amount'];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Color(0xFFE8EEF8), child: Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF173B66))),
                  title: Text(data['description']?.toString() ?? data['action']?.toString() ?? 'Admin गतिविधि', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Admin: ${data['adminName'] ?? data['adminUid'] ?? '-'}\nमिति: ${_date(data['createdAt'])}\nलक्ष्य: ${data['targetCollection'] ?? '-'} / ${data['targetDocumentId'] ?? '-'}'),
                  isThreeLine: true,
                  trailing: amount is num ? Text('रु. ${toNepaliDigits(amount.toString())}', style: const TextStyle(fontWeight: FontWeight.bold)) : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
