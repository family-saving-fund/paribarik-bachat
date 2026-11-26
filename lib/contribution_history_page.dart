import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'nepali_digits.dart';

class ContributionHistoryPage extends StatelessWidget {
  const ContributionHistoryPage({
    super.key,
    required this.fundType,
    this.memberUid,
    this.memberName,
    this.showAllMembers = false,
    this.fundBalance,
    this.fundBalanceLabel,
  });

  final String fundType; // savings | insurance
  final String? memberUid;
  final String? memberName;
  final bool showAllMembers;
  final num? fundBalance;
  final String? fundBalanceLabel;

  static const _months = <String>[
    'बैशाख',
    'जेठ',
    'असार',
    'साउन',
    'भदौ',
    'असोज',
    'कार्तिक',
    'मंसिर',
    'पुष',
    'माघ',
    'फागुन',
    'चैत',
  ];

  String _monthLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return toNepaliDigits(key);
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return toNepaliDigits(key);
    }
    return '${toNepaliDigits(year.toString())} ${_months[month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final isSavings = fundType == 'savings';
    final field = isSavings ? 'savingsPaid' : 'insurancePaid';
    final title = isSavings ? 'कुल बचत विवरण' : 'कुल बिमा विवरण';
    final query = FirebaseFirestore.instance.collection('monthly_savings');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF101B3A),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: showAllMembers || memberUid == null
            ? query.snapshots()
            : query.where('memberUid', isEqualTo: memberUid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('महिनावार विवरण लोड हुन सकेन।'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final totals = <String, int>{};
          for (final doc in snapshot.data!.docs) {
            final data = doc.data();
            if (data['isTest'] == true) continue;
            final key = data['monthKey']?.toString() ?? '';
            if (key.isEmpty) continue;
            final amount = (data[field] as num?)?.toInt() ?? 0;
            totals[key] = (totals[key] ?? 0) + amount;
          }

          final entries = totals.entries.toList()
            ..sort((a, b) {
              final aParts = a.key.split('-');
              final bParts = b.key.split('-');
              final aOrder = aParts.length == 2
                  ? (int.tryParse(aParts[0]) ?? 0) * 12 +
                      (int.tryParse(aParts[1]) ?? 0)
                  : 0;
              final bOrder = bParts.length == 2
                  ? (int.tryParse(bParts[0]) ?? 0) * 12 +
                      (int.tryParse(bParts[1]) ?? 0)
                  : 0;
              return aOrder.compareTo(bOrder);
            });
          final total = entries.fold<int>(0, (sum, item) => sum + item.value);
          final filtered = entries.where((entry) => entry.value > 0).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: isSavings
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFE8F1FB),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        showAllMembers ? 'संस्थाको $title' : (memberName ?? title),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'महिनावार जम्मा: रु. ${toNepaliDigits(total.toString())}',
                        style: TextStyle(
                          color: isSavings
                              ? const Color(0xFF167D46)
                              : const Color(0xFF2469B3),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (fundBalance != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          '${fundBalanceLabel ?? 'कोषको मौज्दात'}: रु. ${toNepaliDigits(fundBalance!.round().toString())}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('अहिलेसम्म कुनै रकम जम्मा भएको छैन।')),
                )
              else
                ...filtered.map((entry) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSavings
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFE8F1FB),
                          child: Icon(
                            isSavings
                                ? Icons.savings_outlined
                                : Icons.health_and_safety_outlined,
                            color: isSavings
                                ? const Color(0xFF167D46)
                                : const Color(0xFF2469B3),
                          ),
                        ),
                        title: Text(
                          _monthLabel(entry.key),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: Text(
                          'रु. ${toNepaliDigits(entry.value.toString())}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}
