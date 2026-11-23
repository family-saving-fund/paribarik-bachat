import 'package:flutter/material.dart';

import 'late_payment_service.dart';
import 'nepali_digits.dart';

class AdminLatePaymentNoticePage extends StatelessWidget {
  final String adminUid;

  const AdminLatePaymentNoticePage({
    super.key,
    required this.adminUid,
  });

  String _statusText(String status) {
    switch (status) {
      case 'pending':
        return 'निर्णय हुन बाँकी';
      case 'approved':
        return 'स्वीकृत';
      case 'auto_approved':
        return 'स्वतः स्वीकृत';
      case 'rejected':
        return 'अस्वीकृत';
      default:
        return status;
    }
  }

  Future<void> _reviewNotice(
    BuildContext context, {
    required String noticeId,
    required bool approved,
  }) async {
    try {
      await LatePaymentService().reviewNotice(
        noticeId: noticeId,
        adminUid: adminUid,
        approved: approved,
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'सूचना स्वीकृत भयो।'
                : 'सूचना अस्वीकृत भयो।',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('निर्णय गर्न समस्या भयो: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('भुक्तानी ढिलाइ सूचनाहरू'),
      ),
      body: StreamBuilder(
        stream: LatePaymentService().watchAllNotices(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('सूचनाहरू लोड हुन सकेनन्।'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final notices = snapshot.data!.docs;

          if (notices.isEmpty) {
            return const Center(
              child: Text('कुनै ढिलाइ सूचना आएको छैन।'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: notices.length,
            itemBuilder: (context, index) {
              final doc = notices[index];
              final data = doc.data();

              final status =
                  data['status']?.toString() ?? 'pending';

              final memberName =
                  data['memberName']?.toString() ?? 'नाम छैन';

              final reason =
                  data['reason']?.toString() ?? 'कारण उल्लेख छैन';

              final monthKey =
                  data['monthKey']?.toString() ?? '';

              final bsDate =
                  data['bsDate']?.toString() ?? '';

              final canReview = status == 'pending';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memberName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('महिना: ${toNepaliDigits(monthKey)}'),
                      Text('पेश गरेको मिति: ${toNepaliDigits(bsDate)}'),
                      const SizedBox(height: 8),
                      const Text(
                        'ढिलाइ हुनुको कारण:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(reason),
                      const SizedBox(height: 10),
                      Text(
                        'स्थिति: ${_statusText(status)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: status == 'rejected'
                              ? Colors.red
                              : status == 'pending'
                                  ? Colors.orange
                                  : Colors.green,
                        ),
                      ),
                      if (canReview) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  _reviewNotice(
                                    context,
                                    noticeId: doc.id,
                                    approved: true,
                                  );
                                },
                                child: const Text('स्वीकृत गर्नुहोस्'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  _reviewNotice(
                                    context,
                                    noticeId: doc.id,
                                    approved: false,
                                  );
                                },
                                child: const Text('अस्वीकृत गर्नुहोस्'),
                              ),
                            ),
                          ],
                        ),
                      ],
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