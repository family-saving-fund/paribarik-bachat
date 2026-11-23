import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'nepali_digits.dart';

class AdminMemberManagementPage extends StatefulWidget {
  const AdminMemberManagementPage({super.key});
  @override
  State<AdminMemberManagementPage> createState() => _AdminMemberManagementPageState();
}

class _AdminMemberManagementPageState extends State<AdminMemberManagementPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('सदस्य व्यवस्थापन')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
          controller: _search,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'सदस्यको नाम वा इमेल खोज्नुहोस्', border: OutlineInputBorder()),
          onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
        )),
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('member').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('सदस्य सूची लोड गर्न सकिएन।'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final members = snapshot.data!.docs.where((doc) {
              final data = doc.data();
              final name = (data['name'] ?? '').toString().toLowerCase();
              final email = (data['email'] ?? '').toString().toLowerCase();
              return name.contains(_query) || email.contains(_query);
            }).toList()..sort((a, b) => (a.data()['name'] ?? '').toString().compareTo((b.data()['name'] ?? '').toString()));
            if (members.isEmpty) return const Center(child: Text('सदस्य भेटिएन।'));
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: members.length,
              itemBuilder: (context, index) {
                final doc = members[index]; final data = doc.data();
                final role = data['role']?.toString() ?? 'member';
                return Card(child: ListTile(
                  leading: CircleAvatar(child: Text((data['name']?.toString().trim().isNotEmpty ?? false) ? data['name'].toString().trim().substring(0, 1) : '?')),
                  title: Text(data['name']?.toString() ?? 'नाम उपलब्ध छैन', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${data['email'] ?? 'इमेल उपलब्ध छैन'}\n${role == 'admin' ? 'प्रशासक' : 'सदस्य'} • ${data['accountActive'] == false ? 'खाता निष्क्रिय' : 'खाता सक्रिय'}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _AdminMemberDetailsPage(uid: doc.id, initialData: data))),
                ));
              },
            );
          },
        )),
      ]),
    );
  }
}

class _AdminMemberDetailsPage extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> initialData;
  const _AdminMemberDetailsPage({required this.uid, required this.initialData});
  @override
  State<_AdminMemberDetailsPage> createState() => _AdminMemberDetailsPageState();
}

class _AdminMemberDetailsPageState extends State<_AdminMemberDetailsPage> {
  late final TextEditingController _mobile = TextEditingController(text: widget.initialData['mobileNumber']?.toString() ?? '');
  late final TextEditingController _dob = TextEditingController(text: widget.initialData['dateOfBirth']?.toString() ?? '');
  late final TextEditingController _address = TextEditingController(text: widget.initialData['address']?.toString() ?? '');
  late final TextEditingController _occupation = TextEditingController(text: widget.initialData['occupation']?.toString() ?? '');
  late final TextEditingController _citizenship = TextEditingController(text: widget.initialData['citizenshipNumber']?.toString() ?? '');
  final List<Map<String, TextEditingController>> _family = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final values = widget.initialData['familyMembers'];
    if (values is List) {
      for (final item in values) {
        if (item is Map) _family.add({
          'name': TextEditingController(text: item['name']?.toString() ?? ''),
          'relation': TextEditingController(text: item['relation']?.toString() ?? ''),
          'dateOfBirth': TextEditingController(text: item['dateOfBirth']?.toString() ?? ''),
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_mobile, _dob, _address, _occupation, _citizenship]) { c.dispose(); }
    for (final item in _family) { for (final c in item.values) { c.dispose(); } }
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    NepaliDateTime initial = NepaliDateTime.now();
    final raw = controller.text.trim();
    final parts = raw.split('-');
    if (parts.length == 3) {
      final y = int.tryParse(parts[0]); final m = int.tryParse(parts[1]); final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) { try { initial = NepaliDateTime(y, m, d); } catch (_) {} }
    }
    final picked = await showNepaliDatePicker(context: context, initialDate: initial, firstDate: NepaliDateTime(1970, 1, 1), lastDate: NepaliDateTime.now());
    if (picked != null) setState(() => controller.text = NepaliDateFormat('yyyy-MM-dd').format(picked));
  }

