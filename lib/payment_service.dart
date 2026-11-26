import 'package:cloud_firestore/cloud_firestore.dart';
import 'penalty_service.dart';
import 'financial_ledger_service.dart';
import 'admin_audit_service.dart';
import 'notification_service.dart';
import 'insurance_fund_ledger.dart';
import 'member_account_guard.dart';
import 'discipline_points_service.dart';

class PaymentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
    
  final FinancialLedgerService _ledgerService = FinancialLedgerService();
    
  final AdminAuditService _auditService = AdminAuditService();

  CollectionReference<Map<String, dynamic>> get _payments =>
      _db.collection('payments');

  CollectionReference<Map<String, dynamic>> get _monthlySavings =>
      _db.collection('monthly_savings');

  CollectionReference<Map<String, dynamic>> get _paymentLocks =>
      _db.collection('payment_locks');
  CollectionReference<Map<String, dynamic>> get _fundTransactions =>
      _db.collection('fund_transactions');

  /// सदस्यले भुक्तानी पेस गर्दा Pending रेकर्ड बनाउँछ।
  ///
  /// एउटै सदस्यको अर्को Pending भुक्तानी भए नयाँ भुक्तानी रोक्छ।
  /// Lock र Payment एउटै transaction मा लेखिन्छन्।
  Future<String> submitPayment({
    required String memberUid,
    required String memberName,
    required String paymentType,
    required int amount,
    required String bsDate,
    required String adDate,
    required List<String> monthKeys,
    String? voucherUrl,
    String? note,
  }) async {
    if (memberUid.trim().isEmpty) {
      throw ArgumentError('सदस्य UID आवश्यक छ।');
    }
    await MemberAccountGuard.ensureActive(memberUid);

    if (memberName.trim().isEmpty) {
      throw ArgumentError('सदस्यको नाम आवश्यक छ।');
    }

    const allowedTypes = {'full', 'partial', 'donation'};

    if (!allowedTypes.contains(paymentType)) {
      throw ArgumentError('भुक्तानीको प्रकार मिलेन।');
    }

    if (amount <= 0) {
      throw ArgumentError('भुक्तानी रकम शून्यभन्दा बढी हुनुपर्छ।');
    }

    if (bsDate.trim().isEmpty || adDate.trim().isEmpty) {
      throw ArgumentError('BS र AD मिति आवश्यक छन्।');
    }
    if (paymentType == 'donation' &&
        DisciplinePointsService.donationMonthKey(bsDate) == null) {
      throw ArgumentError('दानको BS मिति सही ढाँचामा लेख्नुहोस्। उदाहरण: 2083 साल कार्तिक 15 गते');
    }

    if (paymentType != 'donation' && monthKeys.isEmpty) {
      throw ArgumentError('भुक्तानीको महिना छान्नुहोस्।');
    }

    if (monthKeys.any((key) => key.trim().isEmpty)) {
      throw ArgumentError('महिनाको विवरण मिलेन।');
    }

    if (monthKeys.toSet().length != monthKeys.length) {
      throw ArgumentError('एउटै महिना दोहोर्‍याएर छानिएको छ।');
    }

    // पुरानो प्रणालीबाट बनेका Pending रेकर्ड पनि जाँच्ने।
    final pendingSnapshot = await _payments
        .where('memberUid', isEqualTo: memberUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (pendingSnapshot.docs.isNotEmpty) {
      throw StateError(
        'तपाईंको भुक्तानी समीक्षा गरिँदैछ। '
        'कृपया Admin को निर्णय पर्खनुहोस्।',
      );
    }

    final paymentRef = _payments.doc();
    final lockRef = _paymentLocks.doc(memberUid);

    await _db.runTransaction((transaction) async {
        
      // Transaction भित्र lock जाँच्दा एकै समयमा आएका
      // अनुरोधहरू एउटै सदस्यका लागि सुरक्षित हुन्छन्।
      final lockSnapshot = await transaction.get(lockRef);

      if (lockSnapshot.exists) {
        final lockedPaymentId =
            lockSnapshot.data()?['pendingPaymentId']?.toString();

        if (lockedPaymentId != null && lockedPaymentId.isNotEmpty) {
          final lockedPaymentRef = _payments.doc(lockedPaymentId);
          final lockedPaymentSnapshot = await transaction.get(lockedPaymentRef);

          if (lockedPaymentSnapshot.exists &&
              lockedPaymentSnapshot.data()?['status'] == 'pending') {
            throw StateError(
              'तपाईंको भुक्तानी समीक्षा गरिँदैछ। '
              'कृपया Admin को निर्णय पर्खनुहोस्।',
            );
          }
        }
      }

      transaction.set(paymentRef, {
        'paymentId': paymentRef.id,
        'memberUid': memberUid,
        'memberName': memberName,
        'paymentType': paymentType,
        'amount': amount,
        'bsDate': bsDate,
        'adDate': adDate,
        'monthKeys': monthKeys,
        'voucherUrl': voucherUrl,
        'note': note,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
        'adminNote': null,
      });

      transaction.set(lockRef, {
        'memberUid': memberUid,
        'pendingPaymentId': paymentRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    try {
      await NotificationService.sendToAdmins(
        title: 'नयाँ भुक्तानी प्राप्त भयो',
        message: '$memberName ले रु. $amount भुक्तानी पेस गर्नुभएको छ।',
        type: 'payment_submitted',
        relatedId: paymentRef.id,
      );
    } catch (e) {
      print('Payment submission notification error: $e');
    }

    return paymentRef.id;
  }

  /// सदस्यका आफ्नै भुक्तानी हेर्ने।
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMemberPayments(
    String memberUid,
  ) {
    return _payments.where('memberUid', isEqualTo: memberUid).snapshots();
  }

  /// Admin का लागि Pending भुक्तानी हेर्ने।
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingPayments() {
    return _payments.where('status', isEqualTo: 'pending').snapshots();
  }

  /// समीक्षा सकिएपछि यही भुक्तानीको Pending lock मात्र हटाउँछ।
  void _releaseLockIfOwned({
    required Transaction transaction,
    required DocumentSnapshot<Map<String, dynamic>> lockSnapshot,
    required DocumentReference<Map<String, dynamic>> lockRef,
    required String paymentId,
  }) {
    final lockedPaymentId =
        lockSnapshot.data()?['pendingPaymentId']?.toString();

    if (lockSnapshot.exists && lockedPaymentId == paymentId) {
      transaction.delete(lockRef);
    }
  }

  /// Admin ले Pending भुक्तानी अस्वीकार गर्ने।
  Future<void> rejectPayment({
    required String paymentId,
    required String adminUid,
    required String reason,
  }) async {
    if (paymentId.trim().isEmpty ||
        adminUid.trim().isEmpty ||
        reason.trim().isEmpty) {
      throw ArgumentError(
        'भुक्तानी ID, Admin UID र अस्वीकृतिको कारण आवश्यक छन्।',
      );
    }

    final paymentRef = _payments.doc(paymentId);

    // सदस्य UID बाट सम्बन्धित lock पत्ता लगाउने।
    final initialSnapshot = await paymentRef.get();

    if (!initialSnapshot.exists) {
      throw StateError('भुक्तानी रेकर्ड भेटिएन।');
    }

    final memberUid = initialSnapshot.data()?['memberUid']?.toString() ?? '';

    if (memberUid.isEmpty) {
      throw StateError('सदस्यको विवरण भेटिएन।');
    }

    final lockRef = _paymentLocks.doc(memberUid);

    await _db.runTransaction((transaction) async {
      final paymentSnapshot = await transaction.get(paymentRef);
        
      final lockSnapshot = await transaction.get(lockRef);
        
        final adminSnapshot = await transaction.get(
  _db.collection('member').doc(adminUid),
);

final adminName =
    adminSnapshot.data()?['name']?.toString() ?? adminUid;

      if (!paymentSnapshot.exists) {
        throw StateError('भुक्तानी रेकर्ड भेटिएन।');
      }

      final payment = paymentSnapshot.data()!;

      if (payment['memberUid']?.toString() != memberUid) {
        throw StateError('भुक्तानीको सदस्य विवरण परिवर्तन भएको छ।');
      }

      if (payment['status'] != 'pending') {
        throw StateError('यो भुक्तानी पहिले नै समीक्षा गरिएको छ।');
      }
        
   await _auditService.recordInTransaction(
  transaction: transaction,
  eventId: 'payment_rejected_$paymentId',
  adminUid: adminUid,
  adminName: adminName,
  action: 'payment_rejected',
  targetCollection: 'payments',
  targetDocumentId: paymentId,
  description: 'Admin ले भुक्तानी अस्वीकृत गर्नुभयो।',
  memberUid: memberUid,
  memberName: payment['memberName']?.toString() ?? '',
  amount: (payment['amount'] as num?)?.toInt() ?? 0,
  reason: reason.trim(),
  oldValues: {
    'status': 'pending',
  },
  newValues: {
    'status': 'rejected',
    'adminNote': reason.trim(),
  },
);

      transaction.update(paymentRef, {
        'status': 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminUid,
        'adminNote': reason.trim(),
      });

      _releaseLockIfOwned(
        transaction: transaction,
        lockSnapshot: lockSnapshot,
        lockRef: lockRef,
        paymentId: paymentId,
      );
    });
    try {
      await NotificationService.sendToMember(
        memberUid: memberUid,
        title: 'भुक्तानी अस्वीकृत भयो',
        message: 'तपाईंको भुक्तानी अस्वीकृत भएको छ। कारण: ${reason.trim()}',
        type: 'payment_rejected',
        relatedId: paymentId,
      );
    } catch (e) {
      print('Payment rejection notification error: $e');
    }
  }

  /// Admin ले Pending भुक्तानी स्वीकृत गर्ने।
  ///
  /// मासिक भुक्तानीमा पहिले बाँकी बीमा र त्यसपछि बचतमा
  /// रकम छुट्याइन्छ। Donation व्यक्तिगत बचतमा जोडिँदैन।

  Future<void> approvePayment({
    required String paymentId,
    required String adminUid,
    required int approvedAmount,
    String adminNote = '',
  }) async {
    if (paymentId.trim().isEmpty ||
        adminUid.trim().isEmpty ||
        approvedAmount <= 0) {
      throw ArgumentError(
        'भुक्तानी ID, Admin UID र सही रकम आवश्यक छन्।',
      );
    }

    final paymentRef = _payments.doc(paymentId);
    // स्वीकृतिअघि भुक्तानीको सदस्य विवरण पढ्ने।
    final initialPaymentSnapshot = await paymentRef.get();

    if (!initialPaymentSnapshot.exists) {
      throw StateError('भुक्तानी रेकर्ड भेटिएन।');
    }

    final initialPayment = initialPaymentSnapshot.data()!;
    final initialMemberUid = initialPayment['memberUid']?.toString() ?? '';
    final initialPaymentType = initialPayment['paymentType']?.toString() ?? '';

    if (initialMemberUid.isEmpty) {
      throw StateError('सदस्यको विवरण भेटिएन।');
    }

// महिनाअनुसार बाँकी जरिमानाको विवरण पढ्ने।
    Map<String, dynamic> penaltyDetailsByMonth = {};

    if (initialPaymentType == 'full' || initialPaymentType == 'partial') {
      final penaltyData = await PenaltyService().calculateMemberPenalty(
        memberUid: initialMemberUid,
      );

      penaltyDetailsByMonth = Map<String, dynamic>.from(
        penaltyData['penaltyDetailsByMonth'] as Map? ?? {},
      );
    }

    final insuranceFundLedger = InsuranceFundLedger(firestore: _db);
    final insuranceFundSeed = await insuranceFundLedger.getSeedBalance();

    await _db.runTransaction((transaction) async {
      // १. Payment पढ्ने।
      final paymentSnapshot = await transaction.get(paymentRef);

      if (!paymentSnapshot.exists) {
        throw StateError('भुक्तानी रेकर्ड भेटिएन।');
      }

      final payment = paymentSnapshot.data()!;

      if (payment['status'] != 'pending') {
        throw StateError('यो भुक्तानी पहिले नै समीक्षा गरिएको छ।');
      }

      final paymentType = payment['paymentType']?.toString() ?? '';
      final memberUid = payment['memberUid']?.toString() ?? '';
      final originalAmount = (payment['amount'] as num?)?.toInt() ?? 0;

      if (memberUid.isEmpty || originalAmount <= 0) {
        throw StateError('भुक्तानी रेकर्डको विवरण मिलेन।');
      }

      if (approvedAmount > originalAmount) {
        throw StateError(
          'स्वीकृत रकम पेस गरिएको रकमभन्दा बढी हुन मिल्दैन।',
        );
      }

      // २. Lock पढ्ने। सबै लेखाइ अघि आवश्यक read पूरा गर्ने।
      final lockRef = _paymentLocks.doc(memberUid);
      final lockSnapshot = await transaction.get(lockRef);
        
       final adminSnapshot = await transaction.get(
        _db.collection('member').doc(adminUid),
      );

      final adminName =
          adminSnapshot.data()?['name']?.toString() ?? adminUid;
      // सबै बीमा आम्दानी/खर्च एउटै aggregate document मा serialize हुन्छन्।
      final insuranceFundStateSnapshot =
          await transaction.get(insuranceFundLedger.stateRef);

      // ३. Donation को स्वीकृति। दान अंक नेपाली महिनाको १ गतेदेखि
      // मसान्तसम्मको कुल रकमका आधारमा क्रमिक रूपमा समायोजन हुन्छ।
      if (paymentType == 'donation') {
        final donationBsDate = payment['bsDate']?.toString() ?? '';
        final donationMonthKey =
            DisciplinePointsService.donationMonthKey(donationBsDate);
        if (donationMonthKey == null) {
          throw StateError('दानको BS मिति सही ढाँचामा छैन। उदाहरण: 2083 साल कार्तिक 15 गते');
        }

        final donationMemberRef = _db.collection('member').doc(memberUid);
        final donationMemberSnapshot = await transaction.get(donationMemberRef);
        if (!donationMemberSnapshot.exists) {
          throw StateError('दान गर्ने सदस्यको विवरण भेटिएन।');
        }
        final donationSummaryRef = _db
            .collection('discipline_donation_months')
            .doc('${memberUid}_$donationMonthKey');
        final donationSummarySnapshot = await transaction.get(donationSummaryRef);
        final donationPointHistoryRef =
            _db.collection('discipline_point_history').doc(paymentId);
        final donationPointHistorySnapshot =
            await transaction.get(donationPointHistoryRef);
        if (donationPointHistorySnapshot.exists) {
          throw StateError('यो दानको अनुशासन अंक पहिले नै गणना भएको छ।');
        }

        final previousDonationTotal =
            (donationSummarySnapshot.data()?['donationTotal'] as num?)?.toInt() ?? 0;
        final previousAwardedPoints =
            (donationSummarySnapshot.data()?['pointsAwarded'] as num?)?.toInt() ?? 0;
        final newDonationTotal = previousDonationTotal + approvedAmount;
        final targetDonationPoints =
            DisciplinePointsService.donationTargetPoints(newDonationTotal);
        final donationPointsDelta = DisciplinePointsService.donationPointDelta(
          previousTotal: previousDonationTotal,
          previousPointsAwarded: previousAwardedPoints,
          newDonationAmount: approvedAmount,
        );
        if (donationPointsDelta < 0) {
          throw StateError('दानको अनुशासन अंकको पुरानो हिसाब मिलेन।');
        }
        final oldDonationPoints =
            (donationMemberSnapshot.data()?['disciplinePoints'] as num?)?.toInt() ?? 0;
        final newDonationPoints = oldDonationPoints + donationPointsDelta;

        final insuranceDonation = approvedAmount ~/ 2;
        final institutionDonation = approvedAmount - insuranceDonation;
final donationLedgerEvents = [
  {
    'eventId': 'payment_approved_$paymentId',
    'memberUid': memberUid,
    'memberName': payment['memberName']?.toString() ?? '',
    'transactionType': 'donation',
    'amount': approvedAmount,
    'bsDate': payment['bsDate']?.toString() ?? '',
    'description': payment['note']?.toString().trim().isNotEmpty == true
        ? payment['note'].toString()
        : 'चन्दा / दान',
    'sourceCollection': 'payments',
    'sourceDocumentId': paymentId,
    'recordedByUid': adminUid,
    'recordedByName': adminName,
    'status': 'approved',
    'metadata': {
      'insuranceAmount': insuranceDonation,
      'institutionSavingsAmount': institutionDonation,
      'donationMonthKey': donationMonthKey,
      'disciplinePointsDelta': donationPointsDelta,
      'disciplinePointsTarget': targetDonationPoints,
    },
  },
];

final donationLedgerRefs =
    await _ledgerService.prepareManyInTransaction(
  transaction: transaction,
  events: donationLedgerEvents,
);

final donationAuditRef =
    await _auditService.prepareRecordInTransaction(
  transaction: transaction,
  eventId: 'payment_approved_$paymentId',
);

insuranceFundLedger.applyDelta(
  transaction: transaction,
  stateSnapshot: insuranceFundStateSnapshot,
  seedBalance: insuranceFundSeed,
  delta: insuranceDonation.toDouble(),
);

        transaction.set(donationSummaryRef, {
          'memberUid': memberUid,
          'nepaliMonthKey': donationMonthKey,
          'donationTotal': newDonationTotal,
          'pointsAwarded': targetDonationPoints,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastPaymentId': paymentId,
        }, SetOptions(merge: true));

        if (donationPointsDelta != 0) {
          transaction.update(donationMemberRef, {
            'disciplinePoints': newDonationPoints,
            'disciplinePointsUpdatedAt': FieldValue.serverTimestamp(),
          });
        }
        transaction.set(donationPointHistoryRef, {
          'memberUid': memberUid,
          'memberName': payment['memberName']?.toString() ?? '',
          'paymentId': paymentId,
          'paymentType': 'donation',
          'bsDate': donationBsDate,
          'nepaliMonthKey': donationMonthKey,
          'donationAmount': approvedAmount,
          'monthlyDonationTotal': newDonationTotal,
          'pointsDelta': donationPointsDelta,
          'targetPointsAfterDonation': targetDonationPoints,
          'balanceAfter': newDonationPoints,
          'reason': newDonationTotal < 100
              ? 'यो नेपाली महिनाको कुल दान रु. १०० नपुगेकाले अंक लागू भएन'
              : 'यो नेपाली महिनाको कुल दान रु. $newDonationTotal को १०% अनुशासन अंक समायोजन',
          'createdAt': FieldValue.serverTimestamp(),
        });

        _ledgerService.writePreparedManyInTransaction(
          transaction: transaction,
          refs: donationLedgerRefs,
          events: donationLedgerEvents,
        );

_auditService.writePreparedRecordInTransaction(
  transaction: transaction,
  auditRef: donationAuditRef,
  data: {
    'adminUid': adminUid,
    'adminName': adminName,
    'action': 'payment_approved',
    'targetCollection': 'payments',
    'targetDocumentId': paymentId,
    'description': 'Admin ले चन्दा / दान भुक्तानी स्वीकृत गर्नुभयो।',
    'memberUid': memberUid,
    'memberName': payment['memberName']?.toString() ?? '',
    'amount': approvedAmount,
    'oldValues': {'status': 'pending'},
    'newValues': {
      'status': 'approved',
      'approvedAmount': approvedAmount,
      'donationMonthKey': donationMonthKey,
      'monthlyDonationTotal': newDonationTotal,
      'disciplinePointsDelta': donationPointsDelta,
      'disciplinePointsTarget': targetDonationPoints,
    },
  },
);


        transaction.update(paymentRef, {
          'submittedAmount': originalAmount,
          'approvedAmount': approvedAmount,
          'donationInsuranceAmount': insuranceDonation,
          'donationInstitutionAmount': institutionDonation,
          'donationMonthKey': donationMonthKey,
          'disciplinePointsDelta': donationPointsDelta,
          'disciplinePointsReason': 'नेपाली महिनाको कुल दान रु. $newDonationTotal को १०% अंक समायोजन',
          'status': 'approved',
          'reviewedAt': FieldValue.serverTimestamp(),
          'reviewedBy': adminUid,
          'adminNote': adminNote.trim(),
        });

        // Donation को बचत हिस्सा संस्थाको कुल बचत कोषमा।
        if (institutionDonation > 0) {
          final savingsDonationRef = _fundTransactions.doc(
            '${paymentId}_donation_savings',
          );

          transaction.set(savingsDonationRef, {
            'paymentId': paymentId,
            'memberUid': memberUid,
            'memberName': payment['memberName']?.toString() ?? '',
            'fundType': 'savings',
            'category': 'donation',
            'amount': institutionDonation,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // Donation को बीमा हिस्सा संस्थाको बीमा कोषमा।
        if (insuranceDonation > 0) {
          final insuranceDonationRef = _fundTransactions.doc(
            '${paymentId}_donation_insurance',
          );

          transaction.set(insuranceDonationRef, {
            'paymentId': paymentId,
            'memberUid': memberUid,
            'memberName': payment['memberName']?.toString() ?? '',
            'fundType': 'insurance',
            'category': 'donation',
            'amount': insuranceDonation,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        _releaseLockIfOwned(
          transaction: transaction,
          lockSnapshot: lockSnapshot,
          lockRef: lockRef,
          paymentId: paymentId,
        );

        return;
      }

      // ४. मासिक भुक्तानीको प्रकार जाँच्ने।
      if (paymentType != 'full' && paymentType != 'partial') {
        throw StateError('भुक्तानीको प्रकार पहिचान भएन।');
      }

      final rawMonthKeys = payment['monthKeys'];

      if (rawMonthKeys is! List || rawMonthKeys.isEmpty) {
        throw StateError('भुक्तानीमा कुनै महिना छानिएको छैन।');
      }

      final monthKeys = rawMonthKeys.map((key) => key.toString()).toList();

      if (monthKeys.any((key) => key.trim().isEmpty)) {
        throw StateError('भुक्तानीको महिना विवरण मिलेन।');
      }

      if (monthKeys.toSet().length != monthKeys.length) {
        throw StateError('एउटै महिना दोहोरिएको छ।');
      }

      // ५. सबै मासिक रेकर्ड पढ्ने; लेखाइ अझै सुरु भएको छैन।
      final monthRefs = monthKeys
          .map((key) => _monthlySavings.doc('${memberUid}_$key'))
          .toList();

      final monthSnapshots = <DocumentSnapshot<Map<String, dynamic>>>[];

      for (final monthRef in monthRefs) {
        monthSnapshots.add(await transaction.get(monthRef));
      }

      // अनुशासन अंक र आंशिक भुक्तानी गणना पनि सबै लेखाइअघि पढ्ने।
      final memberRef = _db.collection('member').doc(memberUid);
      final memberSnapshot = await transaction.get(memberRef);
      if (!memberSnapshot.exists) {
        throw StateError('अनुशासन अंक अद्यावधिक गर्न सदस्य भेटिएन।');
      }
      final pointHistoryRef =
          _db.collection('discipline_point_history').doc(paymentId);
      final pointHistorySnapshot = await transaction.get(pointHistoryRef);
      final partialMonthRef = paymentType == 'partial' && monthKeys.length == 1
          ? _db.collection('discipline_point_months').doc(
              '${memberUid}_${monthKeys.single}',
            )
          : null;
      final partialMonthSnapshot = partialMonthRef == null
          ? null
          : await transaction.get(partialMonthRef);
      final previousPartialCount =
          (partialMonthSnapshot?.data()?['partialPaymentCount'] as num?)
                  ?.toInt() ??
              0;

      var amountLeft = approvedAmount;
      final updates = <Map<String, dynamic>>[];
      final fundEntries = <Map<String, dynamic>>[];
      final ledgerEvents = <Map<String, dynamic>>[];
      var insuranceFundDelta = 0.0;

// पुरानो महिनाबाट सुरु गरेर रकम बाँड्ने।
      for (var i = 0; i < monthSnapshots.length; i++) {
        final snapshot = monthSnapshots[i];

        if (!snapshot.exists) {
          throw StateError(
            'महिना ${monthKeys[i]} को मासिक रेकर्ड भेटिएन।',
          );
        }

        final data = snapshot.data()!;

        final totalDue = (data['totalDue'] as num?)?.toInt() ?? 0;
        final insuranceAmount = (data['insuranceAmount'] as num?)?.toInt() ?? 0;
        final paidAmount = (data['paidAmount'] as num?)?.toInt() ?? 0;

        if (totalDue <= 0 ||
            insuranceAmount < 0 ||
            paidAmount < 0 ||
            paidAmount > totalDue ||
            insuranceAmount > totalDue) {
          throw StateError(
            '${monthKeys[i]} महिनाको रकमको विवरण जाँच गर्नुहोस्।',
          );
        }

        final hasInsurancePaid = data.containsKey('insurancePaid');
        final hasSavingsPaid = data.containsKey('savingsPaid');

        if ((!hasInsurancePaid || !hasSavingsPaid) && paidAmount > 0) {
          throw StateError(
            '${monthKeys[i]} महिनामा पहिले भुक्तानी भएको छ, '
            'तर बीमा/बचतको विवरण अपूरो छ। पहिले हिसाब मिलाउनुहोस्।',
          );
        }

        final insurancePaid = (data['insurancePaid'] as num?)?.toInt() ?? 0;
        final savingsPaid = (data['savingsPaid'] as num?)?.toInt() ?? 0;

        if (insurancePaid < 0 ||
            savingsPaid < 0 ||
            insurancePaid > insuranceAmount ||
            insurancePaid + savingsPaid != paidAmount) {
          throw StateError(
            '${monthKeys[i]} महिनाको बचत/बीमा हिसाब मिलेन।',
          );
        }

        final savingsAmount = totalDue - insuranceAmount;

        final insuranceRemaining = insuranceAmount - insurancePaid;
        final savingsRemaining = savingsAmount - savingsPaid;

        if (amountLeft <= 0) continue;

        // यस महिनाको बाँकी जरिमाना पढ्ने।
        final penaltyDetails = Map<String, dynamic>.from(
          penaltyDetailsByMonth[monthKeys[i]] as Map? ?? {},
        );

        final insurancePenaltyDue =
            (penaltyDetails['insurancePenaltyDue'] as num?)?.toInt() ?? 0;

        final savingsPenaltyDue =
            (penaltyDetails['savingsPenaltyDue'] as num?)?.toInt() ?? 0;

        final isSpecial = penaltyDetails['isSpecial50Percent'] == true;

        if (insurancePenaltyDue < 0 || savingsPenaltyDue < 0) {
          throw StateError(
            '${monthKeys[i]} महिनाको जरिमाना विवरण मिलेन।',
          );
        }

        // बीमा बाँकी छ भने बीमा र बीमासम्बन्धी जरिमाना दुवै पूरा चाहिन्छ।
        if (insuranceRemaining > 0 &&
            amountLeft < insuranceRemaining + insurancePenaltyDue) {
          throw StateError(
            '${monthKeys[i]} महिनाको बाँकी बीमा रु. '
            '$insuranceRemaining र बीमासम्बन्धी जरिमाना रु. '
            '$insurancePenaltyDue सहित जम्मा रकम पहिले तिर्नुपर्छ।',
          );
        }

        // १. पहिले बीमासम्बन्धी जरिमाना।
        final insurancePenaltyApplied =
            amountLeft < insurancePenaltyDue ? amountLeft : insurancePenaltyDue;

        amountLeft -= insurancePenaltyApplied;

        // २. त्यसपछि बीमाको साँवा।
        final insurancePart =
            amountLeft < insuranceRemaining ? amountLeft : insuranceRemaining;

        amountLeft -= insurancePart;

        // ३. त्यसपछि बचततर्फको जरिमाना।
        final savingsPenaltyApplied =
            amountLeft < savingsPenaltyDue ? amountLeft : savingsPenaltyDue;

        amountLeft -= savingsPenaltyApplied;

        // ४. अन्त्यमा सदस्यको व्यक्तिगत बचत।
        final savingsPart =
            amountLeft < savingsRemaining ? amountLeft : savingsRemaining;

        amountLeft -= savingsPart;

        final newInsurancePaid = insurancePaid + insurancePart;
        final newSavingsPaid = savingsPaid + savingsPart;
        final newPaidAmount = paidAmount + insurancePart + savingsPart;

        final totalPenaltyApplied =
            insurancePenaltyApplied + savingsPenaltyApplied;
        insuranceFundDelta += (insurancePart + insurancePenaltyApplied).toDouble();
          
          ledgerEvents.add({
  'eventId': '${paymentId}_${monthKeys[i]}',
  'memberUid': memberUid,
  'memberName': payment['memberName']?.toString() ?? '',
  'transactionType': 'monthly_payment',
  'amount': insurancePart +
      savingsPart +
      insurancePenaltyApplied +
      savingsPenaltyApplied,
  'bsDate': payment['bsDate']?.toString() ?? '',
  'description': 'महिना ${monthKeys[i]} को बचत तथा जरिमाना भुक्तानी',
  'sourceCollection': 'payments',
  'sourceDocumentId': paymentId,
  'recordedByUid': adminUid,
  'recordedByName': adminName,
  'status': 'approved',
  'metadata': {
    'monthKey': monthKeys[i],
    'insuranceSavingsAmount': insurancePart,
    'personalSavingsAmount': savingsPart,
    'insurancePenaltyAmount': insurancePenaltyApplied,
    'savingsPenaltyAmount': savingsPenaltyApplied,
    'penaltyType': isSpecial ? 'special' : 'normal',
  },
});
          
        // बीमा जरिमाना संस्थाको बीमा कोषमा जम्मा गर्ने।
        if (insurancePenaltyApplied > 0) {
          fundEntries.add({
            'id': '${paymentId}_${monthKeys[i]}_insurance_penalty',
            'data': {
              'paymentId': paymentId,
              'memberUid': memberUid,
              'memberName': payment['memberName']?.toString() ?? '',
              'monthKey': monthKeys[i],
              'fundType': 'insurance',
              'category': 'insurance_penalty',
              'penaltyType': isSpecial ? 'special' : 'normal',
              'amount': insurancePenaltyApplied,
              'createdAt': FieldValue.serverTimestamp(),
            },
          });
        }

// बचत जरिमाना संस्थाको कुल बचत कोषमा जम्मा गर्ने।
        if (savingsPenaltyApplied > 0) {
          fundEntries.add({
            'id': '${paymentId}_${monthKeys[i]}_savings_penalty',
            'data': {
              'paymentId': paymentId,
              'memberUid': memberUid,
              'memberName': payment['memberName']?.toString() ?? '',
              'monthKey': monthKeys[i],
              'fundType': 'savings',
              'category': 'savings_penalty',
              'penaltyType': isSpecial ? 'special' : 'normal',
              'amount': savingsPenaltyApplied,
              'createdAt': FieldValue.serverTimestamp(),
            },
          });
        }

        final oldPenaltyPaid = (data['penaltyPaid'] as num?)?.toInt() ?? 0;

        final oldPenaltyDue = (data['penaltyDue'] as num?)?.toInt() ?? 0;

        final remainingPenalty =
            (insurancePenaltyDue - insurancePenaltyApplied) +
                (savingsPenaltyDue - savingsPenaltyApplied);

        final updateData = <String, dynamic>{
          'insurancePaid': newInsurancePaid,
          'savingsPaid': newSavingsPaid,
          'paidAmount': newPaidAmount,
          'penaltyPaid': oldPenaltyPaid + totalPenaltyApplied,
          'penaltyDue': remainingPenalty,
          'status': newPaidAmount >= totalDue && remainingPenalty == 0
              ? 'paid'
              : 'partial',
          'lastPaymentAt': FieldValue.serverTimestamp(),
        };

        // जरिमानाको प्रकारअनुसार छुट्टाछुट्टै अभिलेख राख्ने।
        if (isSpecial) {
          updateData['specialInsurancePenaltyPaid'] =
              ((data['specialInsurancePenaltyPaid'] as num?)?.toInt() ?? 0) +
                  insurancePenaltyApplied;

          updateData['specialSavingsPenaltyPaid'] =
              ((data['specialSavingsPenaltyPaid'] as num?)?.toInt() ?? 0) +
                  savingsPenaltyApplied;

          updateData['specialPenaltyPaid'] =
              ((data['specialPenaltyPaid'] as num?)?.toInt() ?? 0) +
                  totalPenaltyApplied;
        } else {
          updateData['normalInsurancePenaltyPaid'] =
              ((data['normalInsurancePenaltyPaid'] as num?)?.toInt() ?? 0) +
                  insurancePenaltyApplied;

          updateData['normalSavingsPenaltyPaid'] =
              ((data['normalSavingsPenaltyPaid'] as num?)?.toInt() ?? 0) +
                  savingsPenaltyApplied;

          updateData['normalPenaltyPaid'] =
              ((data['normalPenaltyPaid'] as num?)?.toInt() ?? 0) +
                  totalPenaltyApplied;
        }

        updates.add({
          'ref': monthRefs[i],
          'monthKey': monthKeys[i],
          'data': updateData,
        });
      }

      if (amountLeft > 0) {
        throw StateError(
          'स्वीकृत रकम छानिएका महिनाको बाँकी साँवा र जरिमानाभन्दा बढी छ। '
          'महिना वा रकम जाँच गर्नुहोस्।',
        );
      }

      final processedMonthKeys = updates
          .map((update) => update['monthKey'].toString())
          .toList();
      final fullyPaidMonthKeys = updates
          .where((update) =>
              (update['data'] as Map<String, dynamic>)['status'] == 'paid')
          .map((update) => update['monthKey'].toString())
          .toList();

      final pointAward = DisciplinePointsService.calculate(
        paymentType: paymentType,
        processedMonthKeys: processedMonthKeys,
        fullyPaidMonthKeys: fullyPaidMonthKeys,
        bsDate: payment['bsDate']?.toString() ?? '',
        penaltyDetailsByMonth: penaltyDetailsByMonth,
        previousPartialCount: previousPartialCount,
      );
      if (pointHistorySnapshot.exists) {
        throw StateError('यो भुक्तानीको अनुशासन अंक पहिले नै गणना भएको छ।');
      }
      final oldDisciplinePoints =
          (memberSnapshot.data()?['disciplinePoints'] as num?)?.toInt() ?? 0;
      final newDisciplinePoints = oldDisciplinePoints + pointAward.points;

      // सबै मासिक Ledger अभिलेख पहिले सुरक्षित गर्ने।
    
final monthlyLedgerRefs =
    await _ledgerService.prepareManyInTransaction(
  transaction: transaction,
  events: ledgerEvents,
);

final monthlyAuditRef =
    await _auditService.prepareRecordInTransaction(
  transaction: transaction,
  eventId: 'payment_approved_$paymentId',
);

_ledgerService.writePreparedManyInTransaction(
  transaction: transaction,
  refs: monthlyLedgerRefs,
  events: ledgerEvents,
);

_auditService.writePreparedRecordInTransaction(
  transaction: transaction,
  auditRef: monthlyAuditRef,
  data: {
    'adminUid': adminUid,
    'adminName': adminName,
    'action': 'payment_approved',
    'targetCollection': 'payments',
    'targetDocumentId': paymentId,
    'description': 'Admin ले मासिक बचत तथा जरिमाना भुक्तानी स्वीकृत गर्नुभयो।',
    'memberUid': memberUid,
    'memberName': payment['memberName']?.toString() ?? '',
    'amount': approvedAmount,
    'oldValues': {
      'status': 'pending',
    },
    'newValues': {
      'status': 'approved',
      'approvedAmount': approvedAmount,
      'monthKeys': monthKeys,
    },
    'metadata': {
      'ledgerEventCount': ledgerEvents.length,
      'disciplinePointsDelta': pointAward.points,
      'disciplinePointsReason': pointAward.reason,
    },
  },
);

      // प्रत्येक स्वीकृत आंशिक भुक्तानीको क्रम सुरक्षित राख्ने।
      if (partialMonthRef != null) {
        transaction.set(
          partialMonthRef,
          {
            'memberUid': memberUid,
            'monthKey': monthKeys.single,
            'partialPaymentCount': previousPartialCount + 1,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      // एउटै स्वीकृत भुक्तानीबाट एकपटक मात्र अंक थप्ने वा घटाउने।
      if (pointAward.points != 0) {
        transaction.update(memberRef, {
          'disciplinePoints': newDisciplinePoints,
          'disciplinePointsUpdatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(pointHistoryRef, {
          'memberUid': memberUid,
          'memberName': payment['memberName']?.toString() ?? '',
          'paymentId': paymentId,
          'paymentType': paymentType,
          'monthKeys': monthKeys,
          'bsDate': payment['bsDate']?.toString() ?? '',
          'pointsDelta': pointAward.points,
          'balanceAfter': newDisciplinePoints,
          'reason': pointAward.reason,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // ७. सबै read र हिसाब पूरा भएपछि मासिक रेकर्ड लेख्ने।
      for (final update in updates) {
        transaction.update(
          update['ref'] as DocumentReference<Map<String, dynamic>>,
          update['data'] as Map<String, dynamic>,
        );
      }
      // ८. जरिमानाको Ledger अभिलेख लेख्ने।
      for (final entry in fundEntries) {
        final fundRef = _fundTransactions.doc(
          entry['id'] as String,
        );

        transaction.set(
          fundRef,
          entry['data'] as Map<String, dynamic>,
        );
      }

      // ८. Payment स्वीकृत गर्ने।
      transaction.update(paymentRef, {
        'submittedAmount': originalAmount,
        'approvedAmount': approvedAmount,
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminUid,
        'adminNote': adminNote.trim(),
      });

      // ९. यही भुक्तानीको Pending lock मात्र हटाउने।
      _releaseLockIfOwned(
        transaction: transaction,
        lockSnapshot: lockSnapshot,
        lockRef: lockRef,
        paymentId: paymentId,
      );

      if (insuranceFundDelta > 0) {
        insuranceFundLedger.applyDelta(
          transaction: transaction,
          stateSnapshot: insuranceFundStateSnapshot,
          seedBalance: insuranceFundSeed,
          delta: insuranceFundDelta,
        );
      }
    });

    try {
      await NotificationService.sendToMember(
        memberUid: initialMemberUid,
        title: 'भुक्तानी स्वीकृत भयो',
        message: 'तपाईंको रु. $approvedAmount भुक्तानी स्वीकृत भएको छ।',
        type: 'payment_approved',
        relatedId: paymentId,
      );
    } catch (e) {
      print('Payment approval notification error: $e');
    }
  }
}
