
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static bool _isMemorial(String type) {
    final value = type.trim().toLowerCase();
    return value == 'shraddhanjali' ||
        value == 'memorial' ||
        value == 'श्रद्धाञ्जली';
  }

  static Future<void> _send({
    required String title,
    required String message,
    required String type,
    List<String>? recipientUids,
    bool broadcast = false,
    String? relatedId,
  }) async {
    if (_isMemorial(type)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Login भएको प्रयोगकर्ता भेटिएन।');
    }

    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Firebase ID Token प्राप्त भएन।');
    }

    final uniqueUids = recipientUids
            ?.map((uid) => uid.trim())
            .where((uid) => uid.isNotEmpty)
            .toSet()
            .toList() ??
        [];

    final body = <String, dynamic>{
      'title': title,
      'body': message,
      'type': type,
      'broadcast': broadcast,
      if (uniqueUids.isNotEmpty) 'recipientUids': uniqueUids,
      if (relatedId != null) 'relatedId': relatedId,
    };

    final response = await Supabase.instance.client.functions.invoke(
     'send-push-notification-',
      headers: {
        'Authorization': 'Bearer $idToken',
      },
      body: body,
    );

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        'Notification पठाउन सकिएन। Status: ${response.status}',
      );
    }
  }

  static Future<void> sendToMember({
    required String memberUid,
    required String title,
    required String message,
    required String type,
    String? relatedId,
  }) async {
    if (memberUid.trim().isEmpty) return;

    await _send(
      recipientUids: [memberUid],
      title: title,
      message: message,
      type: type,
      relatedId: relatedId,
    );
  }

  static Future<void> sendToMembers({
    required List<String> memberUids,
    required String title,
    required String message,
    required String type,
    String? relatedId,
  }) async {
    final uniqueUids = memberUids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .toList();

    if (uniqueUids.isEmpty) return;

    await _send(
      recipientUids: uniqueUids,
      title: title,
      message: message,
      type: type,
      relatedId: relatedId,
    );
  }

  static Future<void> sendToAdmins({
    required String title,
    required String message,
    required String type,
    String? relatedId,
  }) async {
    final snapshot = await _db
        .collection('member')
        .where('role', isEqualTo: 'admin')
        .get();

    await sendToMembers(
      memberUids: snapshot.docs.map((doc) => doc.id).toList(),
      title: title,
      message: message,
      type: type,
      relatedId: relatedId,
    );
  }

  static Future<void> sendToMembersExcept({
    required List<String> memberUids,
    required String excludedUid,
    required String title,
    required String message,
    required String type,
    String? relatedId,
  }) async {
    final filteredUids = memberUids
        .where((uid) => uid.trim() != excludedUid.trim())
        .toList();

    await sendToMembers(
      memberUids: filteredUids,
      title: title,
      message: message,
      type: type,
      relatedId: relatedId,
    );
  }

  static Future<void> sendToCurrentUser({
    required String title,
    required String message,
    required String type,
    String? relatedId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    await sendToMember(
      memberUid: uid,
      title: title,
      message: message,
      type: type,
      relatedId: relatedId,
    );
  }
}
