
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminAuditService {
  AdminAuditService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'admin_audit_logs';

  CollectionReference<Map<String, dynamic>> get _auditCollection =>
      _firestore.collection(collectionName);

  /// Records an immutable Admin action inside an existing transaction.
  ///
  /// Call before any transaction write operation.
  /// eventId must be deterministic and unique.
  Future<void> recordInTransaction({
    required Transaction transaction,
    required String eventId,
    required String adminUid,
    required String adminName,
    required String action,
    required String targetCollection,
    required String targetDocumentId,
    required String description,
    String? memberUid,
    String? memberName,
    num? amount,
    String? reason,
    Map<String, dynamic> oldValues = const {},
    Map<String, dynamic> newValues = const {},
    Map<String, dynamic> metadata = const {},
  }) async {
    if (eventId.trim().isEmpty || eventId.contains('/')) {
      throw ArgumentError('Invalid audit eventId.');
    }

    if (adminUid.trim().isEmpty || action.trim().isEmpty) {
      throw ArgumentError('Admin UID and action are required.');
    }

    if (amount != null && (!amount.isFinite || amount < 0)) {
      throw ArgumentError('Audit amount must be valid and non-negative.');
    }

    final auditRef = _auditCollection.doc(eventId);

    // Read before writing; never overwrite an existing audit record.
    final existing = await transaction.get(auditRef);

    if (existing.exists) {
      throw StateError('Audit record already exists: $eventId');
    }

    transaction.set(auditRef, {
      'eventId': eventId,
      'adminUid': adminUid,
      'adminName': adminName,
      'action': action,
      'targetCollection': targetCollection,
      'targetDocumentId': targetDocumentId,
      'description': description,
      'memberUid': memberUid,
      'memberName': memberName,
      'amount': amount,
      'reason': reason,
      'oldValues': oldValues,
      'newValues': newValues,
      'metadata': metadata,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
     
  /// Checks an audit document before any transaction writes.
  Future<DocumentReference<Map<String, dynamic>>> prepareRecordInTransaction({
    required Transaction transaction,
    required String eventId,
  }) async {
    if (eventId.trim().isEmpty || eventId.contains('/')) {
      throw ArgumentError('Invalid audit eventId.');
    }

    final auditRef = _auditCollection.doc(eventId);
    final existing = await transaction.get(auditRef);

    if (existing.exists) {
      throw StateError('Audit record already exists: $eventId');
    }

    return auditRef;
  }

  /// Writes an audit record after all transaction reads are complete.
  void writePreparedRecordInTransaction({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> auditRef,
    required Map<String, dynamic> data,
  }) {
    transaction.set(auditRef, {
      ...data,
      'eventId': auditRef.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

}
