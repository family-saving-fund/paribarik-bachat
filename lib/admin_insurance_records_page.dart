import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'insurance_payout_service.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'nepali_digits.dart';

class AdminInsuranceRecordsPage extends StatelessWidget {
    
  const AdminInsuranceRecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('स्वीकृत बीमा तथा भुक्तानी अभिलेख'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('insurance_claims')
            .where('status', isEqualTo: 'approved')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('बीमा अभिलेख लोड गर्न समस्या भयो।'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final records = snapshot.data!.docs.toList();

          records.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;

            final aDate = aData['approvedAt'] as Timestamp?;
            final bDate = bData['approvedAt'] as Timestamp?;

            return (bDate?.millisecondsSinceEpoch ?? 0)
                .compareTo(aDate?.millisecondsSinceEpoch ?? 0);
          });

          if (records.isEmpty) {
            return const Center(
              child: Text('हाल कुनै स्वीकृत बीमा आवेदन छैन।'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final data =
                  records[index].data() as Map<String, dynamic>;

              final approvedAmount =
                  (data['approvedAmount'] as num?)?.toDouble() ??
                  (data['insuranceAmount'] as num?)?.toDouble() ??
                  0;

              final paidAmount =
                  (data['paidAmount'] as num?)?.toDouble() ?? 0;

         final remainingAmount =
                  (data['remainingAmount'] as num?)?.toDouble() ??
                  (approvedAmount - paidAmount);
  final claimId = records[index].id;
final adminUid = FirebaseAuth.instance.currentUser?.uid;

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
                      const Divider(height: 20),
                      Text('स्वीकृत रकम: रु. ${approvedAmount.toStringAsFixed(2)}'),
                      Text('भुक्तानी भएको: रु. ${paidAmount.toStringAsFixed(2)}'),
                      Text(
                        'बाँकी रकम: रु. ${remainingAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'भुक्तानी स्थिति: ${data['paymentStatus'] ?? 'unpaid'}',
                      ),
          const SizedBox(height: 12),
if (remainingAmount > 0 && adminUid != null)
  SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      icon: const Icon(Icons.payment),
      label: const Text('भुक्तानी गर्नुहोस्'),
      onPressed: () {
  showDialog(
    context: context,
    builder: (dialogContext) {
      return InsurancePaymentDialog(
        claimId: claimId,
        adminUid: adminUid!,
        remainingAmount: remainingAmount,
      );
    },
  );
},
    ),
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
class InsurancePaymentDialog extends StatefulWidget {
  final String claimId;
  final String adminUid;
  final double remainingAmount;

  const InsurancePaymentDialog({
    super.key,
    required this.claimId,
    required this.adminUid,
    required this.remainingAmount,
  });

  @override
  State<InsurancePaymentDialog> createState() =>
      _InsurancePaymentDialogState();
}

class _InsurancePaymentDialogState
    extends State<InsurancePaymentDialog> {
  final _amountController = TextEditingController();
  NepaliDateTime _paymentDate = NepaliDateTime.now();
  bool _isPaying = false;
  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
    
    bool _validatePaymentAmount() {
  final amount = double.tryParse(_amountController.text.trim());

  if (amount == null || amount <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('कृपया सही भुक्तानी रकम राख्नुहोस्।')),
    );
    return false;
  }

  if (amount > widget.remainingAmount) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('भुक्तानी रकम बाँकी रकमभन्दा बढी हुन मिल्दैन।')),
    );
    return false;
  }
   return true;
}

  @override
Widget build(BuildContext context) {
  return AlertDialog(
    title: const Text('बीमा रकम भुक्तानी'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'बाँकी रकम: रु. ${widget.remainingAmount.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
          ),
          decoration: const InputDecoration(
            labelText: 'भुक्तानी रकम (रु.)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.currency_rupee),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            final picked = await showNepaliDatePicker(
              context: context,
              initialDate: _paymentDate,
              firstDate: NepaliDateTime(2000),
              lastDate: NepaliDateTime(2090),
            );

            if (picked != null) {
              setState(() {
                _paymentDate = picked;
              });
            }
          },
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'भुक्तानी मिति (BS)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.calendar_month),
            ),
            child: Text(
              toNepaliDigits(NepaliDateFormat('yyyy-MM-dd').format(_paymentDate)),
            ),
          ),
        ),
      ],
    ),
    actions: [
  ElevatedButton.icon(
    onPressed: _isPaying
        ? null
        : () async {
            if (!_validatePaymentAmount()) return;

            final amount = double.tryParse(
              _amountController.text.trim(),
            );

            if (amount == null) return;

            setState(() => _isPaying = true);

            try {
              final bsDate =
                  NepaliDateFormat('yyyy-MM-dd').format(_paymentDate);

              final adDate = _paymentDate
                  .toDateTime()
                  .toIso8601String()
                  .split('T')
                  .first;

              await InsurancePayoutService().payApprovedClaim(
                claimId: widget.claimId,
                adminUid: widget.adminUid,
                bsDate: bsDate,
                adDate: adDate,
                requestedAmount: amount,
              );

              if (!mounted) return;
              Navigator.pop(context, true);
            } catch (e) {
              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('भुक्तानी असफल: $e')),
              );
            } finally {
              if (mounted) {
                setState(() => _isPaying = false);
              }
            }
          },
    icon: _isPaying
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.payment),
    label: const Text('भुक्तानी गर्नुहोस्'),
  ),
  TextButton(
    onPressed: _isPaying ? null : () => Navigator.pop(context),
    child: const Text('बन्द गर्नुहोस्'),
  ),
],
  );
}
}