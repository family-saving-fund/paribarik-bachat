import 'package:cloud_firestore/cloud_firestore.dart';

/// Reserves each member UID's claims across self and family for one BS FY.
class InsuranceAnnualLimitService {
  InsuranceAnnualLimitService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const double annualLimit = 100000.0;

  int? fiscalYearStart(String date) {
    final parts = date.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null ||
        month < 1 || month > 12 || day < 1 || day > 32) return null;
    return month >= 4 ? year : year - 1;
  }

  DocumentReference<Map<String, dynamic>> ref(String uid, int fyStart) =>
      _db.collection('insurance_annual_limits').doc('${uid}_$fyStart');

  double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;

  /// Used only to seed the aggregate on its first transactional write.
  Future<double> readLegacyReserved(String uid, int fyStart) async {
    final snapshot = await _db.collection('insurance_claims')
        .where('uid', isEqualTo: uid).get();
    var total = 0.0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status']?.toString();
      if (status != 'pending' && status != 'approved') continue;
      if (fiscalYearStart(data['applicationDateBS']?.toString() ?? '') != fyStart) continue;
      total += _number(data['insuranceAmount'] ?? data['claimAmount']);
    }
    return total;
  }

  Future<double> getSeedReserved(String uid, int fyStart) async {
    final snapshot = await ref(uid, fyStart).get();
    if (snapshot.exists) return _number(snapshot.data()?['reservedAmount']);
    return readLegacyReserved(uid, fyStart);
  }
}
