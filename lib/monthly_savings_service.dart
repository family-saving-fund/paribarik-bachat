
import 'package:cloud_firestore/cloud_firestore.dart';

class MonthlySavingsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _savings =>
      _db.collection('monthly_savings');

  int _monthNumber(String monthKey) {
    final parts = monthKey.split('-');

    if (parts.length != 2) {
      throw ArgumentError('महिना YYYY-MM ढाँचामा हुनुपर्छ।');
    }

    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    if (year < 1 || month < 1 || month > 12) {
      throw ArgumentError('गलत BS महिना: $monthKey');
    }

    return year * 12 + month;
  }

  String _monthKeyFromNumber(int number) {
    final year = (number - 1) ~/ 12;
    final month = ((number - 1) % 12) + 1;

    return '$year-${month.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _newMonthlyRecord({
    required String memberUid,
    required String monthKey,
  }) {
    return {
      'memberUid': memberUid,
      'monthKey': monthKey,
      'savingsAmount': 2000,
      'insuranceAmount': 300,
      'totalDue': 2300,
      'paidAmount': 0,
      'insurancePaid': 0,
      'savingsPaid': 0,

     // सामान्य जरिमाना: ४%, ६%, ८%
'normalPenaltyPaid': 0,

// लगातार दुई महिना बाँकी हुँदा लाग्ने ५०%
'specialPenaltyPaid': 0,

// बीमा र बचततर्फ तिरिएको जरिमाना छुट्टाछुट्टै
'normalInsurancePenaltyPaid': 0,
'normalSavingsPenaltyPaid': 0,
'specialInsurancePenaltyPaid': 0,
'specialSavingsPenaltyPaid': 0,

// जम्मा तिरिएको र बाँकी जरिमाना
'penaltyPaid': 0,
'penaltyDue': 0,

// सामान्य जरिमानाको अन्तिम चरण
'penaltyStage': 0,

      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> createNext12Months({
    required String memberUid,
    required String firstMonthKey,
  }) async {
    if (memberUid.trim().isEmpty) {
      throw ArgumentError('सदस्य UID आवश्यक छ।');
    }

    final firstNumber = _monthNumber(firstMonthKey);

    for (int i = 0; i < 12; i++) {
      final monthKey = _monthKeyFromNumber(firstNumber + i);
      final ref = _savings.doc('${memberUid}_$monthKey');

      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);

        if (!snapshot.exists) {
          transaction.set(
            ref,
            _newMonthlyRecord(
              memberUid: memberUid,
              monthKey: monthKey,
            ),
          );
          return;
        }

        final data = snapshot.data() ?? {};
        final updates = <String, dynamic>{};

       // पुरानो भुक्तानी रकम नबिगारी आवश्यक फाँट मात्र थप्ने।
final defaults = <String, dynamic>{
  'normalPenaltyPaid': 0,
  'specialPenaltyPaid': 0,

  // बीमा र बचततर्फ तिरिएको जरिमाना छुट्टाछुट्टै
  'normalInsurancePenaltyPaid': 0,
  'normalSavingsPenaltyPaid': 0,
  'specialInsurancePenaltyPaid': 0,
  'specialSavingsPenaltyPaid': 0,

  'penaltyPaid': 0,
  'penaltyDue': 0,
  'penaltyStage': 0,
  'insurancePaid': 0,
  'savingsPaid': 0,
};

        for (final entry in defaults.entries) {
          if (!data.containsKey(entry.key)) {
            updates[entry.key] = entry.value;
          }
        }

        if (updates.isNotEmpty) {
          transaction.update(ref, updates);
        }
      });
    }
  }

  Future<String> findFirstUnpaidMonth({
    required String memberUid,
    required String startMonthKey,
  }) async {
    if (memberUid.trim().isEmpty) {
      throw ArgumentError('सदस्य UID आवश्यक छ।');
    }

    final startNumber = _monthNumber(startMonthKey);

    final snapshot = await _savings
        .where('memberUid', isEqualTo: memberUid)
        .get();

    final records = <String, Map<String, dynamic>>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final key = data['monthKey']?.toString();

      if (key != null) {
        records[key] = data;
      }
    }

    for (int i = 0; i < 120; i++) {
      final monthKey = _monthKeyFromNumber(startNumber + i);
      final data = records[monthKey];

      if (data == null) {
        return monthKey;
      }

      final totalDue =
          (data['totalDue'] as num?)?.toInt() ?? 2300;
      final paidAmount =
          (data['paidAmount'] as num?)?.toInt() ?? 0;

      if (paidAmount < totalDue) {
        return monthKey;
      }
    }

    throw StateError('भुक्तानी बाँकी महिना भेटिएन।');
  }

  Future<void> saveMonthlyRecord({
    required String memberUid,
    required String monthKey,
    required int savingsAmount,
    required int insuranceAmount,
  }) async {
    if (memberUid.trim().isEmpty) {
      throw ArgumentError('सदस्य UID आवश्यक छ।');
    }

    if (savingsAmount != 2000 || insuranceAmount != 300) {
      throw ArgumentError('मासिक बचत रु. २००० र बीमा रु. ३०० हुनुपर्छ।');
    }

    _monthNumber(monthKey);

    final ref = _savings.doc('${memberUid}_$monthKey');

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);

      if (snapshot.exists) {
        throw StateError('यो महिनाको रेकर्ड पहिले नै छ।');
      }

      transaction.set(
        ref,
        _newMonthlyRecord(
          memberUid: memberUid,
          monthKey: monthKey,
        ),
      );
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMemberRecords(
    String memberUid,
  ) {
    return _savings
        .where('memberUid', isEqualTo: memberUid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllRecords() {
    return _savings.snapshots();
  }
}
