import 'package:cloud_firestore/cloud_firestore.dart';
import 'fund_service.dart';
import 'financial_ledger_service.dart';
import 'admin_audit_service.dart';
import 'member_account_guard.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';

class LoanService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _loans =>
      _db.collection('loans');

  CollectionReference<Map<String, dynamic>> get _members =>
      _db.collection('member');

  CollectionReference<Map<String, dynamic>> get _votes =>
      _db.collection('loan_votes');

  CollectionReference<Map<String, dynamic>> get _memberStatus =>
      _db.collection('loan_member_status');
      CollectionReference<Map<String, dynamic>> get _installments =>
      _db.collection('loan_installments');

  final FundService _fundService = FundService();
    
  final FinancialLedgerService _ledgerService = FinancialLedgerService();
final AdminAuditService _auditService = AdminAuditService();
    
      // --------------------------------------------------
  // Admin भूमिका जाँच
  // --------------------------------------------------
  Future<void> _ensureAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
print('CURRENT LOGIN EMAIL: ${user?.email}');
    if (user == null || user.email == null) {
      throw Exception('पहिले Admin खाताबाट Login गर्नुहोस्।');
    }

    final memberSnapshot =
    await _members.doc(user.uid).get();

    if (!memberSnapshot.exists ||
    (memberSnapshot.data()?['role'] ?? '')
            .toString()
            .toLowerCase() !=
        'admin') {
      throw Exception('यो कार्य Admin ले मात्र गर्न सक्नुहुन्छ।');
    }
  }

      // रकमअनुसार नयाँ ऋणको समयमै तिर्दाको मासिक ब्याजदर।
  static double monthlyRateForAmount(num amount) {
    if (amount <= 20000) return 1.5;
    if (amount <= 50000) return 1.25;
    return 1.0;
  }

  static int maxDurationForAmount(num amount) {
    if (amount <= 20000) return 3;
    if (amount <= 50000) return 6;
    return 12;
  }

  static double overdueRateForAmount(num amount, int overdueDays) {
    if (amount <= 20000) {
      if (overdueDays <= 30) return 2.5;
      if (overdueDays <= 60) return 3.0;
      return 3.5;
    }
    if (amount <= 50000) {
      if (overdueDays <= 30) return 2.0;
      if (overdueDays <= 60) return 2.5;
      return 3.0;
    }
    if (overdueDays <= 30) return 1.5;
    if (overdueDays <= 60) return 2.0;
    return 3.0;
  }

  // --------------------------------------------------
  // ऋणको दैनिक ब्याज गणना (३० दिनको आधारमा)
  // --------------------------------------------------
  Map<String, dynamic> calculateLoanInterest({
    required double principal,
    required DateTime lastInterestDate,
    required DateTime expiryDate,
    required DateTime calculationDate,
    double? baseMonthlyRate,
    num? originalLoanAmount,
    bool useAmountBasedRules = false,
  }) {
  
    final start = DateTime(
      lastInterestDate.year,
      lastInterestDate.month,
      lastInterestDate.day,
    );

    final expiry = DateTime(
      expiryDate.year,
      expiryDate.month,
      expiryDate.day,
    );

    final end = DateTime(
      calculationDate.year,
      calculationDate.month,
      calculationDate.day,
    );

    double totalInterest = 0;
    int overdueDays = 0;
    bool actionRequired = false;

    if (end.isBefore(start)) {
      return {
        'interest': 0.0,
        'overdueDays': 0,
        'actionRequired': false,
      };
    }

    for (
      DateTime day = start.add(const Duration(days: 1));
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      double monthlyRate;

      if (!day.isAfter(expiry)) {
        monthlyRate = baseMonthlyRate ??
            (useAmountBasedRules ? monthlyRateForAmount(originalLoanAmount ?? principal) : 1.0);
      } else {
        overdueDays = day.difference(expiry).inDays;
        monthlyRate = useAmountBasedRules
            ? overdueRateForAmount(originalLoanAmount ?? principal, overdueDays)
            : (overdueDays <= 30 ? 1.5 : overdueDays <= 60 ? 2.0 : 3.0);

        if (overdueDays > 150) {
          actionRequired = true;
        }
      }

      totalInterest +=
          principal * (monthlyRate / 100) / 30;
    }

    if (end.isAfter(expiry)) {
      overdueDays = end.difference(expiry).inDays;
      if (overdueDays > 150) {
        actionRequired = true;
      }
    }

    return {
      'interest': totalInterest,
      'overdueDays': overdueDays,
      'actionRequired': actionRequired,
    };
  }
    
  // --------------------------------------------------
  // ऋण आवेदन पेस गर्ने
  // --------------------------------------------------

  Future<String> submitLoanApplication({
    required String memberUid,
    required String memberName,
    required int requestedAmount,
    required String purpose,
    required String bsDate,
    required String adDate,
    int durationMonths = 1,
    List<String>? guarantors,
  }) async {
    if (memberUid.trim().isEmpty ||
        memberName.trim().isEmpty ||
        purpose.trim().isEmpty) {
      throw Exception('आवश्यक विवरण पूरा भर्नुहोस्।');
    }
    await MemberAccountGuard.ensureActive(memberUid);

    if (requestedAmount <= 0) {
      throw Exception('ऋण रकम शून्यभन्दा बढी हुनुपर्छ।');
    }

    final maxDuration = maxDurationForAmount(requestedAmount);
    if (durationMonths < 1 || durationMonths > maxDuration) {
      throw Exception('यो ऋण रकमका लागि अधिकतम अवधि $maxDuration महिना हो।');
    }

    // ऋण योग्य रकम जाँच
    final eligibleAmount =
        await _fundService.calculateLoanEligibleAmount();

    if (requestedAmount > eligibleAmount) {
      throw Exception(
        'तपाईंले मागेको रकम ऋण योग्य रकमभन्दा बढी छ। '
        'अहिले उपलब्ध ऋण योग्य रकम रु. $eligibleAmount मात्र हो।',
      );
    }

    // छ जना सदस्यको सूची पढ्ने
    final memberSnapshot = await _members.get();

    if (memberSnapshot.docs.length != 6) {
      throw Exception(
        'सदस्य विवरणमा छ जना सदस्य हुनुपर्नेछ। '
        'हाल ${memberSnapshot.docs.length} जना भेटिए।',
      );
    }

    // आवेदनकर्ता बाहेकका पाँच सदस्य स्वतः चयन
    final voterUids = memberSnapshot.docs
        .where((doc) => doc.id != memberUid)
        .map((doc) => doc.id)
        .toList();

    if (voterUids.length != 5) {
      throw Exception('मतदानका लागि पाँच सदस्य भेटिएनन्।');
    }

    final statusRef = _memberStatus.doc(memberUid);
    final loanRef = _loans.doc();

    await _db.runTransaction((transaction) async {
      final statusSnapshot = await transaction.get(statusRef);

      if (statusSnapshot.exists) {
        final statusData = statusSnapshot.data()!;

        final activeApplicationId =
            statusData['activeApplicationId'];

        if (activeApplicationId != null &&
            activeApplicationId.toString().isNotEmpty) {
          throw Exception(
            'तपाईंको अघिल्लो ऋण आवेदन अझै प्रक्रियामा छ।',
          );
        }

        final cooldownValue = statusData['cooldownUntil'];

        if (cooldownValue is Timestamp &&
            cooldownValue.toDate().isAfter(DateTime.now())) {
          final remaining = cooldownValue
              .toDate()
              .difference(DateTime.now())
              .inDays;

          throw Exception(
            'असहमति आएपछि लाग्ने १५ दिने रोक अझै बाँकी छ। '
            'बाँकी दिन: ${remaining + 1}',
          );
        }
      }

      final voters = voterUids.map((uid) {
        final memberDoc = memberSnapshot.docs
            .firstWhere((doc) => doc.id == uid);

        return {
          'uid': uid,
          'name': memberDoc.data()['name'] ?? '',
          'vote': 'pending',
        };
      }).toList();

      transaction.set(loanRef, {
        'loanId': loanRef.id,
        'memberUid': memberUid,
        'memberName': memberName,
        'requestedAmount': requestedAmount,
        'purpose': purpose,
        'bsDate': bsDate,
        'adDate': adDate,
        'durationMonths': durationMonths,
        'monthlyInterestRate': monthlyRateForAmount(requestedAmount),
      'status': 'voting',
'votingRound': 1,
'votingStartedAt': FieldValue.serverTimestamp(),
'votingDeadline': Timestamp.fromDate(
  DateTime.now().add(const Duration(hours: 24)),
),
'round1StartedAt': FieldValue.serverTimestamp(),
'round1Deadline': Timestamp.fromDate(
  DateTime.now().add(const Duration(hours: 24)),
),
'submittedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
        'approvedAmount': 0,
        'approvedDurationMonths': 0,
        'disbursedAmount': 0,
        'outstandingPrincipal': 0,
        'disbursedAt': null,
        'loanStartAt': null,
        'yesVotes': 0,
        'noVotes': 0,
        'votingStatus': 'in_progress',
        'rejectedBy': [],
        'approvedBy': null,
        'votingCompletedAt': null,
        'fourthAgreeAt': null,
        'adminDeadline': null,
        'autoApproved': false,
        'voterUids': voterUids,
        'voters': voters,
      });

      transaction.set(statusRef, {
        'memberUid': memberUid,
        'activeApplicationId': loanRef.id,
        'cooldownUntil': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    return loanRef.id;
  }

  // --------------------------------------------------
  // सदस्यको मतदान
  // --------------------------------------------------
  // --------------------------------------------------
  // सदस्यले ऋणको किस्ता भुक्तानी पेस गर्ने
  // --------------------------------------------------
  
Future<void> submitLoanInstallment({
  required String loanId,
  required String memberUid,
  required int amount,
  required String paymentBsDate,
  required List<int> receiptImageBytes,
}) async {
  final currentUid = FirebaseAuth.instance.currentUser?.uid;

  if (currentUid == null || currentUid != memberUid) {
    throw Exception('आफ्नो खाताबाट मात्र किस्ता पेस गर्न सकिन्छ।');
  }
  await MemberAccountGuard.ensureActive(memberUid);

  if (amount <= 0) {
    throw Exception('किस्ता रकम सही राख्नुहोस्।');
  }

  if (paymentBsDate.trim().isEmpty) {
    throw Exception('भुक्तानी मिति आवश्यक छ।');
  }

  if (receiptImageBytes.isEmpty) {
    throw Exception('रसिद फोटो भेटिएन।');
  }

  // Firestore मा फोटोको आकार ५०० KB भन्दा बढी हुन नदिने
  if (receiptImageBytes.length > 500 * 1024) {
    throw Exception(
      'रसिद फोटोको आकार ५०० KB भन्दा बढी छ। '
      'सानो फोटो छानेर पुनः प्रयास गर्नुहोस्।',
    );
  }

  final loanRef = _loans.doc(loanId);
  final loanSnapshot = await loanRef.get();

  if (!loanSnapshot.exists) {
    throw Exception('ऋण विवरण भेटिएन।');
  }

  final loanData = loanSnapshot.data()!;

  if (loanData['memberUid'] != memberUid ||
      loanData['status'] != 'active') {
    throw Exception('यो सक्रिय ऋण तपाईंको खातामा छैन।');
  }

  // फोटोका Bytes लाई Base64 मा परिवर्तन गर्ने
  final receiptBase64 = base64Encode(receiptImageBytes);

  await _installments.add({
    'loanId': loanId,
    'memberUid': memberUid,
    'memberName': loanData['memberName'] ?? '',
    'amount': amount,
    'paymentBsDate': paymentBsDate,
    'receiptBase64': receiptBase64,
    'receiptSizeBytes': receiptImageBytes.length,
    'status': 'pending',
    'submittedAt': FieldValue.serverTimestamp(),
  });
}

    
Future<void> castVote({
  required String loanId,
  required String voterUid,
  required bool agree,
}) async {
  final currentUid = FirebaseAuth.instance.currentUser?.uid;

  if (currentUid == null || currentUid != voterUid) {
    throw Exception('आफ्नो खाताबाट मात्र मतदान गर्न सकिन्छ।');
  }
  await MemberAccountGuard.ensureActive(voterUid);

  await _db.runTransaction((transaction) async {
    final loanRef = _loans.doc(loanId);
    final loanSnapshot = await transaction.get(loanRef);

    if (!loanSnapshot.exists) {
      throw Exception('ऋण आवेदन भेटिएन।');
    }

    final loan = loanSnapshot.data()!;

    if (loan['status'] != 'voting') {
      throw Exception('यस आवेदनको मतदान खुला छैन।');
    }

    final round = (loan['votingRound'] ?? 1) as int;

    if (round != 1 && round != 2) {
      throw Exception('मतदान चरण सही छैन।');
    }

    final deadline = loan['votingDeadline'];

    if (deadline is! Timestamp ||
        !deadline.toDate().isAfter(DateTime.now())) {
      throw Exception('मतदानको समयसीमा सकिएको छ।');
    }

    final voterUids =
        List<String>.from(loan['voterUids'] ?? []);

    if (!voterUids.contains(currentUid) ||
        currentUid == loan['memberUid']) {
      throw Exception('तपाईं मान्य मतदानकर्ता हुनुहुन्न।');
    }

    final voters = (loan['voters'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final voterIndex =
        voters.indexWhere((voter) => voter['uid'] == currentUid);

    if (voterIndex == -1) {
      throw Exception('मतदानकर्ता सूचीमा तपाईंको नाम भेटिएन।');
    }

    if (voters[voterIndex]['vote'] != 'pending') {
      throw Exception('तपाईंले यस चरणमा पहिले नै मतदान गरिसक्नुभयो।');
    }

    final voteRef = _votes.doc(
      '${loanId}_round${round}_$currentUid',
    );

    final voteSnapshot = await transaction.get(voteRef);

    if (voteSnapshot.exists) {
      throw Exception('तपाईंले यस चरणमा पहिले नै मतदान गरिसक्नुभयो।');
    }

    final voteValue = agree ? 'agree' : 'disagree';

    voters[voterIndex]['vote'] = voteValue;

    final yesVotes =
        voters.where((voter) => voter['vote'] == 'agree').length;

    final noVotes =
        voters.where((voter) => voter['vote'] == 'disagree').length;

    transaction.set(voteRef, {
      'loanId': loanId,
      'voterUid': currentUid,
      'round': round,
      'vote': voteValue,
      'source': 'member',
      'createdAt': FieldValue.serverTimestamp(),
    });

    transaction.update(loanRef, {
      'voters': voters,
      'yesVotes': yesVotes,
      'noVotes': noVotes,
    });
  });
}
    
    // --------------------------------------------------
// Admin ले स्वीकृतिका लागि पर्खिरहेका किस्ता हेर्ने
// --------------------------------------------------
Stream<QuerySnapshot<Map<String, dynamic>>>
    watchPendingInstallments() {
  return _installments
      .where('status', isEqualTo: 'pending')
      .snapshots();
}

   // --------------------------------------------------
  // किस्ता भुक्तानी अस्वीकृत गर्ने
  // --------------------------------------------------
  Future<void> rejectLoanInstallment({
    required String installmentId,
  }) async {
    await _ensureAdmin();

    final adminUid = FirebaseAuth.instance.currentUser!.uid;
    final installmentRef = _installments.doc(installmentId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(installmentRef);

      if (!snapshot.exists) {
        throw Exception('किस्ता भुक्तानी विवरण भेटिएन।');
      }

      if (snapshot.data()?['status'] != 'pending') {
        throw Exception('यो किस्ता पहिले नै समीक्षा भइसकेको छ।');
      }

      transaction.update(installmentRef, {
        'status': 'rejected',
        'reviewedBy': adminUid,
        'reviewedAt': FieldValue.serverTimestamp(),
        'rejectedAt': FieldValue.serverTimestamp(),
      });
    });
  }
    
  // --------------------------------------------------
  // Admin ले ऋण किस्ता स्वीकृत गर्ने
  // --------------------------------------------------
  Future<void> approveLoanInstallment({
  required String installmentId,
  double? adjustedAmount,
}) async {
    await _ensureAdmin();

    final adminUid = FirebaseAuth.instance.currentUser!.uid;
    final installmentRef = _installments.doc(installmentId);

    await _db.runTransaction((transaction) async {
      // किस्ता विवरण पढ्ने
      final installmentSnapshot =
          await transaction.get(installmentRef);

      if (!installmentSnapshot.exists) {
        throw Exception('किस्ता भुक्तानी विवरण भेटिएन।');
      }

      final installmentData = installmentSnapshot.data()!;

      if (installmentData['status'] != 'pending') {
        throw Exception('यो किस्ता पहिले नै समीक्षा भइसकेको छ।');
      }

      final loanId = installmentData['loanId']?.toString() ?? '';
 final amount = (adjustedAmount ??
    (installmentData['amount'] as num)).toDouble();

if (amount <= 0) {
  throw Exception('स्वीकृत रकम शून्यभन्दा बढी हुनुपर्छ।');
}
      final paymentBsDate =
          installmentData['paymentBsDate']?.toString() ?? '';

      if (loanId.isEmpty || amount <= 0) {
        throw Exception('किस्ता विवरण सही छैन।');
      }

      // ऋण विवरण पढ्ने
      final loanRef = _loans.doc(loanId);
      final loanSnapshot = await transaction.get(loanRef);
        
      final adminSnapshot = await transaction.get(
  _db.collection('member').doc(adminUid),
);

final adminName =
    adminSnapshot.data()?['name']?.toString() ?? adminUid;

      if (!loanSnapshot.exists) {
        throw Exception('सम्बन्धित ऋण विवरण भेटिएन।');
      }

      final loanData = loanSnapshot.data()!;

      if (loanData['status'] != 'active') {
        throw Exception('यो ऋण अहिले सक्रिय अवस्थामा छैन।');
      }

      // भुक्तानीको वि.सं. मिति AD मा परिवर्तन गर्ने
      final dateParts = paymentBsDate.split('/');

      if (dateParts.length != 3) {
        throw Exception('भुक्तानी मिति सही ढाँचामा छैन।');
      }

      final paymentBs = NepaliDateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
      );

      final paymentDate = paymentBs.toDateTime();

      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final paymentOnly = DateTime(
        paymentDate.year,
        paymentDate.month,
        paymentDate.day,
      );

      if (paymentOnly.isAfter(todayOnly)) {
        throw Exception('भविष्यको मितिको भुक्तानी स्वीकृत गर्न मिल्दैन।');
      }

      // बाँकी साँवा
      final principal = (
        loanData['outstandingPrincipal'] ??
        loanData['disbursedAmount'] ??
        loanData['approvedAmount'] ??
        0
      ) as num;

      final outstandingPrincipal = principal.toDouble();

      if (outstandingPrincipal <= 0) {
        throw Exception('यस ऋणको बाँकी साँवा छैन।');
      }

      // ऋण सुरु भएको मिति
      final startValue =
          loanData['disbursedAt'] ?? loanData['loanStartAt'];

      if (startValue is! Timestamp) {
        throw Exception('ऋण सुरु भएको मिति भेटिएन।');
      }

      final startBs =
          NepaliDateTime.fromDateTime(startValue.toDate());

      // ऋण समाप्त हुने वि.सं. मिति
      final duration = (
        loanData['approvedDurationMonths'] ??
        loanData['durationMonths'] ??
        1
      ) as num;

      final durationMonths = duration.toInt();

      final monthIndex = startBs.month - 1 + durationMonths;
      final targetYear = startBs.year + monthIndex ~/ 12;
      final targetMonth = monthIndex % 12 + 1;

      final lastDay =
          NepaliDateTime(targetYear, targetMonth).totalDays;

      final targetDay =
          startBs.day > lastDay ? lastDay : startBs.day;

      final expiryBs = NepaliDateTime(
        targetYear,
        targetMonth,
        targetDay,
      ).subtract(const Duration(days: 1));

      final expiryDate = expiryBs.toDateTime();

      // अघिल्लो ब्याज गणना भएको मिति
      final lastInterestValue = loanData['lastInterestDate'];
      final lastInterestDate = lastInterestValue is Timestamp
          ? lastInterestValue.toDate()
          : startValue.toDate();

      if (paymentOnly.isBefore(DateTime(
        lastInterestDate.year,
        lastInterestDate.month,
        lastInterestDate.day,
      ))) {
        throw Exception('भुक्तानी मिति अघिल्लो ब्याज मितिभन्दा पुरानो छ।');
      }

      // भुक्तानी मितिसम्मको नयाँ ब्याज
      final interestResult = calculateLoanInterest(
        principal: outstandingPrincipal,
        lastInterestDate: lastInterestDate,
        expiryDate: expiryDate,
        calculationDate: paymentDate,
        baseMonthlyRate: (loanData['monthlyInterestRate'] as num?)?.toDouble(),
        originalLoanAmount: (loanData['approvedAmount'] ?? loanData['requestedAmount'] ?? outstandingPrincipal) as num,
        useAmountBasedRules: loanData['monthlyInterestRate'] != null,
      );

      final newInterest =
    (interestResult['interest'] as num).toDouble();

      // पहिलेको बाँकी ब्याज + नयाँ ब्याज
      final previousUnpaidInterest =
    ((loanData['unpaidInterest'] ?? 0) as num).toDouble();

      final totalInterestDue =
          previousUnpaidInterest + newInterest;

      // कुल साँवा र ब्याजभन्दा बढी रकम स्वीकृत गर्न नदिने
      final totalDue =
    outstandingPrincipal.toDouble() + totalInterestDue;

      if (amount > totalDue) {
        throw Exception(
          'पेस गरिएको रकम कुल बाँकी रकमभन्दा बढी छ। '
          'कुल साँवा तथा ब्याज रु. $totalDue मात्र छ।',
        );
      }

      // पहिले ब्याज कट्टा गर्ने
      final interestPaid =
          amount >= totalInterestDue ? totalInterestDue : amount;

      final remainingInterest =
          totalInterestDue - interestPaid;

      // ब्याज तिरेपछि बाँकी रकमबाट साँवा घटाउने
      final principalPaid = amount - interestPaid;

      final newPrincipal =
          outstandingPrincipal - principalPaid;
        
        final ledgerEvent = {
  'eventId': 'loan_installment_approved_$installmentId',
  'memberUid': installmentData['memberUid'],
  'memberName': installmentData['memberName'] ?? '',
  'transactionType': 'loan_repayment',
  'amount': amount,
  'bsDate': paymentBsDate,
  'description': 'ऋण किस्ता स्वीकृत',
  'sourceCollection': 'loan_installments',
  'sourceDocumentId': installmentId,
  'recordedByUid': adminUid,
  'recordedByName': adminName,
  'status': 'approved',
  'metadata': {
    'loanId': loanId,
    'interestPaid': interestPaid,
    'principalPaid': principalPaid,
    'unpaidInterestAfterPayment': remainingInterest,
  },
};

final ledgerRefs =
    await _ledgerService.prepareManyInTransaction(
  transaction: transaction,
  events: [ledgerEvent],
);

final auditRef =
    await _auditService.prepareRecordInTransaction(
  transaction: transaction,
  eventId: 'loan_installment_approved_$installmentId',
);

_ledgerService.writePreparedManyInTransaction(
  transaction: transaction,
  refs: ledgerRefs,
  events: [ledgerEvent],
);

_auditService.writePreparedRecordInTransaction(
  transaction: transaction,
  auditRef: auditRef,
  data: {
    'adminUid': adminUid,
    'adminName': adminName,
    'action': 'loan_installment_approved',
    'targetCollection': 'loan_installments',
    'targetDocumentId': installmentId,
    'description': 'ऋण किस्ता स्वीकृत',
    'memberUid': installmentData['memberUid'],
    'memberName': installmentData['memberName'] ?? '',
    'amount': amount,
    'oldValues': {
      'status': 'pending',
    },
    'newValues': {
      'status': 'approved',
      'approvedAmount': amount,
      'interestPaid': interestPaid,
      'principalPaid': principalPaid,
      'loanId': loanId,
    },
  },
);

      // किस्ता विवरण अद्यावधिक
      transaction.update(installmentRef, {
        'status': 'approved',
        'approvedAmount': amount,
        'interestPaid': interestPaid,
        'principalPaid': principalPaid,
        'unpaidInterestAfterPayment': remainingInterest,
        'reviewedBy': adminUid,
        'reviewedAt': FieldValue.serverTimestamp(),
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // ऋण विवरण अद्यावधिक
      transaction.update(loanRef, {
        'outstandingPrincipal': newPrincipal,
        'unpaidInterest': remainingInterest,
        'lastInterestDate': Timestamp.fromDate(paymentDate),
        'lastInstallmentAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

Future<void> startSecondVoting({
  required String loanId,
  required String adminUid,
  required int revisedAmount,
  required int revisedDurationMonths,
}) async {
      await _ensureAdmin();

  final currentUid = FirebaseAuth.instance.currentUser?.uid;

  if (currentUid == null || currentUid != adminUid) {
    throw Exception('Admin खाताबाट मात्र दोस्रो मतदान सुरु गर्न सकिन्छ।');
  }
  if (revisedAmount <= 0) {
    throw Exception('ऋण रकम शून्यभन्दा बढी हुनुपर्छ।');
  }

  final maxDuration = maxDurationForAmount(revisedAmount);
  if (revisedDurationMonths < 1 || revisedDurationMonths > maxDuration) {
    throw Exception('यो ऋण रकमका लागि अधिकतम अवधि $maxDuration महिना हो।');
  }

  final loanRef = _loans.doc(loanId);

  await _db.runTransaction((transaction) async {
    final loanSnapshot = await transaction.get(loanRef);

    if (!loanSnapshot.exists) {
      throw Exception('ऋण आवेदन भेटिएन।');
    }

    final loanData = loanSnapshot.data()!;

    if (loanData['status'] != 'admin_review') {
      throw Exception(
        'यो आवेदन दोस्रो मतदानका लागि तयार छैन।',
      );
    }

    if ((loanData['votingRound'] ?? 1) != 1) {
      throw Exception('दोस्रो मतदान पहिले नै सुरु भएको छ।');
    }

    final voterUids =
        List<String>.from(loanData['voterUids'] ?? []);

    if (voterUids.length != 5) {
      throw Exception('पाँच जना मतदानकर्ता आवश्यक छन्।');
    }

    final oldVoters = List<Map<String, dynamic>>.from(
      (loanData['voters'] ?? []).map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );

    final newVoters = oldVoters.map((voter) {
      return {
        'uid': voter['uid'],
        'name': voter['name'] ?? '',
        'vote': 'pending',
      };
    }).toList();

    final updateData = <String, dynamic>{
  'requestedAmount': revisedAmount,
  'durationMonths': revisedDurationMonths,
  'monthlyInterestRate': monthlyRateForAmount(revisedAmount),
  'voters': newVoters,
  'yesVotes': 0,
  'noVotes': 0,
  'votingRound': 2,
  'status': 'voting',
  'votingStatus': 'round2_in_progress',
  'round2StartedAt': FieldValue.serverTimestamp(),
  'round2Deadline': Timestamp.fromDate(
    DateTime.now().add(const Duration(hours: 24)),
  ),
  'votingDeadline': Timestamp.fromDate(
    DateTime.now().add(const Duration(hours: 24)),
  ),
  'adminModifiedBy': adminUid,
  'adminModifiedAt': FieldValue.serverTimestamp(),
  'round1Completed': true,
};

if (loanData['round1RequestedAmount'] == null) {
  updateData['round1RequestedAmount'] =
      loanData['requestedAmount'];
  updateData['round1DurationMonths'] =
      loanData['durationMonths'];
}

transaction.update(loanRef, updateData);
        });
}

Future<void> castAdminProxyVote({
  required String loanId,
  required String adminUid,
  required String voterUid,
  required bool agree,
}) async {
  await _ensureAdmin();

  final currentUid = FirebaseAuth.instance.currentUser?.uid;

  if (currentUid == null || currentUid != adminUid) {
    throw Exception('Admin खाताबाट मात्र Proxy Vote गर्न सकिन्छ।');
  }

  await _db.runTransaction((transaction) async {
    final loanRef = _loans.doc(loanId);
    final loanSnapshot = await transaction.get(loanRef);

    if (!loanSnapshot.exists) {
      throw Exception('ऋण आवेदन भेटिएन।');
    }

    final loan = loanSnapshot.data()!;

    if (loan['status'] != 'voting') {
      throw Exception('यस आवेदनको मतदान खुला छैन।');
    }

    final round = (loan['votingRound'] ?? 1) as int;

    if (round != 1 && round != 2) {
      throw Exception('मतदान चरण सही छैन।');
    }

    final deadline = loan['votingDeadline'];

    if (deadline is! Timestamp ||
        deadline.toDate().isAfter(DateTime.now())) {
      throw Exception('२४ घण्टे मतदान समयसीमा सकिएको छैन।');
    }

    final voterUids = List<String>.from(loan['voterUids'] ?? []);

    if (!voterUids.contains(voterUid) ||
    voterUid == loan['memberUid']) {
  throw Exception('यो सदस्य मान्य मतदानकर्ता होइन।');
}

    final voteRef = _votes.doc(
      '${loanId}_round${round}_$voterUid',
    );

    final voteSnapshot = await transaction.get(voteRef);

    if (voteSnapshot.exists) {
      throw Exception('यस सदस्यले पहिले नै मतदान गरिसकेको छ।');
    }

    transaction.set(voteRef, {
      'loanId': loanId,
      'voterUid': voterUid,
      'round': round,
      'vote': agree ? 'agree' : 'disagree',
      'source': 'admin',
      'adminUid': currentUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  });
}
    
    // --------------------------------------------------
// Admin ले मतदानको नतिजा गणना गर्ने
// --------------------------------------------------



Future<void> processLoanVotes({
  required String loanId,
  required String adminUid,
}) async {
  await _ensureAdmin();

  final currentUid = FirebaseAuth.instance.currentUser?.uid;

  if (currentUid == null || currentUid != adminUid) {
    throw Exception('Admin ले मात्र मतगणना गर्न सक्छ।');
  }

    final loanRef = _loans.doc(loanId);

  await _db.runTransaction((transaction) async {
    final loanSnapshot = await transaction.get(loanRef);
      
    if (!loanSnapshot.exists) {
      throw Exception('ऋण आवेदन भेटिएन।');
    }

    final loan = loanSnapshot.data()!;

    if (loan['status'] != 'voting') {
      throw Exception('यो आवेदन अहिले मतदानमा छैन।');
    }

    final round = (loan['votingRound'] ?? 1) as int;

    if (round != 1 && round != 2) {
      throw Exception('मतदान चरण मिलेन।');
    }

    final deadline = loan['votingDeadline'];

    final voterUids =
        List<String>.from(loan['voterUids'] ?? []);

    if (voterUids.length != 5 ||
        voterUids.toSet().length != 5) {
      throw Exception('पाँच जना फरक मतदानकर्ता आवश्यक छन्।');
    }

    final voteRefs = voterUids.map((uid) {
      return _votes.doc('${loanId}_round${round}_$uid');
    }).toList();

    final voteSnapshots =
        <DocumentSnapshot<Map<String, dynamic>>>[];

    for (final ref in voteRefs) {
      voteSnapshots.add(await transaction.get(ref));
    }

    final oldVoters = (loan['voters'] as List? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final voters = <Map<String, dynamic>>[];

    var yesVotes = 0;
    var noVotes = 0;

    for (var i = 0; i < voterUids.length; i++) {
      final uid = voterUids[i];

      final matching = oldVoters
          .where((item) => item['uid'] == uid)
          .toList();

      if (matching.length != 1) {
        throw Exception('मतदानकर्ताको विवरण मिलेन: $uid');
      }

      final voter = Map<String, dynamic>.from(matching.first);
      final voteSnapshot = voteSnapshots[i];

      if (!voteSnapshot.exists) {
        voter['vote'] = 'pending';
        voters.add(voter);
        continue;
      }

      final vote = voteSnapshot.data()!;

      if (vote['loanId'] != loanId ||
          vote['voterUid'] != uid ||
          vote['round'] != round ||
          !['agree', 'disagree'].contains(vote['vote'])) {
        throw Exception('मतदान रेकर्डमा त्रुटि भेटियो।');
      }

      if (vote['source'] == 'member') {
        if (vote['adminUid'] != null) {
          throw Exception('सदस्यको मत विवरण मिलेन।');
        }

        final createdAt = vote['createdAt'];

        if (createdAt is! Timestamp ||
            createdAt.toDate().isAfter(deadline.toDate())) {
          throw Exception('सदस्यको मत समयसीमापछि आएको छ।');
        }
      } else if (vote['source'] == 'admin') {
        final proxyCreatedAt = vote['createdAt'];

        if (vote['adminUid'] != currentUid ||
            proxyCreatedAt is! Timestamp ||
            proxyCreatedAt.toDate().isBefore(deadline.toDate())) {
          throw Exception('Admin Proxy Vote विवरण वा समय मिलेन।');
        }

        voter['votedByAdmin'] = true;
        voter['adminUid'] = currentUid;
        voter['adminVotedAt'] = proxyCreatedAt;
      } else {
        throw Exception('Vote को स्रोत पहिचान भएन।');
      }

      voter['vote'] = vote['vote'];

      if (vote['vote'] == 'agree') {
        yesVotes++;
      } else {
        noVotes++;
      }

      voters.add(voter);
    }

    if (voters.any((voter) => voter['vote'] == 'pending')) {
      throw Exception(
        'पाँचै जनाको मत पूरा भएको छैन। पहिले बाँकी Proxy Vote पूरा गर्नुहोस्।',
      );
    }

    final update = <String, dynamic>{
      'voters': voters,
      'yesVotes': yesVotes,
      'noVotes': noVotes,
    };

    final applicantUid = loan['memberUid'].toString();
    final statusRef = _memberStatus.doc(applicantUid);

    if (yesVotes >= 4) {
      update.addAll({
        'status': 'admin_pending',
        'votingStatus': 'completed',
        'fourthAgreeAt': FieldValue.serverTimestamp(),
        'adminDeadline': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 3)),
        ),
        'votingCompletedAt': FieldValue.serverTimestamp(),
        'completedRound': round,
      });
    } else if (noVotes >= 2 && round == 1) {
      update.addAll({
        'status': 'admin_review',
        'votingStatus': 'admin_review',
        'round1YesVotes': yesVotes,
        'round1NoVotes': noVotes,
        'round1Voters': voters,
        'votingCompletedAt': FieldValue.serverTimestamp(),
      });
    } else if (noVotes >= 2 && round == 2) {
      final submittedAt = loan['submittedAt'];

      if (submittedAt is! Timestamp) {
        throw Exception('मूल आवेदन मिति भेटिएन।');
      }

      update.addAll({
        'status': 'rejected',
        'votingStatus': 'rejected',
        'round2YesVotes': yesVotes,
        'round2NoVotes': noVotes,
        'round2Voters': voters,
        'rejectedBy': voters
            .where((v) => v['vote'] == 'disagree')
            .map((v) => v['uid'])
            .toList(),
        'votingCompletedAt': FieldValue.serverTimestamp(),
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(statusRef, {
        'memberUid': applicantUid,
        'activeApplicationId': null,
        'cooldownUntil': Timestamp.fromDate(
          submittedAt.toDate().add(const Duration(days: 15)),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    transaction.update(loanRef, update);
  });
}

  // पुरानो main.dart को compatibility का लागि
  Future<void> respondToGuarantor({
    required String loanId,
    required String guarantorUid,
    required bool accepted,
  }) async {
    await castVote(
      loanId: loanId,
      voterUid: guarantorUid,
      agree: accepted,
    );
  }

  // --------------------------------------------------
  // Admin बाट ऋण स्वीकृति तथा रकम वितरण
  // --------------------------------------------------

  Future<void> approveLoan({
    required String loanId,
    required String approvedBy,
    int? approvedAmount,
    int? approvedDurationMonths,
  }) async {
    final loanRef = _loans.doc(loanId);

    final loanSnapshot = await loanRef.get();

    if (!loanSnapshot.exists) {
      throw Exception('ऋण आवेदन भेटिएन।');
    }

    final loanData = loanSnapshot.data()!;

    if (loanData['status'] != 'admin_pending') {
      throw Exception('यो आवेदन Admin स्वीकृतिका लागि तयार छैन।');
    }

    final deadline = loanData['adminDeadline'];
    final deadlinePassed = deadline is Timestamp &&
        DateTime.now().isAfter(deadline.toDate());

    // तीन दिन कटेपछि मूल मागअनुसार स्वीकृति
    final amount = deadlinePassed
        ? (loanData['requestedAmount'] as num).toInt()
        : (approvedAmount ??
            (loanData['requestedAmount'] as num).toInt());

    final duration = deadlinePassed
        ? (loanData['durationMonths'] as num).toInt()
        : (approvedDurationMonths ??
            (loanData['durationMonths'] as num).toInt());

    if (amount <= 0) {
      throw Exception('स्वीकृत रकम सही राख्नुहोस्।');
    }

    final maxDuration = maxDurationForAmount(amount);
    if (duration < 1 || duration > maxDuration) {
      throw Exception('स्वीकृत रकमका लागि अधिकतम अवधि $maxDuration महिना हो।');
    }

    final eligibleAmount =
    await _fundService.calculateLoanEligibleAmount(
  excludeLoanId: loanId,
);

    if (amount > eligibleAmount) {
      throw Exception(
        'हालको ऋण योग्य रकम रु. $eligibleAmount मात्र छ। '
        'त्यसभन्दा बढी रकम स्वीकृत गर्न मिल्दैन।',
      );
    }

    final applicantUid = loanData['memberUid'].toString();
    final statusRef = _memberStatus.doc(applicantUid);

    await _db.runTransaction((transaction) async {
      final currentLoan = await transaction.get(loanRef);
      final statusSnapshot = await transaction.get(statusRef);

      if (!currentLoan.exists ||
          currentLoan.data()?['status'] != 'admin_pending') {
        throw Exception('यो आवेदन पहिले नै परिवर्तन भइसकेको छ।');
      }

      transaction.update(loanRef, {
        'status': 'active',
        'approvedAmount': amount,
        'approvedDurationMonths': duration,
        'monthlyInterestRate': monthlyRateForAmount(amount),
        'disbursedAmount': amount,
        'outstandingPrincipal': amount,
        'disbursedAt': FieldValue.serverTimestamp(),
        'loanStartAt': FieldValue.serverTimestamp(),
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': approvedBy,
        'approvedBy': approvedBy,
        'autoApproved': deadlinePassed,
      });

      transaction.set(statusRef, {
        'memberUid': applicantUid,
        'activeApplicationId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  // --------------------------------------------------
  // तीन दिन नाघेका आवेदन स्वतः स्वीकृत गर्ने
  // --------------------------------------------------

  Future<void> processExpiredAdminApprovals() async {
    final now = Timestamp.now();

    final snapshot = await _loans
        .where('status', isEqualTo: 'admin_pending')
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final deadline = data['adminDeadline'];

      if (deadline is Timestamp &&
          deadline.compareTo(now) <= 0) {
        try {
          await approveLoan(
            loanId: doc.id,
            approvedBy: 'system_auto_approval',
          );
        } catch (_) {
          // अर्को आवेदन वा रकम परिवर्तनका कारण स्वीकृति हुन नसके
          // बाँकी आवेदनको प्रक्रिया जारी राख्ने।
        }
      }
    }
  }

  // --------------------------------------------------
  // ऋण विवरण हेर्ने Streams
  // --------------------------------------------------

    Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingLoans() {
    return _loans
        .where(
          'status',
          whereIn: ['voting', 'admin_pending', 'admin_review'],
        )
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchVotingLoans(
    String memberUid,
  ) {
    return _loans
        .where('voterUids', arrayContains: memberUid)
        .where('status', isEqualTo: 'voting')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllLoans() {
    return _loans.snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchActiveLoans() {
    return _loans
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchGuarantorResponses(
    String loanId,
  ) {
    return _votes
        .where('loanId', isEqualTo: loanId)
        .snapshots();
  }
}