  void _addFamily() => setState(() => _family.add({
    'name': TextEditingController(), 'relation': TextEditingController(), 'dateOfBirth': TextEditingController(),
  }));

  Future<void> _changeAccountStatus() async {
    final current = widget.initialData;
    if (current['accountActive'] == false) {
      final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('खाता पुनः सक्रिय गर्ने?'),
        content: const Text('सदस्यको खाता सक्रिय हुनेछ। पुनः सक्रिय भएको मितिबाट १० दिनसम्म नयाँ जरिमाना लाग्ने छैन।'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('रद्द')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('सक्रिय गर्नुहोस्'))],
      ));
      if (confirm != true) return;
      await FirebaseFirestore.instance.collection('member').doc(widget.uid).set({
        'accountActive': true,
        'deactivationStartsAt': null,
        'deactivationEndsAt': null,
        'reactivatedAt': FieldValue.serverTimestamp(),
        'penaltyResumeAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 10))),
        'penaltyResumeMode': current['deactivationMode'] == 'indefinite' ? 'current_month_only' : 'fixed_period',
        'accountStatusUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('खाता पुनः सक्रिय भयो।')));
        Navigator.pop(context);
      }
      return;
    }

    String mode = 'fixed';
    String duration = '20 दिन';
    DateTime startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    DateTime customEnd = DateTime.now().add(const Duration(days: 20));
    final choices = <String, Duration>{
      '१० दिन': const Duration(days: 10), '२० दिन': const Duration(days: 20),
      '१ महिना': const Duration(days: 30), '२ महिना': const Duration(days: 60),
      '३ महिना': const Duration(days: 90), '१ वर्ष': const Duration(days: 365),
    };
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: const Text('सदस्य खाता निष्क्रिय गर्ने'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: mode, decoration: const InputDecoration(labelText: 'निष्क्रिय गर्ने प्रकार'), items: const [
          DropdownMenuItem(value: 'fixed', child: Text('निश्चित अवधिसम्म')),
          DropdownMenuItem(value: 'indefinite', child: Text('अनिश्चितकालीन (Admin ले सक्रिय नगरेसम्म)')),
        ], onChanged: (v) => setDialog(() => mode = v ?? 'fixed')),
        if (mode == 'fixed') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: duration, decoration: const InputDecoration(labelText: 'अवधि'), items: [...choices.keys.map((v) => DropdownMenuItem(value: v, child: Text(v))), const DropdownMenuItem(value: 'custom', child: Text('आफैँ मिति छान्नुहोस्'))], onChanged: (v) async {
            if (v == null) return;
            if (v == 'custom') {
              final firstAllowed = startDate.add(const Duration(days: 1));
              final picked = await showDatePicker(context: ctx, initialDate: customEnd.isAfter(firstAllowed) ? customEnd : firstAllowed, firstDate: firstAllowed, lastDate: DateTime.now().add(const Duration(days: 3650)));
              if (picked != null) setDialog(() { duration = v; customEnd = picked; });
            } else { setDialog(() { duration = v; customEnd = startDate.add(choices[v]!); }); }
          }),
          if (duration == 'custom') Text('अन्तिम मिति: ${customEnd.year}-${customEnd.month.toString().padLeft(2, '0')}-${customEnd.day.toString().padLeft(2, '0')}'),
        ] else const Padding(padding: EdgeInsets.only(top: 10), child: Text('यो खाता Admin ले म्यानुअल रूपमा सक्रिय नगरेसम्म निष्क्रिय रहनेछ।')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')), ElevatedButton(onPressed: () => Navigator.pop(ctx, {'mode': mode, 'start': mode == 'fixed' ? startDate : DateTime.now(), 'end': mode == 'fixed' ? customEnd : null}), child: const Text('निष्क्रिय गर्नुहोस्'))],
    )));
    if (result == null) return;
    final end = result['end'] as DateTime?;
    final start = result['start'] as DateTime? ?? DateTime.now();
    final startsInFuture = start.isAfter(DateTime.now());
    await FirebaseFirestore.instance.collection('member').doc(widget.uid).set({
      'accountActive': startsInFuture,
      'deactivationMode': result['mode'],
      'deactivationStartsAt': Timestamp.fromDate(DateTime(start.year, start.month, start.day)),
      'deactivatedAt': startsInFuture ? null : FieldValue.serverTimestamp(),
      'deactivationEndsAt': end == null ? null : Timestamp.fromDate(DateTime(end.year, end.month, end.day, 23, 59, 59)),
      'deactivationSetBy': FirebaseAuth.instance.currentUser?.uid,
      'accountStatusUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('सदस्यको खाता निष्क्रिय गरियो।')));
      Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final family = _family.map((item) => {
      'name': item['name']!.text.trim(), 'relation': item['relation']!.text.trim(), 'dateOfBirth': item['dateOfBirth']!.text.trim(),
    }).where((item) => (item['name'] ?? '').isNotEmpty).toList();
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('member').doc(widget.uid).set({
        'mobileNumber': _mobile.text.trim(), 'dateOfBirth': _dob.text.trim(),
        'address': _address.text.trim(), 'occupation': _occupation.text.trim(),
        'citizenshipNumber': _citizenship.text.trim(), 'familyMembers': family,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
        'adminProfileUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('सदस्य विवरण सुरक्षित भयो।')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('सुरक्षित गर्न सकिएन: $e')));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.initialData;
    return Scaffold(
      appBar: AppBar(title: const Text('सदस्य विवरण सम्पादन')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(leading: const Icon(Icons.person), title: Text(data['name']?.toString() ?? 'नाम छैन'), subtitle: Text('${data['email'] ?? ''}\n${data['role'] == 'admin' ? 'प्रशासक' : 'सदस्य'}'))),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(data['accountActive'] == false ? Icons.block : Icons.verified_user, color: data['accountActive'] == false ? Colors.red : Colors.green),
            title: Text(data['accountActive'] == false ? 'खाता निष्क्रिय छ' : 'खाता सक्रिय छ', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(data['accountActive'] == false ? (data['deactivationMode'] == 'indefinite' ? 'अनिश्चितकालीन निष्क्रियता' : 'निश्चित अवधिको निष्क्रियता') : 'सदस्यको खाता सामान्य अवस्थामा छ'),
            trailing: FilledButton.tonal(
              onPressed: _changeAccountStatus,
              child: Text(data['accountActive'] == false ? 'पुनः सक्रिय' : 'निष्क्रिय गर्नुहोस्'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _field(_mobile, 'मोबाइल नम्बर', keyboard: TextInputType.phone),
        const SizedBox(height: 10),
        _dateField(_dob, 'जन्म मिति (वि.सं.)'),
        const SizedBox(height: 10),
        _field(_address, 'ठेगाना'),
        const SizedBox(height: 10),
        _field(_occupation, 'पेशा'),
        const SizedBox(height: 10),
        _field(_citizenship, 'नागरिकता नम्बर'),
        const SizedBox(height: 20),
        Row(children: [const Expanded(child: Text('परिवारका सदस्य', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))), TextButton.icon(onPressed: _addFamily, icon: const Icon(Icons.add), label: const Text('थप्नुहोस्'))]),
        ..._family.asMap().entries.map((entry) {
          final index = entry.key; final item = entry.value;
          return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
            Row(children: [Expanded(child: Text('परिवार सदस्य ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold))), IconButton(onPressed: () => setState(() { final removed = _family.removeAt(index); for (final c in removed.values) { c.dispose(); } }), icon: const Icon(Icons.delete_outline, color: Colors.red))]),
            _field(item['name']!, 'नाम'), const SizedBox(height: 8), _field(item['relation']!, 'नाता'), const SizedBox(height: 8), _dateField(item['dateOfBirth']!, 'जन्म मिति (वि.सं.)'),
          ])));
        }),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save), label: Text(_saving ? 'सुरक्षित हुँदैछ...' : 'परिवर्तन सुरक्षित गर्नुहोस्')),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label, {TextInputType? keyboard}) => TextField(controller: c, keyboardType: keyboard, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()));
  Widget _dateField(TextEditingController c, String label) => InkWell(onTap: () => _pickDate(c), child: InputDecorator(decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.calendar_month)), child: Text(c.text.isEmpty ? 'पात्रोबाट मिति छान्नुहोस्' : toNepaliDigits(c.text))));
}
