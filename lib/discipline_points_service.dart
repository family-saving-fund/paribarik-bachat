import 'nepali_digits.dart';

class DisciplinePointAward {
  const DisciplinePointAward({required this.points, required this.reason});

  final int points;
  final String reason;
}

class DisciplinePointsService {
  static const Map<String, int> _bsMonths = {
    'बैशाख': 1,
    'वैशाख': 1,
    'जेठ': 2,
    'असार': 3,
    'साउन': 4,
    'श्रावण': 4,
    'भदौ': 5,
    'भाद्र': 5,
    'असोज': 6,
    'कार्तिक': 7,
    'मंसिर': 8,
    'पुष': 9,
    'पौष': 9,
    'माघ': 10,
    'फागुन': 11,
    'चैत': 12,
    'चैत्र': 12,
  };

  static ({int year, int month, int day})? _parseBsDate(String value) {
    final normalized = toWesternDigits(value);
    final numericDate = RegExp(r'^(20\d{2})[-/]([0-1]?\d)[-/]([0-3]?\d)$')
        .firstMatch(normalized.trim());
    if (numericDate != null) {
      final year = int.tryParse(numericDate.group(1)!);
      final month = int.tryParse(numericDate.group(2)!);
      final day = int.tryParse(numericDate.group(3)!);
      if (year == null || month == null || day == null ||
          month < 1 || month > 12 || day < 1 || day > 32) {
        return null;
      }
      return (year: year, month: month, day: day);
    }

    final yearMatch = RegExp(r'(20\d{2})').firstMatch(normalized);
    final dayMatch = RegExp(r'(\d{1,2})\s*गते').firstMatch(normalized);
    if (yearMatch == null || dayMatch == null) return null;
    final year = int.tryParse(yearMatch.group(1)!);
    final day = int.tryParse(dayMatch.group(1)!);
    if (year == null || day == null) return null;
    int? month;
    for (final entry in _bsMonths.entries) {
      if (normalized.contains(entry.key)) {
        month = entry.value;
        break;
      }
    }
    if (month == null || day < 1 || day > 32) return null;
    return (year: year, month: month, day: day);
  }

