
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';

class PenaltyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _adminUid =
      'j5HwNs8IKvbi45m0JKkjuConQvC2';

  CollectionReference<Map<String, dynamic>> get _savings =>
      _db.collection('monthly_savings');

  CollectionReference<Map<String, dynamic>> get _notices =>
      _db.collection('late_payment_notices');

  CollectionReference<Map<String, dynamic>> get _waivers =>
      _db.collection('penalty_waivers');

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

  String _monthKey(int number) {
    final year = (number - 1) ~/ 12;
    final month = ((number - 1) % 12) + 1;

    return '$year-${month.toString().padLeft(2, '0')}';
  }

  int _intValue(dynamic value, [int fallback = 0]) {
    return value is num ? value.round() : fallback;
  }

  int _roundPercent(int amount, int rate) {
    return (amount * rate / 100).round();
  }

  Future<Map<String, dynamic>> calculateMemberPenalty({
    required String memberUid,
  }) async {
    if (memberUid.trim().isEmpty) {
      throw ArgumentError('सदस्य UID आवश्यक छ।');
    }

    final memberRef = _db.collection('member').doc(memberUid);
    final memberSnapshot = await memberRef.get();
    final memberData = memberSnapshot.data() ?? <String, dynamic>{};
    final now = DateTime.now();
    final scheduledEndValue = memberData['deactivationEndsAt'];
    if (memberData['accountActive'] == false &&
        memberData['deactivationMode'] == 'fixed' &&
        scheduledEndValue is Timestamp &&
        !scheduledEndValue.toDate().isAfter(now)) {
      final endedAt = scheduledEndValue.toDate();
      await memberRef.set({
        'accountActive': true,
        'deactivationStartsAt': null,
        'deactivationEndsAt': null,
        'reactivatedAt': Timestamp.fromDate(endedAt),
        'penaltyResumeAt': Timestamp.fromDate(endedAt.add(const Duration(days: 10))),
        'penaltyResumeMode': 'fixed_period',
        'deactivationAutoReactivatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      memberData['accountActive'] = true;
      memberData['deactivationStartsAt'] = null;
      memberData['deactivationEndsAt'] = null;
      memberData['reactivatedAt'] = Timestamp.fromDate(endedAt);
      memberData['penaltyResumeAt'] = Timestamp.fromDate(endedAt.add(const Duration(days: 10)));
      memberData['penaltyResumeMode'] = 'fixed_period';
    }
    final deactivatedAtValue = memberData['deactivatedAt'];
    final startsValue = memberData['deactivationStartsAt'];
    final scheduledStart = startsValue is Timestamp ? startsValue.toDate() : null;
    final endsValue = memberData['deactivationEndsAt'];
    final scheduledEnd = endsValue is Timestamp ? endsValue.toDate() : null;
    final deactivatedAt = deactivatedAtValue is Timestamp
        ? deactivatedAtValue.toDate()
        : scheduledStart;
    final resumeValue = memberData['penaltyResumeAt'];
    final resumeAt = resumeValue is Timestamp ? resumeValue.toDate() : null;
    final scheduledInactive = memberData['deactivationMode'] == 'fixed' &&
        scheduledStart != null && !scheduledStart.isAfter(now) &&
        (scheduledEnd == null || scheduledEnd.isAfter(now));
    final isInactive = memberData['accountActive'] == false || scheduledInactive;
    final isInReactivationGrace = !isInactive && resumeAt != null && now.isBefore(resumeAt);

    // निष्क्रिय अवधि र पुनः सक्रिय भएको १० दिने छुटमा जरिमाना गणना
    // निष्क्रिय बनाइएको मितिसम्म मात्र रोक्ने; पहिलेको बाँकी जरिमाना कायम रहन्छ।
    final referenceDate = (isInactive || isInReactivationGrace) && deactivatedAt != null
        ? deactivatedAt
        : now;
    final bsNow = NepaliDateTime.fromDateTime(referenceDate);

    final currentMonthKey =
        '${bsNow.year}-${bsNow.month.toString().padLeft(2, '0')}';

    final currentMonthNumber = _monthNumber(currentMonthKey);

    final savingsSnapshot = await _savings
        .where('memberUid', isEqualTo: memberUid)
        .get();

    final noticeSnapshot = await _notices
        .where('memberUid', isEqualTo: memberUid)
        .get();

    final waiverSnapshot = await _waivers
        .where('memberUid', isEqualTo: memberUid)
        .get();

    final approvedNoticeMonths = <String>{};

    for (final doc in noticeSnapshot.docs) {
      final data = doc.data();
      final status = data['status']?.toString();

      if (status == 'approved' || status == 'auto_approved') {
        final key = data['monthKey']?.toString();

        if (key != null) {
          approvedNoticeMonths.add(key);
        }
      }
    }

    final waivedByMonth = <String, int>{};

    for (final doc in waiverSnapshot.docs) {
      final data = doc.data();
      final key = data['monthKey']?.toString();
      final amount = _intValue(data['waivedAmount']);

      if (key != null && amount > 0) {
        waivedByMonth[key] =
            (waivedByMonth[key] ?? 0) + amount;
      }
    }

    final records = savingsSnapshot.docs
        .map((doc) => doc.data())
        .where((data) => data['monthKey'] != null)
        .toList();

    records.sort(
      (a, b) => _monthNumber(
        a['monthKey'].toString(),
      ).compareTo(
        _monthNumber(b['monthKey'].toString()),
      ),
    );

    final recordByMonth =
        <String, Map<String, dynamic>>{};

    final remainingByMonth = <String, int>{};
    final overdueMonths = <String, int>{};

    int totalRemaining = 0;

    for (final data in records) {
      final key = data['monthKey'].toString();
      final number = _monthNumber(key);

      if (number > currentMonthNumber) continue;

      final totalDue = _intValue(data['totalDue'], 2300);
      final paidAmount = _intValue(data['paidAmount']);

      final remaining =
          (totalDue - paidAmount).clamp(0, totalDue).toInt();

      recordByMonth[key] = data;
      remainingByMonth[key] = remaining;

      if (remaining == 0) continue;

      totalRemaining += remaining;

      final penaltyStartDay =
          approvedNoticeMonths.contains(key) ? 16 : 11;

      final isOverdue = number < currentMonthNumber ||
          (number == currentMonthNumber &&
              bsNow.day >= penaltyStartDay);

      if (isOverdue) {
        overdueMonths[key] = remaining;
      }
    }

    // अनिश्चितकालीन निष्क्रियतापछि पुनः सक्रिय हुँदा अघिल्ला नयाँ
    // महिनाहरूको जरिमाना नथप्ने; निष्क्रिय हुनुअघि नै बाँकी भएको जरिमाना कायम।
    if (!isInactive && !isInReactivationGrace &&
        resumeAt != null && !now.isBefore(resumeAt) &&
        deactivatedAt != null) {
      final deactivatedBs = NepaliDateTime.fromDateTime(deactivatedAt);
      final deactivatedMonthNumber = _monthNumber(
        '${deactivatedBs.year}-${deactivatedBs.month.toString().padLeft(2, '0')}',
      );
      final resumeBs = NepaliDateTime.fromDateTime(resumeAt);
      final resumeMonthNumber = _monthNumber(
        '${resumeBs.year}-${resumeBs.month.toString().padLeft(2, '0')}',
      );
      final manualMode = memberData['penaltyResumeMode'] == 'current_month_only';
      overdueMonths.removeWhere((key, remaining) {
        final number = _monthNumber(key);
        // निष्क्रिय हुनुअघि नै जरिमाना लागिसकेका महिना पुरानै बक्यौता हुन्।
        if (number < deactivatedMonthNumber) return false;
        if (number == deactivatedMonthNumber) {
          // निष्क्रिय भएको र पुनः सक्रिय भएको दुवै यही महिनामा परेमा,
          // १० दिने छुटपछि चालु महिनाको जरिमाना लाग्न दिनुहोस्।
          if (number == currentMonthNumber && resumeMonthNumber != null && number >= resumeMonthNumber) {
            return false;
          }
          final noticeDay = approvedNoticeMonths.contains(key) ? 16 : 11;
          return deactivatedBs.day < noticeDay;
        }
        // अनिश्चितकालीन विकल्पमा पुनः सक्रिय भएपछि चालु महिनाको मात्र नयाँ जरिमाना।
        if (manualMode) return number != currentMonthNumber;
        // निश्चित अवधिमा निष्क्रिय समयका महिनाहरूमा जरिमाना नथप्ने;
        // १० दिने छुटपछि सुरु भएका महिना र त्यसपछिका महिना मात्र गणना गर्ने।
        return number < resumeMonthNumber;
      });
    }

    // लगातार दुई महिना बाँकी छन् कि छैनन् जाँच।
    // चालु महिना पनि आफ्नो जरिमाना सुरु हुने दिन पुगेको हुनुपर्छ।
    final overdueNumbers = overdueMonths.keys
        .map(_monthNumber)
        .toSet();

    final consecutivePairs = <int>[];
    final deactivatedMonthForPairs = deactivatedAt == null
        ? null
        : _monthNumber('${NepaliDateTime.fromDateTime(deactivatedAt).year}-${NepaliDateTime.fromDateTime(deactivatedAt).month.toString().padLeft(2, '0')}');
    final resumeMonthForPairs = resumeAt == null
        ? null
        : _monthNumber('${NepaliDateTime.fromDateTime(resumeAt).year}-${NepaliDateTime.fromDateTime(resumeAt).month.toString().padLeft(2, '0')}');

    for (final number in overdueNumbers) {
      if (!overdueNumbers.contains(number + 1)) continue;
      if (deactivatedMonthForPairs != null && resumeMonthForPairs != null) {
        final pairWasBeforeDeactivation = number + 1 <= deactivatedMonthForPairs;
        final pairIsAfterPenaltyResume = number >= resumeMonthForPairs;
        if (!pairWasBeforeDeactivation && !pairIsAfterPenaltyResume) continue;
      }
      consecutivePairs.add(number);
    }

    // विशेष जरिमानाको आधार बीमा र बचतमा छुट्याउने।
final specialPenaltyBaseByMonth = <String, int>{};
final specialInsuranceBaseByMonth = <String, int>{};
final specialSavingsBaseByMonth = <String, int>{};

for (final previousNumber in consecutivePairs) {
  final previousKey = _monthKey(previousNumber);
  final currentKey = _monthKey(previousNumber + 1);

  final previousRecord = recordByMonth[previousKey] ?? {};
  final currentRecord = recordByMonth[currentKey] ?? {};

  // अघिल्लो महिनाको बाँकी बीमा र बचत।
  final previousTotal =
      _intValue(previousRecord['totalDue'], 2300);
  final previousInsurance =
      _intValue(previousRecord['insuranceAmount'], 300);

  final previousInsurancePaid =
      _intValue(previousRecord['insurancePaid']);

  final previousSavingsPaid =
      _intValue(previousRecord['savingsPaid']);

  final previousInsuranceRemaining =
      (previousInsurance - previousInsurancePaid)
          .clamp(0, previousInsurance)
          .toInt();

  final previousSavingsTotal =
      (previousTotal - previousInsurance)
          .clamp(0, previousTotal)
          .toInt();

  final previousSavingsRemaining =
      (previousSavingsTotal - previousSavingsPaid)
          .clamp(0, previousSavingsTotal)
          .toInt();

  // चालु विशेष जरिमाना महिनाको पूरा बीमा र बचत।
  final currentTotal =
      _intValue(currentRecord['totalDue'], 2300);
  final currentInsurance =
      _intValue(currentRecord['insuranceAmount'], 300);

  final currentSavings =
      (currentTotal - currentInsurance)
          .clamp(0, currentTotal)
          .toInt();

  specialInsuranceBaseByMonth[previousKey] =
      previousInsuranceRemaining;
  specialSavingsBaseByMonth[previousKey] =
      previousSavingsRemaining;

  specialInsuranceBaseByMonth[currentKey] =
      currentInsurance;
  specialSavingsBaseByMonth[currentKey] =
      currentSavings;

  specialPenaltyBaseByMonth[previousKey] =
      previousInsuranceRemaining + previousSavingsRemaining;

  specialPenaltyBaseByMonth[currentKey] =
      currentInsurance + currentSavings;
}

final specialMonths = specialPenaltyBaseByMonth.keys.toSet();

    final penaltyByMonth = <String, int>{};
    final netPenaltyByMonth = <String, int>{};
    final penaltyDetailsByMonth =
        <String, Map<String, dynamic>>{};

    int overdueRemaining = 0;
    int grossPenalty = 0;
    int totalWaived = 0;
    int netPenalty = 0;
    int totalInsurancePenaltyDue = 0;
    int totalSavingsPenaltyDue = 0;

    for (final entry in overdueMonths.entries) {
  final key = entry.key;
  final remaining = entry.value;
  final number = _monthNumber(key);
  final data = recordByMonth[key] ?? {};

  final normalPaid = _intValue(data['normalPenaltyPaid']);
  final specialPaid = _intValue(data['specialPenaltyPaid']);

  int normalRate = 0;
  int normalDue = 0;
  int specialDue = 0;

  // बीमा र बचतको बाँकी साँवा छुट्टाछुट्टै निकाल्ने।
  final totalDue = _intValue(data['totalDue'], 2300);
  final insuranceAmount =
      _intValue(data['insuranceAmount'], 300);

  final savingsAmount =
      (totalDue - insuranceAmount).clamp(0, totalDue).toInt();

  final insurancePaid = _intValue(data['insurancePaid']);
  final savingsPaid = _intValue(data['savingsPaid']);

  final insuranceRemaining =
      (insuranceAmount - insurancePaid)
          .clamp(0, insuranceAmount)
          .toInt();

  final savingsRemaining =
      (savingsAmount - savingsPaid)
          .clamp(0, savingsAmount)
          .toInt();

  int normalInsuranceDue = 0;
  int normalSavingsDue = 0;
  int specialInsuranceDue = 0;
  int specialSavingsDue = 0;

  if (specialMonths.contains(key)) {
    // विशेष जरिमाना ५०%।
    final insuranceBase =
        specialInsuranceBaseByMonth[key] ?? 0;
    final savingsBase =
        specialSavingsBaseByMonth[key] ?? 0;

    final insuranceTotal =
        _roundPercent(insuranceBase, 50);
    final savingsTotal =
        _roundPercent(savingsBase, 50);

    final specialTotal = insuranceTotal + savingsTotal;

    // पुरानो aggregate भुक्तानीलाई अनुपातअनुसार मिलाउने।
    int oldInsurancePaid = 0;
    int oldSavingsPaid = 0;

    final savedInsurancePaid =
        _intValue(data['specialInsurancePenaltyPaid']);
    final savedSavingsPaid =
        _intValue(data['specialSavingsPenaltyPaid']);

    if (savedInsurancePaid == 0 &&
        savedSavingsPaid == 0 &&
        specialPaid > 0 &&
        specialTotal > 0) {
      oldInsurancePaid =
          (specialPaid * insuranceTotal / specialTotal)
              .round()
              .clamp(0, insuranceTotal)
              .toInt();

      oldSavingsPaid =
          (specialPaid - oldInsurancePaid)
              .clamp(0, savingsTotal)
              .toInt();
    } else {
      oldInsurancePaid = savedInsurancePaid;
      oldSavingsPaid = savedSavingsPaid;
    }

    specialInsuranceDue =
        (insuranceTotal - oldInsurancePaid)
            .clamp(0, insuranceTotal)
            .toInt();

    specialSavingsDue =
        (savingsTotal - oldSavingsPaid)
            .clamp(0, savingsTotal)
            .toInt();

    specialDue =
        specialInsuranceDue + specialSavingsDue;
  } else {
    final age = currentMonthNumber - number;

    final penaltyStartDay =
        approvedNoticeMonths.contains(key) ? 16 : 11;

    int targetStage = 0;

    if (age == 0) {
      if (bsNow.day >= 26) {
        targetStage = 6;
      } else if (bsNow.day >= penaltyStartDay) {
        targetStage = 4;
      }
    } else if (age >= 1) {
      targetStage = 8;
    }

    if (targetStage > 0) {
      normalRate = targetStage;

      final insuranceTotal =
          _roundPercent(insuranceRemaining, targetStage);

      final savingsTotal =
          _roundPercent(savingsRemaining, targetStage);

      final normalTotal = insuranceTotal + savingsTotal;

      // पुरानो aggregate भुक्तानीलाई अनुपातअनुसार मिलाउने।
      int oldInsurancePaid = 0;
      int oldSavingsPaid = 0;

      final savedInsurancePaid =
          _intValue(data['normalInsurancePenaltyPaid']);
      final savedSavingsPaid =
          _intValue(data['normalSavingsPenaltyPaid']);

      if (savedInsurancePaid == 0 &&
          savedSavingsPaid == 0 &&
          normalPaid > 0 &&
          normalTotal > 0) {
        oldInsurancePaid =
            (normalPaid * insuranceTotal / normalTotal)
                .round()
                .clamp(0, insuranceTotal)
                .toInt();

        oldSavingsPaid =
            (normalPaid - oldInsurancePaid)
                .clamp(0, savingsTotal)
                .toInt();
      } else {
        oldInsurancePaid = savedInsurancePaid;
        oldSavingsPaid = savedSavingsPaid;
      }

      normalInsuranceDue =
          (insuranceTotal - oldInsurancePaid)
              .clamp(0, insuranceTotal)
              .toInt();

      normalSavingsDue =
          (savingsTotal - oldSavingsPaid)
              .clamp(0, savingsTotal)
              .toInt();

      normalDue =
          normalInsuranceDue + normalSavingsDue;
    }
  }

  // सामान्य वा विशेषमध्ये लागू हुने जरिमाना छान्ने।
  final isSpecial = specialMonths.contains(key);

  final grossInsurance = isSpecial
      ? specialInsuranceDue
      : normalInsuranceDue;

  final grossSavings = isSpecial
      ? specialSavingsDue
      : normalSavingsDue;

  final gross = grossInsurance + grossSavings;

  // छुट रकमलाई बीमा र बचतको जरिमानामा अनुपातअनुसार बाँड्ने।
  final waived = (waivedByMonth[key] ?? 0)
      .clamp(0, gross)
      .toInt();

  final waivedInsurance = gross > 0
      ? (waived * grossInsurance ~/ gross)
          .clamp(0, grossInsurance)
          .toInt()
      : 0;

  final waivedSavings = (waived - waivedInsurance)
      .clamp(0, grossSavings)
      .toInt();

  final netInsurance =
      (grossInsurance - waivedInsurance)
          .clamp(0, grossInsurance)
          .toInt();

  final netSavings =
      (grossSavings - waivedSavings)
          .clamp(0, grossSavings)
          .toInt();

  final net = netInsurance + netSavings;

  penaltyByMonth[key] = gross;
  netPenaltyByMonth[key] = net;

  penaltyDetailsByMonth[key] = {
    'remainingPrincipal': remaining,

    'normalRate': normalRate,
    'normalPenaltyPaid': normalPaid,
    'normalPenaltyDue': normalDue,
    'normalInsurancePenaltyDue': normalInsuranceDue,
    'normalSavingsPenaltyDue': normalSavingsDue,

    'specialPenaltyBase':
        specialPenaltyBaseByMonth[key] ?? 0,
    'specialPenaltyTotal':
        specialInsuranceDue + specialSavingsDue + specialPaid,
    'specialPenalty': specialDue,
    'specialPenaltyPaid': specialPaid,
    'specialInsurancePenaltyDue': specialInsuranceDue,
    'specialSavingsPenaltyDue': specialSavingsDue,

    // भुक्तानीमा प्रयोग हुने बाँकी जरिमाना।
    'insurancePenaltyDue': netInsurance,
    'savingsPenaltyDue': netSavings,

    'waivedAmount': waived,
    'waivedInsuranceAmount': waivedInsurance,
    'waivedSavingsAmount': waivedSavings,
    'netPenaltyDue': net,
    'isSpecial50Percent': isSpecial,
  };

  overdueRemaining += remaining;
  grossPenalty += gross;
  totalWaived += waived;
  netPenalty += net;
  totalInsurancePenaltyDue += netInsurance;
  totalSavingsPenaltyDue += netSavings;
}

    return {
      'remainingAmount': totalRemaining,
      'overdueAmount': overdueRemaining,
      'penaltyRate': specialMonths.isNotEmpty ? 50 : 0,
      'grossPenalty': grossPenalty,
      'waivedAmount': totalWaived,
      'penaltyAmount': netPenalty,
    'insurancePenaltyDue': totalInsurancePenaltyDue,
      'savingsPenaltyDue': totalSavingsPenaltyDue,
      'totalPayable': totalRemaining + netPenalty,
      'overdueMonths': overdueMonths.length,
      'penaltyByMonth': penaltyByMonth,
      'netPenaltyByMonth': netPenaltyByMonth,
      'penaltyDetailsByMonth': penaltyDetailsByMonth,
      'specialPenaltyMonths': specialMonths.toList(),
      'bsDate':
          '${bsNow.year}-${bsNow.month}-${bsNow.day}',
    };
  }

  Future<void> createPenaltyWaiver({
    required String memberUid,
    required String monthKey,
    required int waivedAmount,
    required String reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.uid != _adminUid) {
      throw StateError('यो सुविधा Admin का लागि मात्र हो।');
    }

    if (memberUid.trim().isEmpty) {
      throw ArgumentError('सदस्य UID आवश्यक छ।');
    }

    if (waivedAmount <= 0) {
      throw ArgumentError('माफी रकम शून्यभन्दा बढी हुनुपर्छ।');
    }

    if (reason.trim().isEmpty) {
      throw ArgumentError('माफीको कारण अनिवार्य लेख्नुहोस्।');
    }

    _monthNumber(monthKey);

    final penaltyData = await calculateMemberPenalty(
      memberUid: memberUid,
    );

    final penaltyMap =
        penaltyData['netPenaltyByMonth'] as Map<String, int>;

    final availablePenalty = penaltyMap[monthKey] ?? 0;

    if (availablePenalty <= 0) {
      throw StateError('यो महिनामा माफी गर्न बाँकी जरिमाना छैन।');
    }

    if (waivedAmount > availablePenalty) {
      throw StateError('माफी रकम बाँकी जरिमानाभन्दा बढी हुन मिल्दैन।');
    }

    final recordSnapshot = await _savings
        .where('memberUid', isEqualTo: memberUid)
        .where('monthKey', isEqualTo: monthKey)
        .get();

    if (recordSnapshot.docs.isEmpty) {
      throw StateError('यो महिनाको बचत रेकर्ड भेटिएन।');
    }

    final record = recordSnapshot.docs.first.data();
    final totalDue = _intValue(record['totalDue'], 2300);
    final paidAmount = _intValue(record['paidAmount']);

    if (paidAmount >= totalDue) {
      throw StateError(
        'भुक्तानी पूरा भइसकेको महिनाको जरिमाना माफ गर्न मिल्दैन।',
      );
    }

    await _waivers.add({
      'memberUid': memberUid,
      'monthKey': monthKey,
      'waivedAmount': waivedAmount,
      'reason': reason.trim(),
      'adminUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMemberWaivers(
    String memberUid,
  ) {
    return _waivers
        .where('memberUid', isEqualTo: memberUid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllWaivers() {
    return _waivers
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}
