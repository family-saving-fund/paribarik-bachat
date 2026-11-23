import 'package:cloud_firestore/cloud_firestore.dart';

/// Transaction-safe cached balance for the separate insurance fund.
/// All app writers of insurance income and payouts must update this document.
class InsuranceFundLedger {
  InsuranceFundLedger({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const String stateDocumentId = 'current';

  DocumentReference<Map<String, dynamic>> get stateRef =>
      _db.collection('insurance_fund_state').doc(stateDocumentId);

  double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;

  /// Calculates the legacy balance only to initialize the aggregate once.
  Future<double> readLegacyBalance() async {
    final savings = await _db.collection('monthly_savings').get();
    final insuranceIncome = await _db
        .collection('fund_transactions')
        .where('fundType', isEqualTo: 'insurance')
        .get();
    final payouts = await _db
        .collection('fund_transactions')
        .where('category', isEqualTo: 'insurance_claim_payout')
        .get();

    var income = 0.0;
    var expense = 0.0;
    for (final doc in savings.docs) {
      final data = doc.data();
      if (data['isTest'] != true) income += _number(data['insurancePaid']);
    }
    for (final doc in insuranceIncome.docs) {
      final data = doc.data();
      if (data['isTest'] != true) income += _number(data['amount']);
    }
    for (final doc in payouts.docs) {
      final data = doc.data();
      if (data['isTest'] != true && data['status'] == 'disbursed') {
        expense += _number(data['amount']);
      }
    }
    return income - expense;
  }

  /// A stale seed is harmless: transaction users serialize on stateRef and
  /// only the first successful transaction initializes it.
  Future<double> getSeedBalance() async {
    final existing = await stateRef.get();
    if (existing.exists) return _number(existing.data()?['balance']);
    return readLegacyBalance();
  }

  void applyDelta({
    required Transaction transaction,
    required DocumentSnapshot<Map<String, dynamic>> stateSnapshot,
    required double seedBalance,
    required double delta,
  }) {
    final current = stateSnapshot.exists
        ? _number(stateSnapshot.data()?['balance'])
        : seedBalance;
    transaction.set(stateRef, {
      'balance': current + delta,
      'revision': ((stateSnapshot.data()?['revision'] as num?)?.toInt() ?? 0) + 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
