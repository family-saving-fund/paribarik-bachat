
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_audit_service.dart';
import 'insurance_fund_ledger.dart';
import 'insurance_annual_limit_service.dart';

class InsurancePayoutService {
  InsurancePayoutService({
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const double minimumReserve = 5000.0;
  static const double annualInsuranceLimit = 100000.0;
  static const String insurancePayoutLockId = 'insurance_payout';

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Future<double> getInsuranceFundBalance() async {
    final aggregate = await InsuranceFundLedger(firestore: _db).stateRef.get();
    if (aggregate.exists) {
      return _toDouble(aggregate.data()?['balance']);
    }
    final savingsSnapshot =
        await _db.collection('monthly_savings').get();

    final incomeSnapshot = await _db
        .collection('fund_transactions')
        .where('fundType', isEqualTo: 'insurance')
        .get();

    final payoutSnapshot = await _db
        .collection('fund_transactions')
        .where('category', isEqualTo: 'insurance_claim_payout')
        .get();

    double totalIncome = 0.0;
    double totalPayout = 0.0;

    for (final doc in savingsSnapshot.docs) {
      final data = doc.data();

      if (data['isTest'] == true) continue;

      totalIncome += _toDouble(data['insurancePaid']);
    }

    for (final doc in incomeSnapshot.docs) {
      final data = doc.data();

      if (data['isTest'] == true) continue;

      totalIncome += _toDouble(data['amount']);
    }

    for (final doc in payoutSnapshot.docs) {
      final data = doc.data();

      if (data['isTest'] == true) continue;
      if (data['status'] != 'disbursed') continue;

      totalPayout += _toDouble(data['amount']);
    }

    return totalIncome - totalPayout;
  }

  Future<double> calculateAvailableInsuranceForClaims() async {
    final balance = await getInsuranceFundBalance();
    final available = balance - minimumReserve;

    return available > 0 ? available : 0.0;
  }

  Future<double> payApprovedClaim({
    required String claimId,
    required String adminUid,
    required String bsDate,
    required String adDate,
    double? requestedAmount,
  }) async {
    if (claimId.trim().isEmpty ||
        adminUid.trim().isEmpty ||
        bsDate.trim().isEmpty ||
        adDate.trim().isEmpty) {
      throw ArgumentError('आवश्यक विवरण अपूरो छ।');
    }

    if (requestedAmount != null && requestedAmount <= 0) {
      throw ArgumentError('भुक्तानी रकम शून्यभन्दा बढी हुनुपर्छ।');
    }

    final claimRef =
        _db.collection('insurance_claims').doc(claimId);

    final adminRef =
        _db.collection('member').doc(adminUid);

    // सबै भुक्तानी एउटै साझा Lock बाट सुरक्षित गर्ने।
    final lockRef = _db
    .collection('system_locks')
    .doc(insurancePayoutLockId);
    final payoutRef =
        _db.collection('insurance_claim_payments').doc();

    final fundRef = _db
        .collection('fund_transactions')
        .doc('insurance_claim_payout_${payoutRef.id}');

    final auditService = AdminAuditService(
      firestore: _db,
    );
    final fundLedger = InsuranceFundLedger(firestore: _db);
    final fundSeedBalance = await fundLedger.getSeedBalance();
    final annualService = InsuranceAnnualLimitService(firestore: _db);
    final claimBeforeTransaction = await claimRef.get();
    if (!claimBeforeTransaction.exists) {
      throw StateError('बीमा आवेदन भेटिएन।');
    }
    final preClaimData = claimBeforeTransaction.data()!;
    final preUid = preClaimData['uid']?.toString() ?? '';
    final preFiscalYear = annualService.fiscalYearStart(
      preClaimData['applicationDateBS']?.toString() ?? '',
    );
    if (preUid.isEmpty || preFiscalYear == null) {
      throw StateError('बीमा आवेदनको सदस्य वा BS आर्थिक वर्ष विवरण मिलेन।');
    }
    final annualRef = annualService.ref(preUid, preFiscalYear);
    final annualSeed = await annualService.getSeedReserved(preUid, preFiscalYear);

    return _db.runTransaction<double>((transaction) async {
      // आवश्यक Document पढ्ने।
      final claimSnapshot = await transaction.get(claimRef);
      final adminSnapshot = await transaction.get(adminRef);
      final lockSnapshot = await transaction.get(lockRef);
      final fundStateSnapshot = await transaction.get(fundLedger.stateRef);
      final annualSnapshot = await transaction.get(annualRef);

      if (!claimSnapshot.exists) {
        throw StateError('बीमा आवेदन भेटिएन।');
      }

      if (!adminSnapshot.exists) {
        throw StateError('Admin विवरण भेटिएन।');
      }

      final claimData = claimSnapshot.data()!;
      final adminData = adminSnapshot.data()!;
      final currentFiscalYear = annualService.fiscalYearStart(
        claimData['applicationDateBS']?.toString() ?? '',
      );

      if (currentFiscalYear != preFiscalYear) {
        throw StateError('बीमा आवेदनको आर्थिक वर्ष परिवर्तन भएको छ। फेरि प्रयास गर्नुहोस्।');
      }

      if (adminData['role'] != 'admin') {
        throw StateError('यो काम गर्ने अनुमति Admin लाई मात्र छ।');
      }

      if (claimData['status'] != 'approved') {
        throw StateError('स्वीकृत नभएको बीमा भुक्तानी गर्न मिल्दैन।');
      }

      final memberUid =
          claimData['uid']?.toString() ?? '';

      if (memberUid.isEmpty || memberUid != preUid) {
        throw StateError('सदस्यको UID भेटिएन वा आवेदन परिवर्तन भएको छ।');
      }
      final reservedAnnualAmount = annualSnapshot.exists
          ? _toDouble(annualSnapshot.data()?['reservedAmount'])
          : annualSeed;
      if (reservedAnnualAmount > annualInsuranceLimit + 0.001) {
        throw StateError(
          'यस सदस्य र परिवारको यस BS आर्थिक वर्षको दाबी रु. १,००,००० सीमा नाघेको छ। '
          'Admin ले पुराना आवेदन जाँच गर्नुपर्छ।',
        );
      }

      final memberName =
          claimData['memberName']?.toString() ?? '';

      final claimantName =
          claimData['claimantName']?.toString() ?? '';

      final approvedAmount = _toDouble(
        claimData['approvedAmount'] ??
        claimData['insuranceAmount'],
      );

      final paidAmount =
          _toDouble(claimData['paidAmount']);

      final remainingAmount = _toDouble(
        claimData['remainingAmount'] ??
        (approvedAmount - paidAmount),
      );

      if (remainingAmount <= 0) {
        throw StateError('यस बीमाको भुक्तानी पूरा भइसकेको छ।');
      }

      final payoutAmount =
          requestedAmount ?? remainingAmount;

      if (payoutAmount <= 0 ||
          payoutAmount > remainingAmount) {
        throw StateError('भुक्तानी रकम बाँकी रकमभन्दा बढी भयो।');
      }

      // Fund balance is read from the shared aggregate inside this transaction.
      // Every in-app insurance-income writer updates the same document atomically.
      final insuranceBalance = fundStateSnapshot.exists
          ? _toDouble(fundStateSnapshot.data()?['balance'])
          : fundSeedBalance;
      final availableBalance = insuranceBalance - minimumReserve;

      if (availableBalance < payoutAmount) {
        throw StateError(
          'बीमा कोषमा पर्याप्त उपलब्ध रकम छैन। '
          'न्यूनतम रु. ५,००० सुरक्षित राख्नुपर्छ।',
        );
      }

      final newPaidAmount =
          paidAmount + payoutAmount;

      final newRemainingAmount =
          approvedAmount - newPaidAmount;

      final paymentStatus =
          newRemainingAmount <= 0.001
              ? 'paid'
              : 'partial';

      final adminName =
          adminData['name']?.toString() ?? 'Admin';

      // Audit record पनि transaction भित्र सुरक्षित गर्ने।
      await auditService.recordInTransaction(
        transaction: transaction,
        eventId: 'insurance_payout_${payoutRef.id}',
        adminUid: adminUid,
        adminName: adminName,
        action: 'insurance_claim_payout',
        targetCollection: 'insurance_claims',
        targetDocumentId: claimId,
        description: 'बीमा दाबी भुक्तानी',
        memberUid: memberUid,
        memberName: memberName,
        amount: payoutAmount,
        oldValues: {
          'paidAmount': paidAmount,
          'remainingAmount': remainingAmount,
        },
        newValues: {
          'paidAmount': newPaidAmount,
          'remainingAmount': newRemainingAmount,
          'paymentStatus': paymentStatus,
        },
        metadata: {
          'paymentId': payoutRef.id,
          'bsDate': bsDate,
          'adDate': adDate,
          'claimantName': claimantName,
        },
      );

      // भुक्तानीको छुट्टै इतिहास।
      transaction.set(payoutRef, {
        'claimId': claimId,
        'uid': memberUid,
        'memberName': memberName,
        'claimantName': claimantName,
        'amount': payoutAmount,
        'bsDate': bsDate,
        'adDate': adDate,
        'adminUid': adminUid,
        'adminName': adminName,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // बीमा कोषबाट घटाउने Transaction।
      transaction.set(fundRef, {
        'fundType': 'expense',
        'category': 'insurance_claim_payout',
        'status': 'disbursed',
        'transactionType': 'debit',
        'amount': payoutAmount,
        'claimId': claimId,
        'paymentId': payoutRef.id,
        'uid': memberUid,
        'memberName': memberName,
        'claimantName': claimantName,
        'bsDate': bsDate,
        'adDate': adDate,
        'createdBy': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // मूल बीमा आवेदनको भुक्तानी विवरण अद्यावधिक।
      transaction.update(claimRef, {
        'paidAmount': newPaidAmount,
        'remainingAmount': newRemainingAmount,
        'paymentStatus': paymentStatus,
        'lastPaymentBS': bsDate,
        'lastPaymentAD': adDate,
        'lastPaymentAt': FieldValue.serverTimestamp(),
        'paymentHistory': FieldValue.arrayUnion([
          {
            'paymentId': payoutRef.id,
            'amount': payoutAmount,
            'bsDate': bsDate,
            'adDate': adDate,
            'adminUid': adminUid,
          }
        ]),
      });

      if (!annualSnapshot.exists) {
        transaction.set(annualRef, {
          'uid': memberUid,
          'fiscalYearStart': preFiscalYear,
          'reservedAmount': reservedAnnualAmount,
          'limitAmount': annualInsuranceLimit,
          'revision': 1,
          'lastAction': 'initialize',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // साझा Lock अद्यावधिक गर्दा समानान्तर भुक्तानीमा
      // Transaction conflict भएर पुनः जाँच हुन्छ।
      final oldRevision = lockSnapshot.exists
          ? (lockSnapshot.data()?['revision'] as num?)?.toInt() ?? 0
          : 0;

      transaction.set(
        lockRef,
        {
          'revision': oldRevision + 1,
          'lastPayoutId': payoutRef.id,
          'lastPayoutAt': FieldValue.serverTimestamp(),
          'updatedBy': adminUid,
        },
        SetOptions(merge: true),
      );

      fundLedger.applyDelta(
        transaction: transaction,
        stateSnapshot: fundStateSnapshot,
        seedBalance: fundSeedBalance,
        delta: -payoutAmount,
      );

      return payoutAmount;
    });
  }
}