  /// दानको अंक नेपाली वर्ष-महिनाको आधारमा छुट्याउन प्रयोग हुन्छ।
  static String? donationMonthKey(String bsDate) {
    final parsed = _parseBsDate(bsDate);
    if (parsed == null) return null;
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}';
  }

  /// एउटै नेपाली महिनामा रु.१०० पुगेपछि कुल दानको १०% लक्ष्य अंक।
  static int donationTargetPoints(int monthlyDonationTotal) {
    if (monthlyDonationTotal < 100) return 0;
    return (monthlyDonationTotal / 10).round();
  }

  /// थप दानपछि पहिले दिइसकेको अंक घटाएर बाँकी अंक मात्र फर्काउँछ।
  static int donationPointDelta({
    required int previousTotal,
    required int previousPointsAwarded,
    required int newDonationAmount,
  }) {
    final newTotal = previousTotal + newDonationAmount;
    return donationTargetPoints(newTotal) - previousPointsAwarded;
  }

  static DisciplinePointAward calculate({
    required String paymentType,
    required List<String> processedMonthKeys,
    required List<String> fullyPaidMonthKeys,
    required String bsDate,
    required Map<String, dynamic> penaltyDetailsByMonth,
    required int previousPartialCount,
  }) {
    final parsedDate = _parseBsDate(bsDate);
    final selectedMonthKey =
        processedMonthKeys.length == 1 ? processedMonthKeys.first : null;
    final currentMonthKey = parsedDate == null
        ? null
        : '${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}';

    var highestPenaltyRate = 0;
    var hasSpecialPenalty = false;
    for (final monthKey in processedMonthKeys) {
      final raw = penaltyDetailsByMonth[monthKey];
      if (raw is! Map) continue;
      final detail = Map<String, dynamic>.from(raw);
      final rate = (detail['normalRate'] as num?)?.toInt() ?? 0;
      if (rate > highestPenaltyRate) highestPenaltyRate = rate;
      final special = (detail['specialPenaltyTotal'] as num?)?.toDouble() ??
          (detail['specialPenalty'] as num?)?.toDouble() ??
          (detail['specialPenaltyDue'] as num?)?.toDouble() ??
          0;
      if (special > 0) hasSpecialPenalty = true;
    }

    final hasPenalty = hasSpecialPenalty || highestPenaltyRate > 0;
    if (hasPenalty) {
      if (hasSpecialPenalty) {
        return const DisciplinePointAward(
          points: -20,
          reason: '५०% विशेष जरिमाना अवधिमा भुक्तानी',
        );
      }
      if (highestPenaltyRate >= 8) {
        return const DisciplinePointAward(
          points: -10,
          reason: 'तेस्रो जरिमाना अवधि (८%) मा भुक्तानी',
        );
      }
      if (highestPenaltyRate >= 6) {
        return const DisciplinePointAward(
          points: -5,
          reason: 'दोस्रो जरिमाना अवधि (६%) मा भुक्तानी',
        );
      }
      if (paymentType == 'partial') {
        return const DisciplinePointAward(
          points: -5,
          reason: 'जरिमाना लागेपछि आंशिक भुक्तानी',
        );
      }
      if (highestPenaltyRate >= 4) {
        return const DisciplinePointAward(
          points: -2,
          reason: 'पहिलो जरिमाना अवधि (४%) मा भुक्तानी',
        );
      }
    }

    if (paymentType == 'full') {
      final count = fullyPaidMonthKeys.length;
      if (count >= 12) {
        return const DisciplinePointAward(points: 500, reason: '१२ महिना वा बढीको एकमुष्ट बचत');
      }
      if (count >= 6) {
        return const DisciplinePointAward(points: 100, reason: '६ देखि ११ महिनाको एकमुष्ट बचत');
      }
      if (count >= 3) {
        return const DisciplinePointAward(points: 50, reason: '३ देखि ५ महिनाको एकमुष्ट बचत');
      }
      if (count == 2) {
        return const DisciplinePointAward(points: 30, reason: '२ महिनाको एकमुष्ट बचत');
      }
      if (count == 1 &&
          parsedDate != null &&
          fullyPaidMonthKeys.contains(currentMonthKey)) {
        if (parsedDate.day <= 3) {
          return const DisciplinePointAward(points: 20, reason: 'महिनाको ३ गते वा त्यसभन्दा अघि पूरा भुक्तानी');
        }
        if (parsedDate.day <= 5) {
          return const DisciplinePointAward(points: 10, reason: 'महिनाको ४ देखि ५ गते पूरा भुक्तानी');
        }
        if (parsedDate.day >= 7 && parsedDate.day <= 9) {
          return const DisciplinePointAward(points: 5, reason: 'महिनाको ७ देखि ९ गते पूरा भुक्तानी');
        }
        if (parsedDate.day == 10) {
          return const DisciplinePointAward(points: 1, reason: 'महिनाको १० गते पूरा भुक्तानी');
        }
      }
    }

    if (paymentType == 'partial' &&
        parsedDate != null &&
        selectedMonthKey == currentMonthKey) {
      if (previousPartialCount == 0 && parsedDate.day < 3) {
        return const DisciplinePointAward(points: 3, reason: 'महिनाको ३ गतेअघि पहिलो आंशिक भुक्तानी');
      }
      if (previousPartialCount == 1 && parsedDate.day <= 10) {
        return const DisciplinePointAward(points: 1, reason: 'महिनाको १० गतेभित्र दोस्रो आंशिक भुक्तानी');
      }
    }

    return const DisciplinePointAward(points: 0, reason: 'यो भुक्तानीमा अनुशासन अंक लागू भएन');
  }
}
