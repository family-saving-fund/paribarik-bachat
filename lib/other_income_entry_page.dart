import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';

import 'insurance_fund_ledger.dart';
import 'financial_ledger_service.dart';
import 'admin_audit_service.dart';
import 'nepali_digits.dart';

class OtherIncomeEntryPage extends StatefulWidget {
  const OtherIncomeEntryPage({super.key});

  @override
  State<OtherIncomeEntryPage> createState() => _OtherIncomeEntryPageState();
}

class _OtherIncomeEntryPageState extends State<OtherIncomeEntryPage> {
  final _formKey = GlobalKey<FormState>();
  final _sourceController = TextEditingController();
  final _amountController = TextEditingController();
  String _fundType = '';
  NepaliDateTime _selectedDate = NepaliDateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _sourceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showNepaliDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: NepaliDateTime(1970, 1, 1),
      lastDate: NepaliDateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    if (_fundType != 'savings' && _fundType != 'insurance') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('पहिले बचत कोष वा बीमा कोष छान्नुहोस्।'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;

    setState(() => _submitting = true);
    try {
      final db = FirebaseFirestore.instance;
      final adminSnapshot = await db.collection('member').doc(user.uid).get();
      final adminName = adminSnapshot.data()?['name']?.toString() ?? 'Admin';
      final fundRef = db.collection('fund_transactions').doc();
      final insuranceLedger = InsuranceFundLedger(firestore: db);
      final insuranceSeed = _fundType == 'insurance'
          ? await insuranceLedger.getSeedBalance()
          : 0.0;
      final ledgerService = FinancialLedgerService(firestore: db);
      final auditService = AdminAuditService(firestore: db);
      final bsDate = NepaliDateFormat('yyyy-MM-dd').format(_selectedDate);

      await db.runTransaction((transaction) async {
        final insuranceState = _fundType == 'insurance'
            ? await transaction.get(insuranceLedger.stateRef)
            : null;
        final ledgerEvents = [
          {
            'eventId': 'other_income_${fundRef.id}',
            'memberUid': 'institution',
            'memberName': 'संस्था',
            'transactionType': 'other_income',
            'amount': amount,
            'bsDate': bsDate,
            'description': _sourceController.text.trim(),
            'sourceCollection': 'fund_transactions',
            'sourceDocumentId': fundRef.id,
            'recordedByUid': user.uid,
            'recordedByName': adminName,
            'status': 'approved',
            'metadata': {
              'fundType': _fundType,
              'category': 'other_income',
              'source': _sourceController.text.trim(),
            },
          },
        ];
        final ledgerRefs = await ledgerService.prepareManyInTransaction(
          transaction: transaction,
          events: ledgerEvents,
        );
        final auditRef = await auditService.prepareRecordInTransaction(
          transaction: transaction,
          eventId: 'other_income_added_${fundRef.id}',
        );

        transaction.set(fundRef, {
          'fundType': _fundType,
          'category': 'other_income',
          'amount': amount,
          'source': _sourceController.text.trim(),
          'description': _sourceController.text.trim(),
          'bsDate': bsDate,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByUid': user.uid,
          'createdByName': adminName,
          'status': 'approved',
          'isTest': false,
        });

        if (_fundType == 'insurance' && insuranceState != null) {
          insuranceLedger.applyDelta(
            transaction: transaction,
            stateSnapshot: insuranceState,
            seedBalance: insuranceSeed,
            delta: amount.toDouble(),
          );
        }
        ledgerService.writePreparedManyInTransaction(
          transaction: transaction,
          refs: ledgerRefs,
          events: ledgerEvents,
        );
        auditService.writePreparedRecordInTransaction(
          transaction: transaction,
          auditRef: auditRef,
          data: {
            'adminUid': user.uid,
            'adminName': adminName,
            'action': 'other_income_added',
            'targetCollection': 'fund_transactions',
            'targetDocumentId': fundRef.id,
            'description': '${_fundType == 'insurance' ? 'बीमा कोष' : 'बचत कोष'} मा अन्य आम्दानी थपियो: ${_sourceController.text.trim()}',
            'amount': amount,
            'newValues': {
              'fundType': _fundType,
              'category': 'other_income',
              'source': _sourceController.text.trim(),
              'amount': amount,
              'bsDate': bsDate,
            },
          },
        );
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('अन्य आम्दानी सफलतापूर्वक सुरक्षित भयो।'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('आम्दानी सुरक्षित हुन सकेन: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF101B3A);
    return Scaffold(
      appBar: AppBar(
        title: const Text('अन्य आम्दानी प्रविष्टि'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'रकम जम्मा हुने कोष छान्नुहोस्',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FundChoiceButton(
                    label: 'बचत कोष',
                    icon: Icons.savings_outlined,
                    selected: _fundType == 'savings',
                    color: const Color(0xFF167D46),
                    onTap: _submitting
                        ? null
                        : () => setState(() => _fundType = 'savings'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FundChoiceButton(
                    label: 'बिमा कोष',
                    icon: Icons.health_and_safety_outlined,
                    selected: _fundType == 'insurance',
                    color: const Color(0xFF2469B3),
                    onTap: _submitting
                        ? null
                        : () => setState(() => _fundType = 'insurance'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            InkWell(
              onTap: _submitting ? null : _selectDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'वि.सं. मिति',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_month),
                ),
                child: Text(toNepaliDigits(
                  NepaliDateFormat('yyyy-MM-dd').format(_selectedDate),
                )),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _sourceController,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'आम्दानीको स्रोत',
                hintText: 'उदाहरण: भाडा, सेवा शुल्क, सहयोग आदि',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'आम्दानीको स्रोत लेख्नुहोस्।'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'रकम (रु.)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.currency_rupee),
              ),
              validator: (value) {
                final amount = int.tryParse(value?.trim() ?? '');
                if (amount == null || amount <= 0) {
                  return 'सही रकम लेख्नुहोस्।';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _submitting || _fundType.isEmpty ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_submitting ? 'सुरक्षित हुँदैछ...' : 'Submit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF167D46),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: const Text('रद्द गर्नुहोस्'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FundChoiceButton extends StatelessWidget {
  const _FundChoiceButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: selected ? color.withValues(alpha: 0.10) : Colors.white,
        side: BorderSide(color: selected ? color : Colors.grey.shade400, width: selected ? 2 : 1),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
