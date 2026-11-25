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

  @override
  void initState() {
    super.initState();
    final today = DateTime.now().toNepaliDateTime();
    _yearController.text = today.year.toString();
    _monthController.text = today.month.toString();
    _checkConfig();
  }

  Future<void> _checkConfig() async {
    final doc = await FirebaseFirestore.instance
        .collection('bank_interest_config')
        .doc('current')
        .get();

    if (!mounted) return;
    setState(() => _initialized = doc.exists);
  }

  String get _userUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _userName =>
      FirebaseAuth.instance.currentUser?.displayName ?? 'Admin';

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
      if (mounted) {
        setState(() => _message = 'वार्षिक ब्याजदर ${rate}% सुरक्षित भयो।');
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
      final result = await _service.calculateInterestThrough(
        endDate: today,
      );

      if (mounted) {
        setState(() {
          _result = result;
          _message = 'ब्याज गणना सफल भयो।';
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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
            padding: const EdgeInsets.all(16),
            children: [
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
                        Expanded(
                          child: _field(
                            'नेपाली वर्ष',
                            _yearController,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            'महिना (१–१२)',
                            _monthController,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _saveRate,
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
                              'प्रारम्भिक मौज्दात सुरक्षित गर्नुहोस्'),
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
                        'सामान्य कोषको ब्याज',
                        _result!.generalInterest,
                      ),
                      const Divider(height: 22),
                      _resultRow(
                        'बीमा कोषको ब्याज',
                        _result!.insuranceInterest,
                      ),
                      const Divider(height: 22),
                      _resultRow(
                        'कुल ब्याज',
                        _result!.totalInterest,
                        bold: true,
                      ),
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
                      const Text(
                        'यो गणना पूर्वावलोकन हो। पोस्टिङ सुविधा अवधिको हिसाब दोहोरिन नदिने सुरक्षा लागू भएपछि सक्रिय गरिनेछ।',
                        style: TextStyle(
                          color: Colors.deepOrange,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_message.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 18),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _message.startsWith('त्रुटि')
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_message),
                ),
            ],
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

  Widget _resultRow(
    String label,
    double amount, {
    bool bold = false,
  }) {
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
