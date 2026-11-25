import 'package:flutter/material.dart';

import 'bank_interest_page.dart';

class OtherIncomeMenuPage extends StatelessWidget {
  const OtherIncomeMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF218838);

    return Scaffold(
      appBar: AppBar(
        title: const Text('अन्य आम्दानी'),
        backgroundColor: const Color(0xFF101B3A),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 3,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              leading: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: green,
                  size: 32,
                ),
              ),
              title: const Text(
                'अन्य आम्दानी',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('आम्दानीका स्रोतहरू व्यवस्थापन गर्नुहोस्'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.account_balance_outlined,
                  color: Color(0xFFE58A16),
                  size: 29,
                ),
              ),
              title: const Text(
                'बैंक ब्याज',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'ब्याजदर, दैनिक गणना र आम्दानी पोस्टिङ',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BankInterestPage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
