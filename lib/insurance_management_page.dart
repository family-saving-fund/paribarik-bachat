import 'package:flutter/material.dart';
import 'insurance_claim_form_page.dart';
import 'insurance_tracking_page.dart';
import 'insurance_history_page.dart';

class InsuranceManagementPage extends StatelessWidget {
  final String uid;
  final String memberName;
  final bool isAdmin;

  const InsuranceManagementPage({
    super.key,
    required this.uid,
    required this.memberName,
    required this.isAdmin,
  });

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
      _buildMenuCard(
        context,
        icon: Icons.assignment_outlined,
        title: 'बीमा दाबी आवेदन पेश गर्नुहोस्',
        subtitle: 'नयाँ बीमा दाबी आवेदन भर्नुहोस्',
        onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => InsuranceClaimFormPage(
        uid: uid,
        memberName: memberName,
      ),
    ),
  );
},
      ),
      const SizedBox(height: 12),
      _buildMenuCard(
        context,
        icon: Icons.track_changes_outlined,
        title: 'बीमा आवेदन ट्र्याकिङ',
        subtitle: 'स्वीकृत, अस्वीकृत र भुक्तानी विवरण',
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => InsuranceTrackingPage(uid: uid)));
        },
      ),
      const SizedBox(height: 12),
      _buildMenuCard(
        context,
        icon: Icons.history_outlined,
        title: 'बीमा इतिहास',
        subtitle: 'बीमा दाबी तथा प्राप्त भुक्तानीको सम्पूर्ण इतिहास',
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => InsuranceHistoryPage(uid: uid)));
        },
      ),
    ],
  ),
),
    );
  }
    
      Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      child: ListTile(
        leading: Icon(icon, size: 30, color: Colors.teal),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
