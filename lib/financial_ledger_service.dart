import 'package:cloud_firestore/cloud_firestore.dart';

class FinancialLedgerService {
  FinancialLedgerService({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'financial_ledger';

  CollectionReference<Map<String, dynamic>> get _ledgerCollection =>
      _firestore.collection(collectionName);

  /// Records one financial event inside an existing Firestore transaction.
  ///
  /// IMPORTANT:
  /// Call this method before any transaction.set/update/delete operation,
  /// because Firestore requires transaction reads to happen before writes.
  ///
  /// eventId must be deterministic and unique for the source financial event.
  /// Example: payment_approved_PAYMENT_DOCUMENT_ID
  Future<bool> recordInTransaction({
    required Transaction transaction,
    required String eventId,
    required String memberUid,
    required String memberName,
    required String transactionType,
    required num amount,
    required String bsDate,
    required String description,
    required String sourceCollection,
    required String sourceDocumentId,
    required String recordedByUid,
    required String recordedByName,
    String status = 'approved',
    Map<String, dynamic> metadata = const {},
  }) async {
    if (eventId.trim().isEmpty) {
      throw ArgumentError('eventId cannot be empty.');
    }

    if (eventId.contains('/')) {
      throw ArgumentError('eventId cannot contain "/".');
    }

    if (memberUid.trim().isEmpty) {
      throw ArgumentError('memberUid cannot be empty.');
    }

    if (!amount.isFinite || amount < 0) {
      throw ArgumentError('amount must be a valid non-negative number.');
    }

    if (transactionType.trim().isEmpty) {
      throw ArgumentError('transactionType cannot be empty.');
    }

    final ledgerRef = _ledgerCollection.doc(eventId);

    // Read first to prevent duplicate ledger events.
    final existingRecord = await transaction.get(ledgerRef);

    if (existingRecord.exists) {
      return false;
    }

    transaction.set(ledgerRef, {
      'eventId': eventId,
      'memberUid': memberUid,
      'memberName': memberName,
      'transactionType': transactionType,
      'amount': amount,
      'bsDate': bsDate,
      'description': description,
      'sourceCollection': sourceCollection,
      'sourceDocumentId': sourceDocumentId,
      'recordedByUid': recordedByUid,
      'recordedByName': recordedByName,
      'status': status,
      'metadata': metadata,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return true;
  }

      /// Records multiple financial events in one Firestore transaction.
  /// All ledger documents are read before any ledger write is performed.
  Future<int> recordManyInTransaction({
    required Transaction transaction,
    required List<Map<String, dynamic>> events,
  }) async {
    if (events.isEmpty) return 0;

    final refs = events.map((event) {
      final eventId = (event['eventId'] ?? '').toString().trim();

      if (eventId.isEmpty || eventId.contains('/')) {
        throw ArgumentError('Invalid ledger eventId: $eventId');
      }

      return _ledgerCollection.doc(eventId);
    }).toList();

    if (refs.map((ref) => ref.id).toSet().length != refs.length) {
      throw ArgumentError('Duplicate eventId in ledger events.');
    }

    // Read every ledger document before writing anything.
    final snapshots = await Future.wait(
      refs.map((ref) => transaction.get(ref)),
    );

    if (snapshots.any((snapshot) => snapshot.exists)) {
      throw StateError(
        'Ledger event already exists. Financial transaction cancelled.',
      );
    }

    for (var i = 0; i < events.length; i++) {
      transaction.set(refs[i], {
        ...events[i],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    return events.length;
  }
    
  /// Returns a member's ledger history, newest records first.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMemberLedger({
    required String memberUid,
    int limit = 100,
  }) {
    if (memberUid.trim().isEmpty) {
      throw ArgumentError('memberUid cannot be empty.');
    }

    return _ledgerCollection
        .where('memberUid', isEqualTo: memberUid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Returns all ledger records for Admin-side reporting.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllLedger() {
  return _ledgerCollection
      .orderBy('createdAt', descending: true)
      .snapshots();
}

  /// Gets a single ledger record by its deterministic event ID.
  Future<DocumentSnapshot<Map<String, dynamic>>> getLedgerRecord(
    String eventId,
  ) {
    return _ledgerCollection.doc(eventId).get();
  }
    
  /// Checks ledger documents before any transaction writes.
  Future<List<DocumentReference<Map<String, dynamic>>>>
      prepareManyInTransaction({
    required Transaction transaction,
    required List<Map<String, dynamic>> events,
  }) async {
    final refs = events.map((event) {
      final eventId = (event['eventId'] ?? '').toString().trim();

      if (eventId.isEmpty || eventId.contains('/')) {
        throw ArgumentError('Invalid ledger eventId: $eventId');
      }

      return _ledgerCollection.doc(eventId);
    }).toList();

    if (refs.map((ref) => ref.id).toSet().length != refs.length) {
      throw ArgumentError('Duplicate eventId in ledger events.');
    }

    final snapshots = await Future.wait(
      refs.map((ref) => transaction.get(ref)),
    );

    if (snapshots.any((snapshot) => snapshot.exists)) {
      throw StateError(
        'Ledger event already exists. Financial transaction cancelled.',
      );
    }

    return refs;
  }

  /// Writes prepared ledger documents after all transaction reads.
  void writePreparedManyInTransaction({
    required Transaction transaction,
    required List<DocumentReference<Map<String, dynamic>>> refs,
    required List<Map<String, dynamic>> events,
  }) {
    if (refs.length != events.length) {
      throw ArgumentError('Ledger refs and events count do not match.');
    }

    for (var i = 0; i < events.length; i++) {
      transaction.set(refs[i], {
        ...events[i],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
