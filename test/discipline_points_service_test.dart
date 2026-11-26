import 'package:flutter_test/flutter_test.dart';
import 'package:paribarik_bachat_kosh/discipline_points_service.dart';

void main() {
  group('DisciplinePointsService', () {
    const noPenalty = <String, dynamic>{};

    test('दानको महिनागत गणना र रु.१०० पुगेपछि मात्र अंक', () {
      expect(
        DisciplinePointsService.donationMonthKey('2083 साल कार्तिक 30 गते'),
        '2083-07',
      );
      expect(
        DisciplinePointsService.donationMonthKey('२०८३-०८-०१'),
        '2083-08',
      );
      expect(DisciplinePointsService.donationTargetPoints(50), 0);
      expect(DisciplinePointsService.donationTargetPoints(100), 10);
      expect(DisciplinePointsService.donationTargetPoints(125), 13);
      expect(DisciplinePointsService.donationTargetPoints(150), 15);
      expect(DisciplinePointsService.donationTargetPoints(255), 26);
      expect(
        DisciplinePointsService.donationPointDelta(
          previousTotal: 50,
          previousPointsAwarded: 0,
          newDonationAmount: 50,
        ),
        10,
      );
      expect(
        DisciplinePointsService.donationPointDelta(
          previousTotal: 100,
          previousPointsAwarded: 10,
          newDonationAmount: 50,
        ),
        5,
      );
    });

    test('महिना फेरिँदा अघिल्लो महिनाको दान नयाँ महिनामा जोडिँदैन', () {
      final previousMonth =
          DisciplinePointsService.donationMonthKey('2083 साल कार्तिक 30 गते');
      final nextMonth =
          DisciplinePointsService.donationMonthKey('2083 साल मंसिर 1 गते');
      expect(previousMonth, '2083-07');
      expect(nextMonth, '2083-08');
      expect(previousMonth, isNot(nextMonth));
    });

    test('१२ महिनाको पूर्ण एकमुष्ट भुक्तानीमा +५०० मात्र', () {
      final months = List.generate(
        12,
        (index) => '2083-${(index + 1).toString().padLeft(2, '0')}',
      );
      final result = DisciplinePointsService.calculate(
        paymentType: 'full',
        processedMonthKeys: months,
        fullyPaidMonthKeys: months,
        bsDate: '2083 साल कार्तिक 3 गते सोमबार',
        penaltyDetailsByMonth: noPenalty,
        previousPartialCount: 0,
      );
      expect(result.points, 500);
    });

    test('११, ६, ५, ३ र २ महिनाका पूर्ण भुक्तानीमा सही अंक', () {
      for (final item in [
        (count: 11, points: 100),
        (count: 6, points: 100),
        (count: 5, points: 50),
        (count: 3, points: 50),
        (count: 2, points: 30),
      ]) {
        final months = List.generate(
          item.count,
          (index) => '2083-${(index + 1).toString().padLeft(2, '0')}',
        );
        final result = DisciplinePointsService.calculate(
          paymentType: 'full',
          processedMonthKeys: months,
          fullyPaidMonthKeys: months,
          bsDate: '2083 साल कार्तिक 3 गते सोमबार',
          penaltyDetailsByMonth: noPenalty,
          previousPartialCount: 0,
        );
        expect(result.points, item.points);
      }
    });

    test('पूर्ण भुक्तानीको मिति अनुसार अंक', () {
      final cases = [
        (day: 1, points: 20),
        (day: 2, points: 20),
        (day: 3, points: 20),
        (day: 4, points: 10),
        (day: 5, points: 10),
        (day: 6, points: 0),
        (day: 7, points: 5),
        (day: 9, points: 5),
        (day: 10, points: 1),
      ];
      for (final item in cases) {
        final result = DisciplinePointsService.calculate(
          paymentType: 'full',
          processedMonthKeys: const ['2083-07'],
          fullyPaidMonthKeys: const ['2083-07'],
          bsDate: '2083 साल कार्तिक ${item.day} गते सोमबार',
          penaltyDetailsByMonth: noPenalty,
          previousPartialCount: 0,
        );
        expect(result.points, item.points, reason: 'BS दिन ${item.day}');
      }
    });

    test('पूर्ण रकमले महिना पूरा नभएसम्म मिति बोनस दिँदैन', () {
      final result = DisciplinePointsService.calculate(
        paymentType: 'full',
        processedMonthKeys: const ['2083-07'],
        fullyPaidMonthKeys: const [],
        bsDate: '2083 साल कार्तिक 2 गते सोमबार',
        penaltyDetailsByMonth: noPenalty,
        previousPartialCount: 0,
      );
      expect(result.points, 0);
    });

    test('चयन गरिएका महिनामध्ये वास्तवमै पूरा भएका महिनाको मात्र एकमुष्ट अंक', () {
      final selected = List.generate(
        12,
        (index) => '2083-${(index + 1).toString().padLeft(2, '0')}',
      );
      final fullyPaid = selected.take(5).toList();
      final result = DisciplinePointsService.calculate(
        paymentType: 'full',
        processedMonthKeys: selected,
        fullyPaidMonthKeys: fullyPaid,
        bsDate: '2083 साल कार्तिक 3 गते सोमबार',
        penaltyDetailsByMonth: noPenalty,
        previousPartialCount: 0,
      );
      expect(result.points, 50);
    });

    test('पहिलो र दोस्रो आंशिक भुक्तानीमा +३ र +१', () {
      final first = DisciplinePointsService.calculate(
        paymentType: 'partial',
        processedMonthKeys: const ['2083-07'],
        fullyPaidMonthKeys: const [],
        bsDate: '2083 साल कार्तिक 2 गते सोमबार',
        penaltyDetailsByMonth: noPenalty,
        previousPartialCount: 0,
      );
      final second = DisciplinePointsService.calculate(
        paymentType: 'partial',
        processedMonthKeys: const ['2083-07'],
        fullyPaidMonthKeys: const [],
        bsDate: '2083 साल कार्तिक 10 गते सोमबार',
        penaltyDetailsByMonth: noPenalty,
        previousPartialCount: 1,
      );
      expect(first.points, 3);
      expect(second.points, 1);
    });

    test('जरिमाना हुँदा एउटै सबैभन्दा लागू ऋणात्मक अंक मात्र', () {
      final cases = [
        (rate: 4, paymentType: 'full', points: -2),
        (rate: 4, paymentType: 'partial', points: -5),
        (rate: 6, paymentType: 'full', points: -5),
        (rate: 8, paymentType: 'partial', points: -10),
      ];
      for (final item in cases) {
        final result = DisciplinePointsService.calculate(
          paymentType: item.paymentType,
          processedMonthKeys: const ['2083-07'],
          fullyPaidMonthKeys: item.paymentType == 'full'
              ? const ['2083-07']
              : const [],
          bsDate: '2083 साल कार्तिक 2 गते सोमबार',
          penaltyDetailsByMonth: {
            '2083-07': {'normalRate': item.rate},
          },
          previousPartialCount: 0,
        );
        expect(result.points, item.points);
      }
    });

    test('५० प्रतिशत विशेष जरिमानामा -२० मात्र', () {
      final result = DisciplinePointsService.calculate(
        paymentType: 'partial',
        processedMonthKeys: const ['2083-07'],
        fullyPaidMonthKeys: const [],
        bsDate: '2083 साल कार्तिक 2 गते सोमबार',
        penaltyDetailsByMonth: {
          '2083-07': {
            'normalRate': 8,
            'specialPenaltyTotal': 500,
          },
        },
        previousPartialCount: 0,
      );
      expect(result.points, -20);
    });
  });
}
