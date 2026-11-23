
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class NotificationPage extends StatelessWidget {
  final String memberUid;

  const NotificationPage({
    super.key,
    required this.memberUid,
  });

  CollectionReference<Map<String, dynamic>> get _notifications =>
      FirebaseFirestore.instance.collection('notifications');

  Future<void> _markAsRead(
    BuildContext context,
    String notificationId,
  ) async {
    try {
    await _notifications.doc(notificationId).update({
  'isRead': true,
});
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('सूचना पढिएको बनाउन सकिएन: $e')),
      );
    }
  }

  String _formatDate(dynamic value) {
    if (value is! Timestamp) return 'समय उपलब्ध छैन';

    final date = value.toDate().toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month/$year  $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    if (memberUid.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('सूचनाहरू')),
        body: const Center(
          child: Text('सदस्य पहिचान उपलब्ध छैन।'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('सूचनाहरू'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _notifications
            .where('memberUid', isEqualTo: memberUid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'सूचना लोड गर्न समस्या भयो।\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = snapshot.data?.docs.toList() ?? [];

          docs.sort((a, b) {
            final aTime = a.data()['createdAt'];
            final bTime = b.data()['createdAt'];

            final aDate = aTime is Timestamp
                ? aTime.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);

            final bDate = bTime is Timestamp
                ? bTime.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);

            return bDate.compareTo(aDate);
          });

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 65,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'अहिलेसम्म कुनै सूचना छैन।',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          final unreadCount = docs.where(
            (doc) => doc.data()['isRead'] != true,
          ).length;

          return Column(
            children: [
              if (unreadCount > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: Text(
                    'नपढिएका सूचना: $unreadCount',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final isRead = data['isRead'] == true;

                    final title =
                        data['title']?.toString() ?? 'नयाँ सूचना';

                    final message =
                        data['message']?.toString() ?? '';

                    final type =
                        data['type']?.toString() ?? 'general';

                    return Card(
                      elevation: isRead ? 1 : 3,
                      color: isRead
                          ? null
                          : Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.35),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: isRead
                              ? Colors.grey.shade300
                              : Theme.of(context).colorScheme.primary,
                          child: Icon(
                            Icons.notifications_active,
                            color: isRead ? Colors.grey.shade700 : Colors.white,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontWeight: isRead
                                      ? FontWeight.normal
                                      : FontWeight.bold,
                                ),
                              ),
                            ),
                            if (!isRead)
                              const Icon(
                                Icons.circle,
                                size: 10,
                                color: Colors.blue,
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(message),
                              const SizedBox(height: 8),
                              Text(
                                '${_formatDate(data['createdAt'])}  •  $type',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onTap: isRead
                            ? null
                            : () => _markAsRead(context, doc.id),
                      ),
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
