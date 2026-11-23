import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'nepali_digits.dart';

class InsuranceTrackingPage extends StatelessWidget {
  final String uid;
  const InsuranceTrackingPage({super.key, required this.uid});

  String _status(String value) {
    switch (value) {
      case 'pending': return 'समीक्षाको क्रममा';
      case 'approved': return 'स्वीकृत';
      case 'rejected': return 'अस्वीकृत';
      default: return value.isEmpty ? 'अवस्था उपलब्ध छैन' : value;
    }
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      default: return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('बीमा आवेदन ट्र्याकिङ')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('insurance_claims')
            .where('uid', isEqualTo: uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('बीमा आवेदन लोड गर्न सकिएन।'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = [...?snapshot.data?.docs];
          docs.sort((a, b) => _time(b.data()).compareTo(_time(a.data())));
          if (docs.isEmpty) return const Center(child: Text('तपाईंको कुनै बीमा आवेदन भेटिएन।'));
          return ListView.builder(
            padding: const EdgeInsets.all(12), itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final status = data['status']?.toString() ?? 'pending';
              final paymentStatus = data['paymentStatus']?.toString() ?? 'unpaid';
              final approved = _amount(data['approvedAmount'] ?? data['insuranceAmount']);
              final paid = _amount(data['paidAmount']);
              final remaining = _amount(data['remainingAmount'] ?? (approved - paid));
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: Icon(Icons.health_and_safety, color: _statusColor(status)),
                  title: Text(data['claimantName']?.toString() ?? data['memberName']?.toString() ?? 'दाबीकर्ता'),
                  subtitle: Text('आवेदन मिति: ${toNepaliDigits(data['applicationDateBS'] ?? 'उपलब्ध छैन')}\n${_status(status)}'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _line('उपचार खर्च', 'रु. ${data['expenseAmount'] ?? 0}'),
                    _line('दाबी गरिएको बीमा रकम', 'रु. ${data['insuranceAmount'] ?? 0}'),
                    _line('स्वीकृत रकम', 'रु. ${approved.toStringAsFixed(2)}'),
                    _line('भुक्तानी भएको', 'रु. ${paid.toStringAsFixed(2)}'),
                    _line('बाँकी भुक्तानी', 'रु. ${remaining.toStringAsFixed(2)}'),
                    _line('भुक्तानी अवस्था', _paymentLabel(paymentStatus)),
                    if ((data['reason'] ?? '').toString().isNotEmpty) _line('कारण', data['reason'].toString()),
                    if ((data['details'] ?? '').toString().isNotEmpty) _line('विवरण', data['details'].toString()),
                    if (data['rejectionReason'] != null) _line('अस्वीकृतिको कारण', data['rejectionReason'].toString()),
                    if (data['photoUrls'] is List && (data['photoUrls'] as List).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Align(alignment: Alignment.centerLeft, child: Text('पेश गरिएका प्रमाण', style: TextStyle(fontWeight: FontWeight.bold))),
                      Wrap(spacing: 8, children: (data['photoUrls'] as List).map((url) => GestureDetector(
                        onTap: () => showDialog(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url.toString())))),
                        child: Image.network(url.toString(), width: 70, height: 70, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                      )).toList()),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  static int _time(Map<String, dynamic> data) {
    final value = data['createdAt'];
    return value is Timestamp ? value.millisecondsSinceEpoch : 0;
  }
  static double _amount(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  static String _paymentLabel(String value) {
    switch (value) { case 'paid': return 'पूरा भुक्तानी'; case 'partial': return 'आंशिक भुक्तानी'; default: return 'भुक्तानी हुन बाँकी'; }
  }
  static Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 145, child: Text(label)), Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)))]),
  );
}
