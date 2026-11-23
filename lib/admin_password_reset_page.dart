import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminPasswordResetPage extends StatelessWidget {
  const AdminPasswordResetPage({super.key});

  Future<void> _updateRequest(
    BuildContext context,
    String requestId,
    String status,
  ) async {
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;

      if (adminUid == null) {
        throw Exception('Admin लगइन भएको छैन।');
      }

      await FirebaseFirestore.instance
          .collection('password_reset_requests')
          .doc(requestId)
          .update({
        'status': status,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedByUid': adminUid,
      });

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? 'अनुरोध स्वीकृत भयो।'
                : 'अनुरोध अस्वीकृत भयो।',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('कारबाही गर्न असफल: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Password Reset अनुरोध'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('password_reset_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('अनुरोध लोड गर्न समस्या भयो।'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final requests = snapshot.data?.docs ?? [];

          if (requests.isEmpty) {
            return const Center(
              child: Text('कुनै नयाँ Password Reset अनुरोध छैन।'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final doc = requests[index];
              final data = doc.data();

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['memberName'] ?? 'नाम उपलब्ध छैन',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('इमेल: ${data['email'] ?? ''}'),
                      Text('सदस्य UID: ${data['memberUid'] ?? ''}'),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _updateRequest(
                                context,
                                doc.id,
                                'approved',
                              ),
                              icon: const Icon(Icons.check),
                              label: const Text('स्वीकृत'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _updateRequest(
                                context,
                                doc.id,
                                'rejected',
                              ),
                              icon: const Icon(Icons.close),
                              label: const Text('अस्वीकृत'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
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
