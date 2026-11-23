import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BankPaymentDetailsPage extends StatelessWidget {
  const BankPaymentDetailsPage({super.key});

  Future<void> _copyValue(
    BuildContext context, {
    required String value,
    required String label,
  }) async {
    await Clipboard.setData(ClipboardData(text: value));

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label Copy भयो।'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _copyRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _copyValue(
              context,
              value: value,
              label: label,
            ),
            icon: const Icon(Icons.copy, size: 17),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('भुक्तानी बैंक विवरण'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'assets/nabil_bank_qr.jpg',
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('QR Image देखाउन सकिएन।'),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: Colors.grey.shade400,
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _copyRow(
                        context,
                        label: 'बैंकको नाम कपी गर्नुहोस्',
                        value: 'NABIL BANK LTD.',
                      ),
                      Divider(
                        height: 1,
                        color: Colors.grey.shade300,
                      ),
                      _copyRow(
                        context,
                        label: 'खाता नम्बर कपी गर्नुहोस्',
                        value: '09810017511662',
                      ),
                      Divider(
                        height: 1,
                        color: Colors.grey.shade300,
                      ),
                      _copyRow(
                        context,
                  label: 'खातावालाको नाम कपी गर्नुहोस्',
                        value: 'Tika Ram Chuhan',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}