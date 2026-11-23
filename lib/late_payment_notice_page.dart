import 'package:flutter/material.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';

import 'late_payment_service.dart';
import 'nepali_digits.dart';

class LatePaymentNoticePage extends StatefulWidget {
  final String memberName;
  final String uid;

  const LatePaymentNoticePage({
    super.key,
    required this.memberName,
    required this.uid,
  });

  @override
  State<LatePaymentNoticePage> createState() =>
      _LatePaymentNoticePageState();
}

class _LatePaymentNoticePageState
    extends State<LatePaymentNoticePage> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitNotice() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final today = NepaliDateTime.fromDateTime(now);

    if (today.day < 1 || today.day > 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('यो फारम १ देखि ९ गतेसम्म मात्र पेश गर्न सकिन्छ।'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final monthKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}';

      final bsDate =
          '${today.year}-${today.month}-${today.day}';

      final adDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final deadlineAt = NepaliDateTime(
        today.year,
        today.month,
        10,
      ).toDateTime().add(const Duration(days: 1));

      await LatePaymentService().submitNotice(
        memberUid: widget.uid,
        memberName: widget.memberName,
        monthKey: monthKey,
        bsDate: bsDate,
        adDate: adDate,
        bsDay: today.day,
        deadlineAt: deadlineAt,
        reason: _reasonController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ढिलाइको जानकारी सफलतापूर्वक पेश भयो।'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('जानकारी पेश गर्न समस्या भयो: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = NepaliDateTime.fromDateTime(DateTime.now());
    final canSubmit = today.day >= 1 && today.day <= 9;

    return Scaffold(
      appBar: AppBar(
        title: const Text('भुक्तानी ढिलाइ जानकारी'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'सदस्य: ${widget.memberName}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text('आजको नेपाली मिति: ${toNepaliDigits('${today.year}-${today.month}-${today.day}')}'),
          const SizedBox(height: 18),
          const Text(
            'यस महिनाको भुक्तानी समयमा गर्न नसक्नुको कारण खुलाउनुहोस्। '
            'Admin बाट स्वीकृत भएमा १५ गतेसम्म बचत र बीमाको जरिमाना लाग्ने छैन।',
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 18),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _reasonController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'ढिलाइ हुनुको कारण',
                hintText: 'आफ्नो कारण यहाँ लेख्नुहोस्...',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'कृपया ढिलाइको कारण लेख्नुहोस्।';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 20),
          if (!canSubmit)
            const Text(
              'यो फारम प्रत्येक महिनाको १ देखि ९ गतेसम्म मात्र पेश गर्न सकिन्छ।',
              style: TextStyle(color: Colors.red),
            ),
          ElevatedButton(
            onPressed: (!canSubmit || _saving) ? null : _submitNotice,
            child: _saving
                ? const CircularProgressIndicator()
                : const Text('जानकारी पेश गर्नुहोस्'),
          ),
        ],
      ),
    );
  }
}