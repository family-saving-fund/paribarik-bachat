
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'penalty_service.dart';

class PenaltyManagementPage extends StatefulWidget {
  const PenaltyManagementPage({super.key});

  @override
  State<PenaltyManagementPage> createState() =>
      _PenaltyManagementPageState();
}

class _PenaltyManagementPageState
    extends State<PenaltyManagementPage> {
  static const Color navy = Color(0xFF08254A);
  static const Color gold = Color(0xFFE8B943);

  final PenaltyService _service = PenaltyService();

  Future<void> _refresh() async {
    if (mounted) setState(() {});
  }

  Future<void> _showWaiverDialog({
    required String memberUid,
    required String memberName,
    required String monthKey,
    required int availablePenalty,
  }) async {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$memberName — जरिमाना माफी'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('महिना: $monthKey'),
              Text('माफी गर्न बाँकी: रु. $availablePenalty'),
              const SizedBox(height: 14),
              TextFormField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'माफी रकम (रु.)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final amount =
                      int.tryParse(value?.trim() ?? '');

                  if (amount == null || amount <= 0) {
                    return 'सही रकम लेख्नुहोस्।';
                  }

                  if (amount > availablePenalty) {
                    return 'बाँकी जरिमानाभन्दा बढी भयो।';
                  }

                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'माफी दिनुको कारण',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'माफीको कारण लेख्नुहोस्।';
                  }

                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('रद्द'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('माफी सुरक्षित गर्नुहोस्'),
          ),
        ],
      ),
    );

    if (result != true) {
      amountController.dispose();
      reasonController.dispose();
      return;
    }

    try {
      await _service.createPenaltyWaiver(
        memberUid: memberUid,
        monthKey: monthKey,
        waivedAmount:
            int.parse(amountController.text.trim()),
        reason: reasonController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('जरिमाना माफी सुरक्षित भयो।'),
          backgroundColor: Colors.green,
        ),
      );

      await _refresh();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('माफी सुरक्षित गर्न असफल: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      amountController.dispose();
      reasonController.dispose();
    }
  }

  Widget _buildMemberCard(
    QueryDocumentSnapshot<Map<String, dynamic>> member,
  ) {
    final memberData = member.data();
    final memberName =
        memberData['name']?.toString() ?? 'नाम छैन';

    return FutureBuilder<Map<String, dynamic>>(
      future: _service.calculateMemberPenalty(
        memberUid: member.id,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return Card(
            child: ListTile(
              title: Text(memberName),
              subtitle: const LinearProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              title: Text(memberName),
              subtitle: Text(
                'हिसाब प्राप्त गर्न असफल: ${snapshot.error}',
              ),
            ),
          );
        }

        final data = snapshot.data ?? {};

        final remaining =
            (data['remainingAmount'] as num?)?.toInt() ?? 0;
        final overdue =
            (data['overdueAmount'] as num?)?.toInt() ?? 0;
        final penalty =
            (data['penaltyAmount'] as num?)?.toInt() ?? 0;
        final waived =
            (data['waivedAmount'] as num?)?.toInt() ?? 0;
        final payable =
            (data['totalPayable'] as num?)?.toInt() ?? 0;

        final grossByMonth =
            Map<String, int>.from(
          data['penaltyByMonth'] ?? {},
        );

        final netByMonth =
            Map<String, int>.from(
          data['netPenaltyByMonth'] ?? {},
        );

        final detailsByMonth =
            Map<String, dynamic>.from(
          data['penaltyDetailsByMonth'] ?? {},
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ExpansionTile(
            leading: const CircleAvatar(
              backgroundColor: navy,
              child: Icon(Icons.person, color: gold),
            ),
            title: Text(
              memberName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'बाँकी जरिमाना: रु. $penalty',
              style: TextStyle(
                color: penalty > 0
                    ? Colors.red
                    : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            childrenPadding:
                const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _summaryRow('कुल बाँकी भुक्तानी', remaining),
              _summaryRow('जरिमाना लागिसकेको रकम', overdue),
              _summaryRow('कुल जरिमाना', penalty),
              _summaryRow('पहिले माफी भएको रकम', waived),
              const Divider(),
              _summaryRow(
                'जम्मा तिर्नुपर्ने',
                payable,
                bold: true,
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'महिनाअनुसार जरिमाना',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              if (grossByMonth.isEmpty)
                const Text('हाल कुनै जरिमाना लागेको छैन।')
              else
                ...grossByMonth.entries.map((entry) {
                  final monthKey = entry.key;
                  final gross = entry.value;
                  final net = netByMonth[monthKey] ?? 0;

                  final details =
                      Map<String, dynamic>.from(
                    detailsByMonth[monthKey] ?? {},
                  );

                  final specialBase =
                      (details['specialPenaltyBase'] as num?)
                              ?.toInt() ??
                          0;

                  final specialTotal =
                      (details['specialPenaltyTotal'] as num?)
                              ?.toInt() ??
                          0;

                  final specialPaid =
                      (details['specialPenaltyPaid'] as num?)
                              ?.toInt() ??
                          0;

                  final isSpecial =
                      details['isSpecial50Percent'] == true;

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      monthKey,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      isSpecial
                          ? '५०% आधार साँवा: रु. $specialBase\n'
                              'कुल विशेष जरिमाना: रु. $specialTotal\n'
                              'पहिले तिरेको: रु. $specialPaid\n'
                              'माफीपछि बाँकी: रु. $net'
                          : 'जरिमाना: रु. $gross  |  माफीपछि: रु. $net',
                      style: const TextStyle(
                        color: Colors.red,
                      ),
                    ),
                    trailing: net > 0
                        ? IconButton(
                            tooltip: 'जरिमाना माफी',
                            icon: const Icon(
                              Icons.edit_note,
                              color: Colors.orange,
                              size: 28,
                            ),
                            onPressed: () =>
                                _showWaiverDialog(
                              memberUid: member.id,
                              memberName: memberName,
                              monthKey: monthKey,
                              availablePenalty: net,
                            ),
                          )
                        : const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                  );
                }),

              const Divider(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'जरिमाना माफी इतिहास',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              StreamBuilder<
                  QuerySnapshot<Map<String, dynamic>>>(
                stream:
                    _service.watchMemberWaivers(member.id),
                builder: (context, waiverSnapshot) {
                  if (waiverSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (waiverSnapshot.hasError) {
                    return Text(
                      'इतिहास खोल्न असफल: '
                      '${waiverSnapshot.error}',
                    );
                  }

                  final docs =
                      waiverSnapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'अहिलेसम्म माफी इतिहास छैन।',
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final waiver = doc.data();

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.history,
                          color: Colors.orange,
                        ),
                        title: Text(
                          '${waiver['monthKey'] ?? ''} — '
                          'रु. ${waiver['waivedAmount'] ?? 0}',
                        ),
                        subtitle: Text(
                          waiver['reason']?.toString() ?? '',
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summaryRow(
    String label,
    int amount, {
    bool bold = false,
  }) {
    final bool isWaiver = label.contains('माफी');

    final Color amountColor =
        (isWaiver || amount == 0)
            ? Colors.green
            : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight:
                  bold ? FontWeight.bold : FontWeight.normal,
              color: Colors.white,
            ),
          ),
          Text(
            'रु. $amount',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: amountColor,
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
        title: const Text('जरिमाना व्यवस्थापन'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF4F5F9),
      body: StreamBuilder<
          QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('member')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'सदस्य सूची खोल्न असफल: ${snapshot.error}',
              ),
            );
          }

          // Admin पनि नियमित सदस्य भएकाले
          // जरिमाना सूचीमा समावेश हुन्छन्।
          final members =
              (snapshot.data?.docs ?? []).toList()
                ..sort(
                  (a, b) =>
                      (a.data()['name'] ?? '')
                          .toString()
                          .compareTo(
                            (b.data()['name'] ?? '')
                                .toString(),
                          ),
                );

          if (members.isEmpty) {
            return const Center(
              child: Text('सदस्यको विवरण भेटिएन।'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'सदस्यअनुसार जरिमाना विवरण',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              ...members.map(_buildMemberCard),
            ],
          );
        },
      ),
    );
  }
}
