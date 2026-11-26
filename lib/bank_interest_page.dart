import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';

import 'bank_interest_calculation.dart';
import 'bank_interest_service.dart';

class BankInterestPage extends StatefulWidget {
  const BankInterestPage({super.key});

  @override
  State<BankInterestPage> createState() => _BankInterestPageState();
}

class _BankInterestPageState extends State<BankInterestPage> {
  final BankInterestService _service = BankInterestService();
  final _rateController = TextEditingController();
  final _yearController = TextEditingController();
  final _monthController = TextEditingController();

  bool _loading = false;
  bool _initialized = false;
  BankInterestCalculationResult? _result;
  String _message = '';
  Map<String, dynamic>? _currentRate;

  @override
  void initState() {
    super.initState();
    _rateController.addListener(_onRateChanged);
    final today = DateTime.now().toNepaliDateTime();
    _yearController.text = today.year.toString();
    _monthController.text = today.month.toString();
    _checkConfig();
    _loadCurrentRate();
  }

  Future<void> _checkConfig() async {
    final doc = await FirebaseFirestore.instance
        .collection('bank_interest_config')
        .doc('current')
        .get();

    if (!mounted) return;
    setState(() => _initialized = doc.exists);
  }

  Future<void> _loadCurrentRate() async {
    try {
      final rate = await _service.getCurrentAnnualRate();
      if (mounted) setState(() => _currentRate = rate);
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'हालको ब्याजदर लोड हुन सकेन: $e');
      }
    }
  }

  String get _userUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _userName =>
      FirebaseAuth.instance.currentUser?.displayName ?? 'Admin';

  void _onRateChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSaveRate {
    final rate = double.tryParse(_rateController.text.trim());
    final year = int.tryParse(_yearController.text.trim());
    final month = int.tryParse(_monthController.text.trim());
    return !_loading &&
        rate != null &&
        rate >= 0 &&
        rate <= 100 &&
        year != null &&
        year > 0 &&
        month != null &&
        month >= 1 &&
        month <= 12;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = '';
    });

    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'त्रुटि: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveRate() async {
    final rate = double.tryParse(_rateController.text.trim());
    final year = int.tryParse(_yearController.text.trim());
    final month = int.tryParse(_monthController.text.trim());

    if (rate == null || year == null || month == null) {
      setState(() => _message = 'ब्याजदर, नेपाली वर्ष र महिना सही राख्नुहोस्।');
      return;
    }

    await _run(() async {
      await _service.saveAnnualRate(
        annualRate: rate,
        effectiveBsYear: year,
        effectiveBsMonth: month,
        createdByUid: _userUid,
        createdByName: _userName,
      );
      await _loadCurrentRate();
      if (mounted) {
        _rateController.clear();
        setState(() => _message = 'वार्षिक ब्याजदर $rate% सुरक्षित भयो।');
      }
    });
  }

  Future<void> _initialize() async {
    await _run(() async {
      await _service.initializeOpeningBalances(
        createdByUid: _userUid,
        createdByName: _userName,
      );
      if (mounted) {
        setState(() {
          _initialized = true;
          _message = 'प्रारम्भिक मौज्दात सुरक्षित भयो।';
        });
      }
    });
  }

  Future<void> _calculate() async {
    await _run(() async {
      final today = DateTime.now().toNepaliDateTime();
      final result = await _service.calculateInterestThrough(endDate: today);

      if (mounted) {
        setState(() {
          _result = result;
          _message = 'ब्याज गणना सफल भयो।';
        });
      }
    });
  }

  bool get _isDistributionDate {
    final today = DateTime.now().toNepaliDateTime();
    return today.day == 1 && [4, 7, 10, 12].contains(today.month);
  }

  String _bsDate(NepaliDateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _postInterest() async {
    await _run(() async {
      final today = DateTime.now().toNepaliDateTime();

      if (today.day != 1 || ![4, 7, 10, 12].contains(today.month)) {
        throw StateError(
            'ब्याज साउन १, कात्तिक १, माघ १ वा चैत १ मा मात्र पोस्ट गर्न मिल्छ।');
      }

      final config = await FirebaseFirestore.instance
          .collection('bank_interest_config')
          .doc('current')
          .get();

      if (!config.exists) {
        throw StateError('प्रारम्भिक मौज्दातको विवरण भेटिएन।');
      }

      final parts =
          (config.data()!['calculationStartBsDate'] as String).split('-');
      final previousDate = NepaliDateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      final startDate = previousDate
          .toDateTime()
          .add(const Duration(days: 1))
          .toNepaliDateTime();

      final result = await _service.calculateInterestThrough(endDate: today);

      await _service.postCalculatedInterest(
        periodId:
            'bank_interest_${today.year}_${today.month.toString().padLeft(2, '0')}',
        startBsDate: _bsDate(startDate),
        endBsDate: _bsDate(today),
        result: result,
        postedByUid: _userUid,
        postedByName: _userName,
      );

      if (mounted) {
        setState(() {
          _result = null;
          _message = 'ब्याज सफलतापूर्वक पोस्ट भयो। अर्को अवधिको गणना सुरु भयो।';
        });
      }
    });
  }

  Widget _section({
    required String title,
    required Widget child,
    IconData? icon,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.green.shade700),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType keyboard = TextInputType.number,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
      ),
    );
  }

  String _money(double amount) {
    return 'रु. ${amount.toStringAsFixed(2)}';
  }

  @override
  void dispose() {
    _rateController.removeListener(_onRateChanged);
    _rateController.dispose();
    _yearController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'बैंक ब्याज व्यवस्थापन',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              Card(
                elevation: 2,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.green.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.green.shade50,
                        child:
                            Icon(Icons.percent, color: Colors.green.shade800),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'हाल लागू वार्षिक ब्याजदर',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currentRate == null
                                  ? 'हाल लागू दर उपलब्ध छैन'
                                  : '${_currentRate!['annualRate']}%  •  प्रभावकारी मिति: ${_currentRate!['effectiveBsDate'] ?? '${_currentRate!['effectiveBsYear']}-${_currentRate!['effectiveBsMonth']}'}',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _section(
                title: 'वार्षिक ब्याजदर निर्धारण',
                icon: Icons.percent,
                child: Column(
                  children: [
                    _field(
                      'वार्षिक ब्याजदर (%)',
                      _rateController,
                      hint: 'जस्तै: 6.5',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _field('नेपाली वर्ष', _yearController)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field('महिना (१–१२)', _monthController),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _canSaveRate ? _saveRate : null,
                        icon: const Icon(Icons.save),
                        label: const Text('ब्याजदर सुरक्षित गर्नुहोस्'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _section(
                title: 'प्रारम्भिक मौज्दात',
                icon: Icons.account_balance_wallet,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _initialized
                              ? Icons.check_circle
                              : Icons.info_outline,
                          color: _initialized ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _initialized
                                ? 'प्रारम्भिक मौज्दात सुरक्षित छ।'
                                : 'ब्याज गणना सुरु गर्न मौज्दात सुरक्षित गर्नुहोस्।',
                          ),
                        ),
                      ],
                    ),
                    if (!_initialized) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _initialize,
                          icon: const Icon(Icons.lock),
                          label: const Text(
                            'प्रारम्भिक मौज्दात सुरक्षित गर्नुहोस्',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _section(
                title: 'ब्याज गणना',
                icon: Icons.calculate,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'आजसम्मको सामान्य कोष र बीमा कोषको दैनिक ब्याज गणना गर्नुहोस्।',
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _loading || !_initialized ? null : _calculate,
                        icon: const Icon(Icons.refresh),
                        label: const Text('ब्याज गणना गर्नुहोस्'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_result != null)
                _section(
                  title: 'गणना परिणाम',
                  icon: Icons.receipt_long,
                  child: Column(
                    children: [
                      _resultRow(
                          'सामान्य कोषको कुल ब्याज', _result!.generalInterest),
                      _resultRow('सामान्य कोषको १३% कर',
                          _result!.generalInterest * 0.13),
                      _resultRow('सामान्य कोषमा खुद जम्मा',
                          _result!.generalInterest * 0.87,
                          bold: true),
                      const Divider(height: 18),
                      _resultRow(
                          'बीमा कोषको कुल ब्याज', _result!.insuranceInterest),
                      _resultRow('बीमा कोषको १३% कर',
                          _result!.insuranceInterest * 0.13),
                      _resultRow('बीमा कोषमा खुद जम्मा',
                          _result!.insuranceInterest * 0.87,
                          bold: true),
                      const Divider(height: 22),
                      _resultRow('कुल ब्याज', _result!.totalInterest,
                          bold: true),
                      _resultRow('कुल १३% कर', _result!.totalInterest * 0.13),
                      _resultRow('दुवै कोषमा जम्मा हुने खुद ब्याज',
                          _result!.totalInterest * 0.87,
                          bold: true),
                      const SizedBox(height: 12),
                      _infoRow('गणना भएका दिन', '${_result!.totalDays} दिन'),
                      _infoRow(
                        'सामान्य कोषको अन्तिम मौज्दात',
                        _money(_result!.generalClosingBalance),
                      ),
                      _infoRow(
                        'बीमा कोषको अन्तिम मौज्दात',
                        _money(_result!.insuranceClosingBalance),
                      ),
                      const SizedBox(height: 12),
                      if (_isDistributionDate) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _loading ? null : _postInterest,
                            icon: const Icon(Icons.account_balance),
                            label: const Text(
                                'कर कट्टी गरी ब्याज पोस्ट गर्नुहोस्'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ] else
                        const Text(
                          'यो पूर्वावलोकन मात्र हो। पोस्टिङ साउन १, कात्तिक १, माघ १ वा चैत १ मा मात्र उपलब्ध हुन्छ।',
                          style:
                              TextStyle(color: Colors.deepOrange, fontSize: 12),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          if (_message.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: SafeArea(
                top: false,
                child: Material(
                  elevation: 14,
                  color: _message.startsWith('त्रुटि')
                      ? Colors.red.shade800
                      : Colors.green.shade800,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _message.startsWith('त्रुटि')
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: Colors.white,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha: 0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, double amount, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          _money(amount),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: bold ? Colors.green.shade800 : null,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
