import 'package:cloud_firestore/cloud_firestore.dart';

/// Member-side financial actions are blocked while an account is deactivated.
/// A fixed period is considered inactive only between its configured dates.
class MemberAccountGuard {
  static Future<bool> isDeactivated(String memberUid) async {
    if (memberUid.trim().isEmpty) return false;
    final snapshot = await FirebaseFirestore.instance
        .collection('member')
        .doc(memberUid)
        .get();
    final data = snapshot.data() ?? {};
    final mode = data['deactivationMode']?.toString();
    final now = DateTime.now();

    if (mode == 'fixed') {
      final startValue = data['deactivationStartsAt'];
      final endValue = data['deactivationEndsAt'];
      final start = startValue is Timestamp ? startValue.toDate() : null;
      final end = endValue is Timestamp ? endValue.toDate() : null;
      if (end != null && !end.isAfter(now)) return false;
      if (start != null && start.isAfter(now)) return false;
      if (start != null && !start.isAfter(now) &&
          (end == null || end.isAfter(now))) return true;
    }

    return data['accountActive'] == false;
  }

  static Future<void> ensureActive(String memberUid) async {
    if (await isDeactivated(memberUid)) {
      throw StateError(
        'तपाईंको खाता निष्क्रिय छ। कृपया Admin लाई सम्पर्क गर्नुहोस्।',
      );
    }
  }
}
