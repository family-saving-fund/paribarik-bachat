import 'package:nepali_date_picker/nepali_date_picker.dart';

enum BankInterestFundType {
  general,
  insurance,
}

class BankInterestEvent {
  const BankInterestEvent({
    required this.bsDate,
    required this.fundType,
    required this.amountDelta,
    required this.description,
  });

  final String bsDate;
  final BankInterestFundType fundType;

  /// आम्दानी/जम्मा भए positive, खर्च/निकासा भए negative।
  final double amountDelta;
  final String description;
}

class BankInterestCalculationResult {
  const BankInterestCalculationResult({
    required this.generalInterest,
    required this.insuranceInterest,
    required this.generalClosingBalance,
    required this.insuranceClosingBalance,
    required this.totalDays,
  });

  final double generalInterest;
  final double insuranceInterest;
  final double generalClosingBalance;
  final double insuranceClosingBalance;
  final int totalDays;

  double get totalInterest => generalInterest + insuranceInterest;
}

class BankInterestCalculationEngine {
  /// नेपाली वर्षको वास्तविक दिन संख्या निकाल्ने।
  int daysInNepaliYear(int year) {
    final start = NepaliDateTime(year, 1, 1).toDateTime();
    final nextStart = NepaliDateTime(year + 1, 1, 1).toDateTime();
    return nextStart.difference(start).inDays;
  }

  NepaliDateTime _parseBsDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) {
      throw FormatException('गलत नेपाली मिति: $value');
    }

    return NepaliDateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// दैनिक ब्याज गणना।
  ///
  /// opening balances गणना सुरु हुने मितिभन्दा अघिल्लो दिनको
  /// अन्तिम ब्यालेन्स हुनुपर्छ।
  ///
  /// annualRateForDate ले प्रत्येक दिन लागू हुने वार्षिक दर (%) दिन्छ।
  Future<BankInterestCalculationResult> calculate({
    required NepaliDateTime startDate,
    required NepaliDateTime endDate,
    required double generalOpeningBalance,
    required double insuranceOpeningBalance,
    required List<BankInterestEvent> events,
    required Future<double> Function(NepaliDateTime date) annualRateForDate,
  }) async {
    if (endDate.toDateTime().isBefore(startDate.toDateTime())) {
      throw ArgumentError('अन्तिम मिति सुरु मितिभन्दा अगाडि हुन मिल्दैन।');
    }

    if (generalOpeningBalance < 0 || insuranceOpeningBalance < 0) {
      throw ArgumentError('सुरुको ब्यालेन्स ऋणात्मक हुन मिल्दैन।');
    }

    final eventMap = <String, List<BankInterestEvent>>{};

    for (final event in events) {
      final date = _parseBsDate(event.bsDate);
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      eventMap.putIfAbsent(key, () => []).add(event);
    }

    var generalBalance = generalOpeningBalance;
    var insuranceBalance = insuranceOpeningBalance;
    var generalInterest = 0.0;
    var insuranceInterest = 0.0;
    var totalDays = 0;

    var currentDate = startDate.toDateTime();
    final lastDate = endDate.toDateTime();

    while (!currentDate.isAfter(lastDate)) {
      final bsDate = currentDate.toNepaliDateTime();
      final key =
          '${bsDate.year}-${bsDate.month.toString().padLeft(2, '0')}-${bsDate.day.toString().padLeft(2, '0')}';

      // आजको वास्तविक कारोबार पहिले लागू गर्ने।
      for (final event in eventMap[key] ?? const <BankInterestEvent>[]) {
        if (event.fundType == BankInterestFundType.general) {
          generalBalance += event.amountDelta;
        } else {
          insuranceBalance += event.amountDelta;
        }
      }

      if (generalBalance < -0.000001 || insuranceBalance < -0.000001) {
        throw StateError('मिति $key मा कोषको ब्यालेन्स ऋणात्मक भयो।');
      }

      if (generalBalance < 0) generalBalance = 0;
      if (insuranceBalance < 0) insuranceBalance = 0;

      final annualRate = await annualRateForDate(bsDate);

      if (annualRate < 0 || annualRate > 100) {
        throw ArgumentError('मिति $key को ब्याजदर अमान्य छ।');
      }

      final yearDays = daysInNepaliYear(bsDate.year);

      generalInterest += generalBalance * (annualRate / 100) / yearDays;

      insuranceInterest += insuranceBalance * (annualRate / 100) / yearDays;

      totalDays++;
      currentDate = currentDate.add(const Duration(days: 1));
    }

    return BankInterestCalculationResult(
      generalInterest: generalInterest,
      insuranceInterest: insuranceInterest,
      generalClosingBalance: generalBalance,
      insuranceClosingBalance: insuranceBalance,
      totalDays: totalDays,
    );
  }
}
