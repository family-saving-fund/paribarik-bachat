import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'notification_service.dart';
import 'member_account_guard.dart';

class LatePaymentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _notices =>
      _db.collection('late_payment_notices');

  /// सदस्यको ढिलाइसम्बन्धी जानकारी पेस गर्ने।
  Future<void> submitNotice({
    required String memberUid,
    required String memberName,
    required String monthKey,
    required String bsDate,
    required String adDate,
    required int bsDay,
    required DateTime deadlineAt,
    required String reason,
  }) async {
    if (memberUid.trim().isEmpty ||
        memberName.trim().isEmpty ||
        monthKey.trim().isEmpty) {
      throw ArgumentError('सदस्यको विवरण र महिना आवश्यक छन्।');
    }

    await MemberAccountGuard.ensureActive(memberUid);

    final today = NepaliDateTime.fromDateTime(DateTime.now());

    final currentMonthKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}';

    if (today.day < 1 ||
        today.day > 9 ||
        bsDay != today.day ||
        monthKey != currentMonthKey) {
      throw StateError(
        'ढिलाइको जानकारी चालु महिनाको १ देखि ९ गतेसम्म मात्र पेस गर्न सकिन्छ।',
      );
    }

    if (reason.trim().isEmpty) {
      throw ArgumentError('ढिलाइको कारण लेख्नुहोस्।');
    }

    if (!deadlineAt.isAfter(DateTime.now())) {
      throw StateError('स्वीकृतिको म्याद सकिएको छ।');
    }

    final noticeId = '${memberUid}_$monthKey';
    final noticeRef = _notices.doc(noticeId);

    await _db.runTransaction((transaction) async {
      final existing = await transaction.get(noticeRef);

      if (existing.exists) {
        throw StateError('यो महिनाको जानकारी पहिल्यै पेस गरिएको छ।');
      }

      transaction.set(noticeRef, {
        'memberUid': memberUid,
        'memberName': memberName,
        'monthKey': monthKey,
        'bsDate': bsDate,
        'adDate': adDate,
        'bsDay': bsDay,
        'deadlineAt': Timestamp.fromDate(deadlineAt),
        'reason': reason.trim(),
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
        'adminNote': '',
      });
    });

    await NotificationService.sendToAdmins(
      title: 'नयाँ ढिलाइ सूचना',
      message: '$memberName ले $monthKey महिनाको ढिलाइसम्बन्धी जानकारी पेस गर्नुभएको छ।',
      type: 'late_payment_notice',
      relatedId: noticeId,
    );
  }
  

  /// Admin का लागि सबै जानकारी हेर्ने।
  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllNotices() {
    return _notices.orderBy('submittedAt', descending: true).snapshots();
  }

  /// सदस्यले आफ्नै जानकारी हेर्ने।
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMemberNotices(
    String memberUid,
  ) {
    return _notices.where('memberUid', isEqualTo: memberUid).snapshots();
  }
   
  /// Admin ले जानकारी स्वीकृत वा अस्वीकृत गर्ने।
  Future<void> reviewNotice({
    required String noticeId,
    required String adminUid,
    required bool approved,
    String adminNote = '',
  }) async {
    final ref = _notices.doc(noticeId);

    final today = NepaliDateTime.fromDateTime(DateTime.now());

    if (today.day >= 11) {
      throw StateError(
        '११ गतेदेखि ढिलाइ सूचनामा Admin ले निर्णय गर्न पाउँदैन।',
      );
    }

    late String memberUid;
    late String title;
    late String message;

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);

      if (!snapshot.exists) {
        throw StateError('ढिलाइको जानकारी भेटिएन।');
      }

      final data = snapshot.data()!;

      if (data['status'] != 'pending') {
        throw StateError('यो जानकारीको निर्णय भइसकेको छ।');
      }

      memberUid = (data['memberUid'] ?? '').toString();

      if (memberUid.isEmpty) {
        throw StateError('सदस्य UID भेटिएन।');
      }

      title =
          approved ? 'भुक्तानी सूचना स्वीकृत' : 'भुक्तानी सूचना अस्वीकृत';

      message = approved
          ? 'बधाई छ, Admin द्वारा तपाईंको ढिलाइसम्बन्धी जानकारी स्वीकृत भएको छ।'
          : 'तपाईंको ढिलाइसम्बन्धी जानकारी अस्वीकृत भएको छ। ${adminNote.trim()}';

      transaction.update(ref, {
        'status': approved ? 'approved' : 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminUid,
        'adminNote': adminNote.trim(),
      });
    });

    await NotificationService.sendToMember(
      memberUid: memberUid,
      title: title,
      message: message,
      type: 'late_payment_notice',
      relatedId: noticeId,
    );
  }

      
  
  /// म्याद सकिएका जानकारी स्वतः स्वीकृत गर्ने।
  Future<int> processExpiredNotices({
    required String memberUid,
  }) async {
    if (memberUid.trim().isEmpty) {
      throw ArgumentError('सदस्य UID आवश्यक छ।');
    }

    if (await MemberAccountGuard.isDeactivated(memberUid)) return 0;

    final today = NepaliDateTime.fromDateTime(DateTime.now());

    if (today.day <= 10) {
      return 0;
    }

    final currentMonthKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}';

    final snapshot = await _notices
        .where('memberUid', isEqualTo: memberUid)
        .where('monthKey', isEqualTo: currentMonthKey)
        .where('status', isEqualTo: 'pending')
        .get();

    int approvedCount = 0;

    for (final doc in snapshot.docs) {
      final didApprove = await _db.runTransaction<bool>(
        (transaction) async {
          final latest = await transaction.get(doc.reference);

          if (!latest.exists) return false;

          final data = latest.data()!;

          if (data['memberUid'] != memberUid ||
              data['monthKey'] != currentMonthKey ||
              data['status'] != 'pending') {
            return false;
          }

          transaction.update(doc.reference, {
            'status': 'auto_approved',
            'reviewedAt': FieldValue.serverTimestamp(),
            'reviewedBy': 'system',
            'adminNote': '१० गते पूरा भएपछि निर्णय नभएकाले स्वतः स्वीकृत।',
          });

          return true;
        },
      );

      if (!didApprove) continue;

      approvedCount++;

      await NotificationService.sendToMember(
        memberUid: memberUid,
        title: 'ढिलाइ सूचना स्वतः स्वीकृत',
        message: '१० गतेपछि तपाईंको ढिलाइसम्बन्धी जानकारी स्वतः स्वीकृत भएको छ।',
        type: 'late_payment_notice',
        relatedId: doc.id,
      );
    }

    return approvedCount;
  }    
}
