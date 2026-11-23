
import 'package:flutter/material.dart';
import 'admin_insurance_applications_page.dart';
import 'admin_insurance_records_page.dart';

class AdminInsuranceManagementPage extends StatelessWidget {
  const AdminInsuranceManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('बीमा व्यवस्थापन'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.assignment_outlined,
                  color: Colors.teal,
                  size: 30,
                ),
                title: const Text(
                  'बीमा आवेदनहरू',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'आएका आवेदन हेर्ने र स्वीकृत वा अस्वीकृत गर्ने',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const AdminInsuranceApplicationsPage(),
    ),
  );
},
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.history,
                  color: Colors.teal,
                  size: 30,
                ),
                title: const Text(
                  'स्वीकृत बीमा तथा भुक्तानी अभिलेख',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
  'स्वीकृत रकम, भुक्तानी र बाँकी रकमको विवरण',
),
trailing: const Icon(Icons.arrow_forward_ios, size: 16),
onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const AdminInsuranceRecordsPage(),
    ),
  );
},
              ),
            ),
          ],
        ),
      ),
    );
  }
}
