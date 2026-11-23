import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'nepali_digits.dart';

class InsuranceHistoryPage extends StatelessWidget {
  final String uid;
  const InsuranceHistoryPage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('बीमा इतिहास')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Text('बीमा दाबीको इतिहास', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('insurance_claims').where('uid', isEqualTo: uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('बीमा इतिहास लोड गर्न सकिएन।');
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = [...snapshot.data!.docs]..sort((a, b) => _time(b.data()).compareTo(_time(a.data())));
            if (docs.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('हालसम्म कुनै बीमा दाबी रेकर्ड छैन।')));
            return Column(children: docs.map((doc) {
              final d = doc.data();
              final amount = d['approvedAmount'] ?? d['insuranceAmount'] ?? 0;
              final status = _status(d['status']?.toString() ?? 'pending');
              return Card(child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined, color: Colors.teal),
                title: Text(d['claimantName']?.toString() ?? d['memberName']?.toString() ?? 'दाबीकर्ता'),
                subtitle: Text('${toNepaliDigits(d['applicationDateBS'] ?? 'मिति छैन')}  •  $status\nस्वीकृत/दाबी रकम: रु. $amount'),
                isThreeLine: true,
              ));
            }).toList());
          },
        ),
        const SizedBox(height: 20),
        const Text('बीमा भुक्तानी इतिहास', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('insurance_claim_payments').where('uid', isEqualTo: uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('भुक्तानी इतिहास लोड गर्न सकिएन।');
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = [...snapshot.data!.docs]..sort((a, b) => _time(b.data()).compareTo(_time(a.data())));
            if (docs.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('हालसम्म बीमा रकम भुक्तानी भएको रेकर्ड छैन।')));
            return Column(children: docs.map((doc) {
              final d = doc.data();
              return Card(child: ListTile(
                leading: const Icon(Icons.payments_outlined, color: Colors.green),
                title: Text('रु. ${d['amount'] ?? 0}'),
                subtitle: Text('दाबीकर्ता: ${d['claimantName'] ?? d['memberName'] ?? '—'}\nभुक्तानी मिति: ${toNepaliDigits(d['bsDate'] ?? '—')}'),
                isThreeLine: true,
              ));
            }).toList());
          },
        ),
      ]),
    );
  }

  static int _time(Map<String, dynamic> data) {
    final value = data['createdAt'];
    return value is Timestamp ? value.millisecondsSinceEpoch : 0;
  }
  static String _status(String value) {
    switch (value) { case 'pending': return 'विचाराधीन'; case 'approved': return 'स्वीकृत'; case 'rejected': return 'अस्वीकृत'; default: return value; }
  }
}
