import 'package:cloud_firestore/cloud_firestore.dart';
import 'insurance_fund_ledger.dart';

class FundService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // रकम सुरक्षित रूपमा int मा परिवर्तन गर्ने
  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
    
      double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString()) ?? 0;
  }

  // बीमा कोषको वास्तविक मौज्दात
  Future<double> calculateInsuranceFundBalance() async {
    final aggregate = await InsuranceFundLedger(firestore: _db).stateRef.get();
    if (aggregate.exists) {
      return _toDouble(aggregate.data()?['balance']);
    }
    double totalIncome = 0;
    double totalPaid = 0;

    // सदस्यहरूको मासिक बीमा जम्मा
    final savingsSnapshot =
        await _db.collection('monthly_savings').get();

    for (final doc in savingsSnapshot.docs) {
      final data = doc.data();
      if (data['isTest'] == true) continue;
      totalIncome += _toDouble(data['insurancePaid']);
    }

    // बीमा जरिवाना र बीमा कोषमा आएको अन्य रकम
    final fundSnapshot =
        await _db.collection('fund_transactions').get();

    for (final doc in fundSnapshot.docs) {
      final data = doc.data();

      if (data['isTest'] == true) continue;

      final amount = _toDouble(data['amount']);

      if (data['fundType'] == 'insurance') {
        totalIncome += amount;
      }

      // बीमा दाबीमा भुक्तानी भएको रकम
      if (data['fundType'] == 'expense' &&
          data['category'] == 'insurance_claim_payout' &&
          data['status'] == 'disbursed') {
        totalPaid += amount;
      }
    }

    return totalIncome - totalPaid;
  }

  // रु. ५,००० सुरक्षित राखेर भुक्तानी गर्न मिल्ने रकम
  Future<double> calculateAvailableInsuranceForClaims() async {
    final balance = await calculateInsuranceFundBalance();

    final available = balance - 5000;

    return available > 0 ? available : 0;
  }
    
      // वितरण भइसकेको कुल खर्च
  Future<int> calculateTotalExpenses() async {
    final expenseSnapshot = await _db
        .collection('fund_transactions')
        .where('fundType', isEqualTo: 'expense')
        .where('category', isEqualTo: 'expense_withdrawal')
        .where('status', isEqualTo: 'disbursed')
        .get();

    int totalExpenses = 0;

    for (final doc in expenseSnapshot.docs) {
      final data = doc.data();

      if (data['isTest'] == true) {
        continue;
      }

      totalExpenses += _toInt(data['amount']);
    }

    return totalExpenses;
  }
    
      // खर्च घटाउनुअघिको कुल संस्थागत आम्दानी
  Future<int> calculateTotalIncome() async {
    final institutionSavings =
        await calculateInstitutionSavings();

    final totalExpenses =
        await calculateTotalExpenses();

    return institutionSavings + totalExpenses;
  }
    

  // बीमा बाहेक संस्थाको कुल योग्य बचत
  Future<int> calculateInstitutionSavings() async {
    // १. मासिक बचत र बचत जरिवाना
    final savingsSnapshot =
        await _db.collection('monthly_savings').get();

    int memberSavings = 0;

    for (final doc in savingsSnapshot.docs) {
      final data = doc.data();

      memberSavings += _toInt(data['savingsPaid']);

      // सामान्य बचत जरिवाना
memberSavings +=
    _toInt(data['normalSavingsPenaltyPaid']);

// विशेष बचत जरिवाना
memberSavings +=
    _toInt(data['specialSavingsPenaltyPaid']);

      // बीमा र बीमा जरिवाना जानाजानी जोडिएको छैन।
    }

    // २. fund_transactions बाट Donation को बचत हिस्सा
final donationSnapshot = await _db
    .collection('fund_transactions')
    .where('fundType', isEqualTo: 'savings')
    .where('category', isEqualTo: 'donation')
    .get();

int donationSavings = 0;

for (final doc in donationSnapshot.docs) {
  final data = doc.data();

  if (data['isTest'] == true) {
    continue;
  }

  donationSavings += _toInt(data['amount']);
}

// ३. Admin ले स्वीकृत गरेका ऋण किस्ताबाट ब्याज मात्र जोड्ने
final installmentSnapshot = await _db
    .collection('loan_installments')
    .where('status', isEqualTo: 'approved')
    .get();

int approvedInstallmentSavings = 0;

for (final doc in installmentSnapshot.docs) {
  final data = doc.data();

  if (data['isTest'] == true) {
    continue;
  }

  // साँवा रकम संस्थाको आम्दानी होइन।
  // स्वीकृत किस्ताको ब्याज मात्र कुल बचतमा जोड्ने।
  approvedInstallmentSavings +=
      _toInt(data['interestPaid']);
}
    // Donation fund_transactions बाट लिइएको छ।
// बचत जरिमाना monthly_savings बाट मात्र लिइएको छ।
// fund_transactions बाट बचत जरिमाना फेरि जोडिएको छैन,
// ताकि दोहोरो गणना नहोस्।
// ४. वास्तविक रूपमा वितरण भएका खर्च घटाउने
print('MEMBER SAVINGS = $memberSavings');
print('DONATION SAVINGS = $donationSavings');
      
      final expenseSnapshot = await _db
        .collection('fund_transactions')
        .where('fundType', isEqualTo: 'expense')
        .where('category', isEqualTo: 'expense_withdrawal')
        .where('status', isEqualTo: 'disbursed')
        .get();

    int totalExpenses = 0;
      print('EXPENSE RECORD COUNT = ${expenseSnapshot.docs.length}');

    for (final doc in expenseSnapshot.docs) {
      final data = doc.data();

      if (data['isTest'] == true) {
        continue;
      }

      totalExpenses += _toInt(data['amount']);
    }
      
        return memberSavings +
        donationSavings +
        approvedInstallmentSavings -
        totalExpenses;
  }

  // वितरण भइसकेको र बाँकी रहेको ऋण साँवा
  Future<int> calculateOutstandingLoans() async {
    final snapshot = await _db
        .collection('loans')
        .where('status', isEqualTo: 'active')
        .get();

    int outstanding = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final remaining =
          data['outstandingPrincipal'] ??
          data['remainingPrincipal'] ??
          data['disbursedAmount'] ??
          data['approvedAmount'] ??
          0;

      outstanding += _toInt(remaining);
    }

    return outstanding;
  }

  // संस्थाको उपलब्ध बचत
  Future<int> calculateAvailableSavings() async {
    final totalSavings =
        await calculateInstitutionSavings();

    final outstandingLoans =
        await calculateOutstandingLoans();

    final available = totalSavings - outstandingLoans;

    return available > 0 ? available : 0;
  }

  // स्वीकृत हुन बाँकी ऋण आवेदनको माग रकम
  Future<int> calculatePendingLoanRequests({
    String? excludeLoanId,
  }) async {
    final snapshot = await _db
    .collection('loans')
    .where(
      'status',
      whereIn: [
        'voting',
        'admin_review',
        'admin_pending',
      ],
    )
    .get();

    int pendingAmount = 0;

    for (final doc in snapshot.docs) {
      if (excludeLoanId != null &&
          doc.id == excludeLoanId) {
        continue;
      }

      final data = doc.data();

      pendingAmount +=
          _toInt(data['requestedAmount']);
    }

    return pendingAmount;
  }

  // ऋण योग्य रकम:
  // (उपलब्ध बचत - २०,०००) को ७०%
  // त्यसबाट बाँकी आवेदनको माग घटाउने
  // अधिकतम रु. ५,००,०००
  Future<int> calculateLoanEligibleAmount({
    String? excludeLoanId,
  }) async {
    final availableSavings =
        await calculateAvailableSavings();

    final afterEmergencyFund =
        availableSavings - 20000;

    if (afterEmergencyFund <= 0) {
      return 0;
    }

    final baseEligible =
        (afterEmergencyFund * 70) ~/ 100;

    final pendingRequests =
        await calculatePendingLoanRequests(
      excludeLoanId: excludeLoanId,
    );

    final eligibleAmount =
        baseEligible - pendingRequests;

    if (eligibleAmount <= 0) {
      return 0;
    }

    return eligibleAmount > 500000
        ? 500000
        : eligibleAmount;
  }
}
