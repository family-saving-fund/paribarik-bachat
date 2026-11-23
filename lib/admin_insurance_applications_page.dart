
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'insurance_annual_limit_service.dart';
import 'nepali_digits.dart';

class AdminInsuranceApplicationsPage extends StatelessWidget {
  const AdminInsuranceApplicationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('बीमा आवेदनहरू'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('insurance_claims')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('आवेदन लोड गर्न समस्या भयो।'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final applications = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['status'] == 'pending';
          }).toList();

          applications.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;

            final aDate = aData['createdAt'] as Timestamp?;
            final bDate = bData['createdAt'] as Timestamp?;

            return (bDate?.millisecondsSinceEpoch ?? 0)
                .compareTo(aDate?.millisecondsSinceEpoch ?? 0);
          });

          if (applications.isEmpty) {
            return const Center(
              child: Text('हाल कुनै नयाँ बीमा आवेदन छैन।'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: applications.length,
            itemBuilder: (context, index) {
              final doc = applications[index];
              final data = doc.data() as Map<String, dynamic>;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['memberName']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'दाबी गर्ने: ${data['claimantName'] ?? ''}',
                      ),
                      Text(
                        'आवेदन मिति: ${toNepaliDigits(data['applicationDateBS'] ?? '')}',
                      ),
                      Text(
                        'उपचार खर्च: रु. ${data['expenseAmount'] ?? 0}',
                      ),
                      Text(
                        'बीमा रकम: रु. ${data['insuranceAmount'] ?? 0}',
                      ),
                      const SizedBox(height: 8),
                      Text('कारण: ${data['reason'] ?? ''}'),
                      Text('विवरण: ${data['details'] ?? ''}'),
                      const SizedBox(height: 10),
                      const Text(
                        'बिल तथा प्रमाणहरू:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      if (data['photoUrls'] is List)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: (data['photoUrls'] as List)
                              .map((url) => GestureDetector(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (_) => Dialog(
                                          child: InteractiveViewer(
                                            child: Image.network(
                                              url.toString(),
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) =>
                                                  const Padding(
                                                padding: EdgeInsets.all(20),
                                                child: Text(
                                                  'तस्बिर खोल्न सकिएन।',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    child: Image.network(
                                      url.toString(),
                                      width: 75,
                                      height: 75,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.broken_image),
                                    ),
                                  ))
    .toList(),
      ),
   const SizedBox(height: 12),
   
  Row(
  children: [
    Expanded(
      child: ElevatedButton(
        onPressed: () async {
          final amount =
              (data['insuranceAmount'] as num?)?.toDouble() ?? 0;

          try {
            await FirebaseFirestore.instance.runTransaction((transaction) async {
              final freshClaim = await transaction.get(doc.reference);
              final freshData = freshClaim.data() as Map<String, dynamic>?;

if (!freshClaim.exists || freshData?['status'] != 'pending') {
                throw StateError('यो आवेदन पहिले नै समीक्षा गरिएको छ।');
              }
              transaction.update(doc.reference, {
                'status': 'approved',
                'approvedAt': FieldValue.serverTimestamp(),
                'approvedAmount': amount,
                'paidAmount': 0.0,
                'remainingAmount': amount,
                'paymentStatus': 'unpaid',
              });
            });

            if (!context.mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('बीमा आवेदन स्वीकृत भयो।')),
            );
          } catch (e) {
            if (!context.mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('स्वीकृत गर्न समस्या भयो: $e')),
            );
          }
        },
        child: const Text('स्वीकृत गर्नुहोस्'),
      ),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: OutlinedButton(
        onPressed: () async {
          try {
            final annualService = InsuranceAnnualLimitService();
            await FirebaseFirestore.instance.runTransaction((transaction) async {
              final freshClaim = await transaction.get(doc.reference);
              final freshData = freshClaim.data() as Map<String, dynamic>?;

if (!freshClaim.exists || freshData?['status'] != 'pending') {
                throw StateError('यो आवेदन पहिले नै समीक्षा गरिएको छ।');
              }
              final claim = freshClaim.data() as Map<String, dynamic>;
              final uid = claim['uid']?.toString() ?? '';
              final fiscalYear = (claim['fiscalYearStart'] as num?)?.toInt() ??
                  annualService.fiscalYearStart(
                    claim['applicationDateBS']?.toString() ?? '',
                  );
              DocumentReference<Map<String, dynamic>>? annualRef;
              DocumentSnapshot<Map<String, dynamic>>? annualSnapshot;
              if (uid.isNotEmpty && fiscalYear != null) {
                annualRef = annualService.ref(uid, fiscalYear);
                annualSnapshot = await transaction.get(annualRef);
              }
              transaction.update(doc.reference, {
                'status': 'rejected',
                'rejectedAt': FieldValue.serverTimestamp(),
              });
              if (annualRef != null && annualSnapshot!.exists) {
                final oldReserved =
                    (annualSnapshot.data()?['reservedAmount'] as num?)?.toDouble() ?? 0;
                final rejectedAmount =
                    (claim['insuranceAmount'] as num?)?.toDouble() ?? 0;
                if (rejectedAmount <= 0 || oldReserved + 0.001 < rejectedAmount) {
                  throw StateError('वार्षिक बीमा आरक्षित रकमको हिसाब मिलेन।');
                }
                transaction.update(annualRef, {
                  'reservedAmount': oldReserved - rejectedAmount,
                  'revision': ((annualSnapshot.data()?['revision'] as num?)?.toInt() ?? 0) + 1,
                  'lastAction': 'release',
                  'lastClaimId': doc.id,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              }
            });

            if (!context.mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('बीमा आवेदन अस्वीकृत भयो।')),
            );
          } catch (e) {
            if (!context.mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('अस्वीकृत गर्न समस्या भयो: $e')),
            );
          }
        },
        child: const Text('अस्वीकृत गर्नुहोस्'),
      ),
    ),
  ],
),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
