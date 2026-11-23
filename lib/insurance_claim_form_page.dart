import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'dart:typed_data';
import 'insurance_annual_limit_service.dart';
import 'member_account_guard.dart';
import 'nepali_digits.dart';

class InsuranceClaimFormPage extends StatefulWidget {
  final String uid;
  final String memberName;

  const InsuranceClaimFormPage({
    super.key,
    required this.uid,
    required this.memberName,
  });

  @override
  State<InsuranceClaimFormPage> createState() =>
      _InsuranceClaimFormPageState();
}

class _InsuranceClaimFormPageState
    extends State<InsuranceClaimFormPage> {
    final _formKey = GlobalKey<FormState>();
    bool _isSubmitting = false;
  final NepaliDateTime _applicationDate = NepaliDateTime.now();
  final _amountController = TextEditingController();
    double? _calculatedInsuranceAmount;
    String? _claimFor;
String? _selectedFamilyMember;
  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedPhotos = [];
  final _reasonController = TextEditingController();
  final _detailsController = TextEditingController();

    void _calculateInsuranceAmount() {
  final expense = double.tryParse(_amountController.text.trim());

  if (expense == null || expense <= 5000) {
    setState(() {
      _calculatedInsuranceAmount = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'रु. ५,००० भन्दा बढी खर्च भए मात्र बीमा सुविधा उपलब्ध हुन्छ।',
        ),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  setState(() {
    _calculatedInsuranceAmount = expense * 0.20;
  });
}
    Future<void> _pickClaimPhoto() async {
  final List<XFile> photos = await _picker.pickMultiImage(
    imageQuality: 80,
  );

  if (photos.isNotEmpty && mounted) {
    setState(() {
      _selectedPhotos = [..._selectedPhotos, ...photos];
    });
  }
}
    
    Future<List<String>> _uploadClaimPhotos() async {
  final List<String> photoUrls = [];

  for (final photo in _selectedPhotos) {
    final bytes = await photo.readAsBytes();

    final filePath =
        'insurance_claims/${widget.uid}/${DateTime.now().millisecondsSinceEpoch}_${photo.name}';

    await Supabase.instance.client.storage
        .from('expense_vouchers')
        .uploadBinary(
          filePath,
          bytes,
          fileOptions: FileOptions(
            contentType: photo.mimeType ?? 'image/jpeg',
            upsert: false,
          ),
        )
        .timeout(const Duration(seconds: 30));

    final downloadUrl = Supabase.instance.client.storage
        .from('expense_vouchers')
        .getPublicUrl(filePath);

    photoUrls.add(downloadUrl);
  }

  return photoUrls;
}
    
    Future<void> _submitClaim() async {
  if (_isSubmitting) return;

  if (_claimFor == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('कृपया सदस्य वा परिवारको विकल्प छान्नुहोस्।'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  if (_claimFor == 'family' && _selectedFamilyMember == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('कृपया परिवारको सदस्य छान्नुहोस्।'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

if (_calculatedInsuranceAmount == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('कृपया पहिले बीमा रकम गणना गर्नुहोस्।'),
      backgroundColor: Colors.red,
    ),
  );
  return;
}
        
  if (_selectedPhotos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('कृपया बीमा दाबीको प्रमाण फोटो छान्नुहोस्।'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  if (!_formKey.currentState!.validate()) return;
        
  setState(() {
    _isSubmitting = true;
  });

  String? errorMessage;
String currentStep = 'फोटो अपलोड';

  try {
    await MemberAccountGuard.ensureActive(widget.uid);
    currentStep = 'Supabase फोटो अपलोड';
final photoUrls = await _uploadClaimPhotos();

currentStep = 'Firestore मा विवरण सुरक्षित';

    final applicationDateBS =
        NepaliDateFormat('yyyy-MM-dd').format(_applicationDate);
    final annualService = InsuranceAnnualLimitService();
    final fiscalYear = annualService.fiscalYearStart(applicationDateBS);
    if (fiscalYear == null) {
      throw StateError('BS आर्थिक वर्षको मिति सही छैन।');
    }
    final annualRef = annualService.ref(widget.uid, fiscalYear);
    final legacyReserved =
        await annualService.getSeedReserved(widget.uid, fiscalYear);
    final claimRef = FirebaseFirestore.instance
        .collection('insurance_claims').doc();
    final requestedInsurance = _calculatedInsuranceAmount!;

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final annualSnapshot = await transaction.get(annualRef);
      final alreadyReserved = annualSnapshot.exists
          ? ((annualSnapshot.data()?['reservedAmount'] as num?)?.toDouble() ?? 0)
          : legacyReserved;
      if (alreadyReserved + requestedInsurance >
          InsuranceAnnualLimitService.annualLimit + 0.001) {
        throw StateError(
          'यस सदस्य र परिवारको यस BS आर्थिक वर्षको रु. १,००,००० सीमा पुग्छ। '
          'हाल सुरक्षित दाबी रु. ${alreadyReserved.toStringAsFixed(2)} छ।',
        );
      }

      transaction.set(annualRef, {
        'uid': widget.uid,
        'fiscalYearStart': fiscalYear,
        'reservedAmount': alreadyReserved + requestedInsurance,
        'limitAmount': InsuranceAnnualLimitService.annualLimit,
        'revision': ((annualSnapshot.data()?['revision'] as num?)?.toInt() ?? 0) + 1,
        'lastAction': 'reserve',
        'lastClaimId': claimRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(claimRef, {
        'uid': widget.uid,
        'memberName': widget.memberName,
        'claimFor': _claimFor,
        'claimantName': _claimFor == 'family'
            ? _selectedFamilyMember
            : widget.memberName,
        'applicationDateBS': applicationDateBS,
        'fiscalYearStart': fiscalYear,
        'expenseAmount': double.tryParse(_amountController.text) ?? 0,
        'insuranceAmount': requestedInsurance,
        'claimAmount': requestedInsurance,
        'reason': _reasonController.text.trim(),
        'details': _detailsController.text.trim(),
        'photoUrls': photoUrls,
        'status': 'pending',
        'paymentStatus': 'unpaid',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  } catch (e) {
    errorMessage = '$currentStep चरणमा असफल भयो: $e';
  } finally {
    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  if (!mounted) return;

  if (errorMessage != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('बीमा दाबी आवेदन सफलतापूर्वक पेश भयो।'),
      backgroundColor: Colors.green,
    ),
  );

  Navigator.pop(context);
}
    @override
void dispose() {
  _amountController.dispose();
  _reasonController.dispose();
  _detailsController.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('बीमा दाबी आवेदन'),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('सदस्यको नाम: ${widget.memberName}'),
          const SizedBox(height: 16),

          const Text(
            'दाबी कसका लागि हो?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          RadioListTile<String>(
            title: const Text('सदस्य स्वयंको लागि'),
            value: 'self',
            groupValue: _claimFor,
            onChanged: (value) {
              setState(() {
                _claimFor = value;
                _selectedFamilyMember = null;
              });
            },
          ),

          RadioListTile<String>(
            title: const Text('सदस्यको परिवारको लागि'),
            value: 'family',
            groupValue: _claimFor,
            onChanged: (value) {
              setState(() {
                _claimFor = value;
                _selectedFamilyMember = null;
              });
            },
          ),

          if (_claimFor == 'family')
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('member')
                  .doc(widget.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final familyMembers =
                    (snapshot.data?.data()?['familyMembers']
                            as List<dynamic>?) ??
                        [];

                final names = familyMembers
                    .map((item) =>
                        (item as Map)['name']?.toString() ?? '')
                    .where((name) => name.trim().isNotEmpty)
                    .toList();

                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  );
                }

                if (names.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Profile मा परिवार सदस्य थपिएको छैन।',
                    ),
                  );
                }

                return DropdownButtonFormField<String>(
                  value: names.contains(_selectedFamilyMember)
                      ? _selectedFamilyMember
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'परिवारको सदस्य छान्नुहोस्',
                    border: OutlineInputBorder(),
                  ),
                  items: names.map((name) {
                    return DropdownMenuItem<String>(
                      value: name,
                      child: Text(name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedFamilyMember = value;
                    });
                  },
                );
              },
            ),

          const SizedBox(height: 16),

          if (_claimFor == 'self' ||
              (_claimFor == 'family' &&
                  _selectedFamilyMember != null)) ...[
            const SizedBox(height: 12),

            TextFormField(
              initialValue:
                  toNepaliDigits(NepaliDateFormat('yyyy-MM-dd').format(_applicationDate)),
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'आवेदन मिति (BS)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_month),
              ),
            ),

            const SizedBox(height: 16),

            TextFormField(
  controller: _amountController,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  decoration: const InputDecoration(
    labelText: 'कुल उपचार खर्च (रु.)',
    border: OutlineInputBorder(),
  ),
                
  onChanged: (value) {
  setState(() {
    _calculatedInsuranceAmount = null;
  });
},
                
  validator: (value) {
    final amount = double.tryParse(value ?? '');
    if (amount == null || amount <= 0) {
      return 'कृपया कुल उपचार खर्च सही राख्नुहोस्।';
    }
    return null;
  },
),

const SizedBox(height: 8),

ElevatedButton(
  onPressed: _calculateInsuranceAmount,
  child: const Text('बीमा रकम गणना गर्नुहोस्'),
),

if (_calculatedInsuranceAmount != null) ...[
  const SizedBox(height: 12),
  TextFormField(
    initialValue: _calculatedInsuranceAmount!.toStringAsFixed(2),
    readOnly: true,
    decoration: const InputDecoration(
      labelText: 'भुक्तानी योग्य बीमा (२०%)',
      border: OutlineInputBorder(),
    ),
  ),
],

const SizedBox(height: 16),
            const Text(
              'बीमा दाबीको प्रमाण फोटो (अनिवार्य)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            if (_selectedPhotos.isNotEmpty)
  Wrap(
    spacing: 8,
    runSpacing: 8,
    children: _selectedPhotos.map((photo) {
      return FutureBuilder<Uint8List>(
        future: photo.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Stack(
  children: [
    Image.memory(
      snapshot.data!,
      width: 100,
      height: 100,
      fit: BoxFit.cover,
    ),
    Positioned(
      right: 0,
      top: 0,
      child: IconButton(
        onPressed: () {
          setState(() {
            _selectedPhotos.remove(photo);
          });
        },
        icon: const Icon(
          Icons.cancel,
          color: Colors.red,
        ),
      ),
    ),
  ],
);
          }
          return const SizedBox(
            width: 100,
            height: 100,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        },
      );
    }).toList(),
  ),

            OutlinedButton.icon(
              onPressed:
             _isSubmitting ? null : _pickClaimPhoto,
              icon: const Icon(Icons.photo_library),
              label: Text(
                _selectedPhotos.isEmpty
    ? 'फोटो छान्नुहोस्'
    : '${_selectedPhotos.length} वटा फोटो छानिएका छन्',
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed:
              _isSubmitting ? null : _submitClaim,
              child: _isSubmitting
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('पेश हुँदैछ...'),
                      ],
                    )
                  : const Text('दाबी आवेदन पेश गर्नुहोस्'),
            ),
          ],
        ],
      ),
    ),
  );
}
}