import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';

import 'bank_interest_calculation.dart';

import 'insurance_fund_ledger.dart';
import 'fund_service.dart';

/// बैंक ब्याजको दर, दैनिक गणना र पोस्टिङ व्यवस्थापन।
class BankInterestService {
  BankInterestService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance,
        _insuranceLedger = InsuranceFundLedger(
          firestore: firestore ?? FirebaseFirestore.instance,
        );

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _rates =>
      _db.collection('bank_interest_rates');

  CollectionReference<Map<String, dynamic>> get _periods =>
      _db.collection('bank_interest_periods');

  CollectionReference<Map<String, dynamic>> get _transactions =>
      _db.collection('bank_interest_transactions');

  final InsuranceFundLedger _insuranceLedger;

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  /// नयाँ वार्षिक ब्याजदर सुरक्षित गर्ने; पुरानो दरको इतिहास राख्ने।
  Future<void> saveAnnualRate({
    required double annualRate,
    required int effectiveBsYear,
    required int effectiveBsMonth,
    required String createdByUid,
    required String createdByName,
  }) async {
    if (annualRate < 0 || annualRate > 100) {
      throw ArgumentError('ब्याजदर ० देखि १०० प्रतिशतभित्र हुनुपर्छ।');
    }
    if (effectiveBsMonth < 1 || effectiveBsMonth > 12) {
      throw ArgumentError('नेपाली महिना १ देखि १२ सम्म हुनुपर्छ।');
    }

    final effectiveDate = NepaliDateTime(effectiveBsYear, effectiveBsMonth, 1);
    await _rates.add({
      'annualRate': annualRate,
      'effectiveBsYear': effectiveBsYear,
      'effectiveBsMonth': effectiveBsMonth,
      'effectiveBsDate':
          '$effectiveBsYear-${effectiveBsMonth.toString().padLeft(2, '0')}-01',
      'effectiveDate': Timestamp.fromDate(effectiveDate.toDateTime()),
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// दिइएको नेपाली मितिमा लागू हुने पछिल्लो ब्याजदर खोज्ने।
  Future<double> getAnnualRateForDate(NepaliDateTime date) async {
    final snapshot = await _rates
        .where('effectiveBsYear', isLessThanOrEqualTo: date.year)
        .orderBy('effectiveBsYear', descending: true)
        .get();

    final applicable = snapshot.docs.where((doc) {
      final data = doc.data();
      final year = (data['effectiveBsYear'] as num?)?.toInt() ?? 0;
      final month = (data['effectiveBsMonth'] as num?)?.toInt() ?? 0;
      return year < date.year || (year == date.year && month <= date.month);
    }).toList();

    applicable.sort((a, b) {
      final ay = (a.data()['effectiveBsYear'] as num).toInt();
      final am = (a.data()['effectiveBsMonth'] as num).toInt();
      final by = (b.data()['effectiveBsYear'] as num).toInt();
      final bm = (b.data()['effectiveBsMonth'] as num).toInt();
      final periodComparison = (by * 12 + bm).compareTo(ay * 12 + am);
      if (periodComparison != 0) return periodComparison;

      final aCreatedAt = a.data()['createdAt'];
      final bCreatedAt = b.data()['createdAt'];
      if (aCreatedAt is Timestamp && bCreatedAt is Timestamp) {
        return bCreatedAt.compareTo(aCreatedAt);
      }
      return b.id.compareTo(a.id);
    });

    if (applicable.isEmpty) return 0.0;
    return _toDouble(applicable.first.data()['annualRate']);
  }

  /// हालको नेपाली मितिमा लागू ब्याजदर र त्यसको प्रभावकारी मिति ल्याउने।
  Future<Map<String, dynamic>?> getCurrentAnnualRate() async {
    final today = DateTime.now().toNepaliDateTime();
    final snapshot = await _rates
        .where('effectiveBsYear', isLessThanOrEqualTo: today.year)
        .orderBy('effectiveBsYear', descending: true)
        .get();

    final applicable = snapshot.docs.where((doc) {
      final data = doc.data();
      final year = (data['effectiveBsYear'] as num?)?.toInt() ?? 0;
      final month = (data['effectiveBsMonth'] as num?)?.toInt() ?? 0;
      return year < today.year || (year == today.year && month <= today.month);
    }).toList();

    applicable.sort((a, b) {
      final ad = a.data();
      final bd = b.data();
      final ay = (ad['effectiveBsYear'] as num).toInt();
      final am = (ad['effectiveBsMonth'] as num).toInt();
      final by = (bd['effectiveBsYear'] as num).toInt();
      final bm = (bd['effectiveBsMonth'] as num).toInt();
      final comparison = (by * 12 + bm).compareTo(ay * 12 + am);
      if (comparison != 0) return comparison;

      final ac = ad['createdAt'];
      final bc = bd['createdAt'];
      if (ac is Timestamp && bc is Timestamp) {
        return bc.compareTo(ac);
      }
      return b.id.compareTo(a.id);
    });

    if (applicable.isEmpty) return null;
    final data = applicable.first.data();
    return {
      'annualRate': _toDouble(data['annualRate']),
      'effectiveBsYear': data['effectiveBsYear'],
      'effectiveBsMonth': data['effectiveBsMonth'],
      'effectiveBsDate': data['effectiveBsDate'],
    };
  }

  /// ब्याज गणनाको प्रारम्भिक मौज्दात एकपटक मात्र सुरक्षित गर्ने।
  Future<void> initializeOpeningBalances({
    required String createdByUid,
    required String createdByName,
  }) async {
    final configRef = _db.collection('bank_interest_config').doc('current');
    final existing = await configRef.get();

    if (existing.exists) {
      throw StateError('ब्याज गणनाको प्रारम्भिक मौज्दात पहिले नै सुरक्षित छ।');
    }

    final generalBalance = await FundService().calculateAvailableSavings();
    final insuranceBalance = await _insuranceLedger.getSeedBalance();

    if (generalBalance < 0 || insuranceBalance < 0) {
      throw StateError('कोषको प्रारम्भिक मौज्दात ऋणात्मक हुन मिल्दैन।');
    }

    final openingDate = DateTime.now().toNepaliDateTime();
    final bsDate =
        '${openingDate.year}-${openingDate.month.toString().padLeft(2, '0')}-${openingDate.day.toString().padLeft(2, '0')}';

    await configRef.set({
      'calculationStartBsDate': bsDate,
      'generalOpeningBalance': generalBalance,
      'insuranceOpeningBalance': insuranceBalance,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// गणना भएको ब्याज पोस्ट गर्ने; एउटै अवधिमा दोहोरो पोस्ट रोक्ने।
  Future<void> postCalculatedInterest({
    required String periodId,
    required String startBsDate,
    required String endBsDate,
    required BankInterestCalculationResult result,
    required String postedByUid,
    required String postedByName,
  }) async {
    final endParts = endBsDate.split('-');
    if (endParts.length != 3) {
      throw ArgumentError('ब्याज पोस्टिङको नेपाली मिति गलत छ।');
    }

    final endYear = int.tryParse(endParts[0]);
    final endMonth = int.tryParse(endParts[1]);
    final endDay = int.tryParse(endParts[2]);

    if (endYear == null ||
        endMonth == null ||
        endDay != 1 ||
        ![4, 7, 10, 12].contains(endMonth)) {
      throw ArgumentError(
        'ब्याज श्रावण १, कार्तिक १, माघ १ वा चैत १ मा मात्र पोस्ट गर्न मिल्छ।',
      );
    }

    if (periodId.trim().isEmpty) {
      throw ArgumentError('ब्याज अवधिको ID खाली हुन मिल्दैन।');
    }
    if (result.generalInterest < 0 || result.insuranceInterest < 0) {
      throw ArgumentError('ब्याज रकम ऋणात्मक हुन मिल्दैन।');
    }

    // दुवै कोषको ब्याजमा छुट्टाछुट्टै १३% कर कट्टी।
    const taxRate = 0.13;
    final generalTax = result.generalInterest * taxRate;
    final insuranceTax = result.insuranceInterest * taxRate;
    final generalNetInterest = result.generalInterest - generalTax;
    final insuranceNetInterest = result.insuranceInterest - insuranceTax;

    final periodRef = _periods.doc(periodId);
    final generalRef = _transactions.doc('${periodId}_general');
    final insuranceRef = _transactions.doc('${periodId}_insurance');
    final insuranceSeed = await _insuranceLedger.getSeedBalance();
    final insuranceStateRef = _insuranceLedger.stateRef;
    final configRef = _db.collection('bank_interest_config').doc('current');

    // वितरण अवधिमा लागू भएका ब्याजदरहरूको इतिहास तयार गर्ने।
    final startParts = startBsDate.split('-');
    final startPeriod =
        int.parse(startParts[0]) * 12 + int.parse(startParts[1]);
    final endPeriod = endYear * 12 + endMonth;

    final rateSnapshot = await _rates.get();
    final ratesByPeriod = <int, Map<String, dynamic>>{};

    for (final doc in rateSnapshot.docs) {
      final rate = doc.data();
      final year = (rate['effectiveBsYear'] as num).toInt();
      final month = (rate['effectiveBsMonth'] as num).toInt();
      final key = year * 12 + month;

      if (key > endPeriod) continue;

      final previous = ratesByPeriod[key];
      final previousCreated = previous?['createdAt'];
      final currentCreated = rate['createdAt'];

      if (previous == null ||
          (previousCreated is Timestamp &&
              currentCreated is Timestamp &&
              currentCreated.compareTo(previousCreated) > 0)) {
        ratesByPeriod[key] = {
          'annualRate': _toDouble(rate['annualRate']),
          'effectiveBsYear': year,
          'effectiveBsMonth': month,
          'effectiveBsDate': rate['effectiveBsDate'],
        };
      }
    }

    final sortedRates = ratesByPeriod.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    Map<String, dynamic>? startingRate;
    final rateHistory = <Map<String, dynamic>>[];

    for (final entry in sortedRates) {
      if (entry.key <= startPeriod) {
        startingRate = entry.value;
      } else if (entry.key <= endPeriod) {
        rateHistory.add(entry.value);
      }
    }

    if (startingRate != null) {
      rateHistory.insert(0, startingRate);
    }

    await _db.runTransaction((transaction) async {
      final periodSnapshot = await transaction.get(periodRef);
      if (periodSnapshot.exists) {
        throw StateError('यो अवधिको ब्याज पहिले नै पोस्ट गरिएको छ।');
      }

      final insuranceStateSnapshot = await transaction.get(insuranceStateRef);
      final configSnapshot = await transaction.get(configRef);

      if (!configSnapshot.exists) {
        throw StateError('ब्याज गणनाको प्रारम्भिक विवरण भेटिएन।');
      }

      if (result.insuranceInterest > 0) {
        _insuranceLedger.applyDelta(
          transaction: transaction,
          stateSnapshot: insuranceStateSnapshot,
          seedBalance: insuranceSeed,
          delta: insuranceNetInterest,
        );

        transaction.set(insuranceRef, {
          'periodId': periodId,
          'fundType': 'insurance',
          'incomeCategory': 'bank_interest',
          'isInstitutionIncome': true,
          'amount': insuranceNetInterest,
          'grossInterest': result.insuranceInterest,
          'taxRate': taxRate,
          'taxAmount': insuranceTax,
          'netInterest': insuranceNetInterest,
          'startBsDate': startBsDate,
          'endBsDate': endBsDate,
          'postedByUid': postedByUid,
          'postedByName': postedByName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (result.generalInterest > 0) {
        transaction.set(generalRef, {
          'periodId': periodId,
          'fundType': 'general',
          'incomeCategory': 'bank_interest',
          'isInstitutionIncome': true,
          'amount': generalNetInterest,
          'grossInterest': result.generalInterest,
          'taxRate': taxRate,
          'taxAmount': generalTax,
          'netInterest': generalNetInterest,
          'startBsDate': startBsDate,
          'endBsDate': endBsDate,
          'postedByUid': postedByUid,
          'postedByName': postedByName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.update(configRef, {
        'calculationStartBsDate': endBsDate,
        'generalOpeningBalance':
            result.generalClosingBalance + generalNetInterest,
        'insuranceOpeningBalance':
            result.insuranceClosingBalance + insuranceNetInterest,
        'lastPostedPeriodId': periodId,
        'lastPostedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(periodRef, {
        'periodId': periodId,
        'startBsDate': startBsDate,
        'endBsDate': endBsDate,
        'generalInterest': result.generalInterest,
        'insuranceInterest': result.insuranceInterest,
        'totalInterest': result.totalInterest,
        'generalTax': generalTax,
        'insuranceTax': insuranceTax,
        'totalTax': generalTax + insuranceTax,
        'generalNetInterest': generalNetInterest,
        'insuranceNetInterest': insuranceNetInterest,
        'totalNetInterest': generalNetInterest + insuranceNetInterest,
        'taxRate': taxRate,
        'rateHistory': rateHistory,
        'totalDays': result.totalDays,
        'status': 'posted',
        'postedByUid': postedByUid,
        'postedByName': postedByName,
        'postedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// सुरक्षित प्रारम्भिक मौज्दातपछि भएका वास्तविक कारोबार जोडेर ब्याज गणना गर्ने।
  Future<BankInterestCalculationResult> calculateInterestThrough({
    required NepaliDateTime endDate,
  }) async {
    final config =
        await _db.collection('bank_interest_config').doc('current').get();

    if (!config.exists) {
      throw StateError('पहिले ब्याजको प्रारम्भिक मौज्दात सुरक्षित गर्नुपर्छ।');
    }

    final data = config.data()!;
    final asOfParts = (data['calculationStartBsDate'] as String).split('-');
    final asOf = NepaliDateTime(
      int.parse(asOfParts[0]),
      int.parse(asOfParts[1]),
      int.parse(asOfParts[2]),
    );

    final startDate =
        asOf.toDateTime().add(const Duration(days: 1)).toNepaliDateTime();

    if (endDate.toDateTime().isBefore(startDate.toDateTime())) {
      throw ArgumentError('गणना गर्ने अन्तिम मिति सुरु मितिभन्दा अगाडि छ।');
    }

    final events = <BankInterestEvent>[];

    void addEvent({
      required dynamic rawDate,
      required BankInterestFundType fundType,
      required double delta,
      required String description,
    }) {
      final date = rawDate?.toString() ?? '';
      if (date.isEmpty || delta == 0) return;

      final parts = date.split('-');
      if (parts.length != 3) return;

      final eventDate = NepaliDateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );

      if (eventDate.toDateTime().isBefore(startDate.toDateTime()) ||
          eventDate.toDateTime().isAfter(endDate.toDateTime())) {
        return;
      }

      events.add(BankInterestEvent(
        bsDate: date,
        fundType: fundType,
        amountDelta: delta,
        description: description,
      ));
    }

    final ledger = await _db.collection('financial_ledger').get();

    for (final doc in ledger.docs) {
      final item = doc.data();
      if (item['status'] != 'approved') continue;

      final metadata =
          Map<String, dynamic>.from(item['metadata'] as Map? ?? {});

      switch (item['transactionType']) {
        case 'monthly_payment':
          addEvent(
            rawDate: item['bsDate'],
            fundType: BankInterestFundType.general,
            delta: _toDouble(metadata['personalSavingsAmount']) +
                _toDouble(metadata['savingsPenaltyAmount']),
            description: 'मासिक बचत',
          );
          addEvent(
            rawDate: item['bsDate'],
            fundType: BankInterestFundType.insurance,
            delta: _toDouble(metadata['insuranceSavingsAmount']) +
                _toDouble(metadata['insurancePenaltyAmount']),
            description: 'बीमा बचत',
          );
          break;

        case 'donation':
          addEvent(
            rawDate: item['bsDate'],
            fundType: BankInterestFundType.general,
            delta: _toDouble(metadata['institutionSavingsAmount']),
            description: 'संस्थागत चन्दा',
          );
          addEvent(
            rawDate: item['bsDate'],
            fundType: BankInterestFundType.insurance,
            delta: _toDouble(metadata['insuranceAmount']),
            description: 'बीमा चन्दा',
          );
          break;

        case 'other_income': {
          final isInsurance = metadata['fundType'] == 'insurance';
          addEvent(
            rawDate: item['bsDate'],
            fundType: isInsurance
                ? BankInterestFundType.insurance
                : BankInterestFundType.general,
            delta: _toDouble(item['amount']),
            description: isInsurance
                ? 'बीमा कोषको अन्य आम्दानी'
                : 'बचत कोषको अन्य आम्दानी',
          );
          break;
        }

        case 'loan_repayment':
          addEvent(
            rawDate: item['bsDate'],
            fundType: BankInterestFundType.general,
            delta: _toDouble(metadata['interestPaid']) +
                _toDouble(metadata['principalPaid']),
            description: 'ऋण किस्ता फिर्ता',
          );
          break;
      }
    }

    final loans = await _db.collection('loans').get();
    for (final doc in loans.docs) {
      final loan = doc.data();
      final date = loan['disbursedBsDate'];
      final amount = _toDouble(loan['disbursedAmount']);
      addEvent(
        rawDate: date,
        fundType: BankInterestFundType.general,
        delta: -amount,
        description: 'ऋण निकासा',
      );
    }

    final fundTransactions = await _db.collection('fund_transactions').get();

    for (final doc in fundTransactions.docs) {
      final item = doc.data();
      if (item['isTest'] == true || item['status'] != 'disbursed') {
        continue;
      }

      final category = item['category'];
      final amount = _toDouble(item['amount']);

      if (category == 'expense_withdrawal') {
        addEvent(
          rawDate: item['bsDate'],
          fundType: BankInterestFundType.general,
          delta: -amount,
          description: 'संस्थाको खर्च',
        );
      } else if (category == 'insurance_claim_payout') {
        addEvent(
          rawDate: item['bsDate'],
          fundType: BankInterestFundType.insurance,
          delta: -amount,
          description: 'बीमा दाबी भुक्तानी',
        );
      }
    }

    final engine = BankInterestCalculationEngine();
    return engine.calculate(
      startDate: startDate,
      endDate: endDate,
      generalOpeningBalance: _toDouble(data['generalOpeningBalance']),
      insuranceOpeningBalance: _toDouble(data['insuranceOpeningBalance']),
      events: events,
      annualRateForDate: getAnnualRateForDate,
    );
  }
}
