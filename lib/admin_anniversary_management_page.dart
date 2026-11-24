import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAnniversaryManagementPage extends StatefulWidget {
  const AdminAnniversaryManagementPage({super.key});

  @override
  State<AdminAnniversaryManagementPage> createState() =>
      _AdminAnniversaryManagementPageState();
}

class _AdminAnniversaryManagementPageState
    extends State<AdminAnniversaryManagementPage> {
  final CollectionReference<Map<String, dynamic>> _events =
      FirebaseFirestore.instance.collection('dashboard_anniversaries');

  final CollectionReference<Map<String, dynamic>> _privateMembers =
      FirebaseFirestore.instance.collection('member_private_details');

  final ImagePicker _imagePicker = ImagePicker();

  Future<String?> _pickAndUploadMemberPhoto(
    String personDocId, {
    bool isCoreMember = false,
    String? memberUid,
    String? memberName,
  }) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return null;

    final extension = picked.name.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => throw Exception('JPG, PNG वा WebP फोटो मात्र छान्नुहोस्।'),
    };
    final normalizedExtension = extension == 'jpeg' ? 'jpg' : extension;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw Exception('फोटो 5 MB भन्दा सानो हुनुपर्छ।');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('पहिले Login गर्नुहोस्।');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Firebase Login Token प्राप्त भएन।');
    }

    final path = 'family-members/$personDocId.$normalizedExtension';
    final response = await Supabase.instance.client.functions.invoke(
      'family-photo-access-',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'action': 'upload',
        'path': path,
        'imageBase64': base64Encode(bytes),
        'contentType': contentType,
      },
    );

    final responseData = response.data;
    if (response.status < 200 || response.status >= 300 ||
        responseData is! Map || responseData['success'] != true) {
      throw Exception('फोटो अपलोड भएन: $responseData');
    }

    await _privateMembers.doc(personDocId).set({
      'photoPath': path,
      'photoUpdatedAt': FieldValue.serverTimestamp(),
      if (isCoreMember) 'personType': 'core_member',
      if (isCoreMember) 'isActive': true,
      if (isCoreMember && memberUid != null) 'memberUid': memberUid,
      if (isCoreMember && memberName != null) 'name': memberName,
    }, SetOptions(merge: true));
    return path;
  }

  String _memberUid(Map<String, dynamic> data, String documentId) {
    final value = data['memberUid']?.toString().trim() ?? '';
    return value.isNotEmpty ? value : documentId;
  }

  int _intValue(dynamic value, [int fallback = 0]) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadCoreMembers() async {
    final snapshot = await _privateMembers
        .where('personType', isEqualTo: 'core_member')
        .where('isActive', isEqualTo: true)
        .get();

    // यदि निजी विवरणमा मूल सदस्यको छुट्टै रेकर्ड छैन भने मुख्य member
    // collection का सबै ६ सदस्यलाई जन्मदिनका लागि उपलब्ध गराउने।
    final docs = snapshot.docs.isNotEmpty
        ? snapshot.docs.toList()
        : (await FirebaseFirestore.instance.collection('member').get()).docs.toList();
    docs.sort((a, b) => (a.data()['name'] ?? '')
        .toString()
        .compareTo((b.data()['name'] ?? '').toString()));
    return docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadDeceasedMembers() async {
    final snapshot = await _privateMembers
        .where('isDeceased', isEqualTo: true)
        .get();
    final docs = snapshot.docs.toList();
    docs.sort((a, b) {
      final serialCompare = _intValue(a.data()['serialNumber'])
          .compareTo(_intValue(b.data()['serialNumber']));
      if (serialCompare != 0) return serialCompare;
      return (a.data()['name'] ?? '')
          .toString()
          .compareTo((b.data()['name'] ?? '').toString());
    });
    return docs;
  }

  // Fetch all private records and filter locally. This avoids depending on a
  // Firestore composite index and supports records whose memberUid is absent.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadFamilyMembers(String coreMemberUid) async {
    final snapshot = await _privateMembers.get();
    final docs = snapshot.docs.where((doc) {
      final data = doc.data();
      if (data['isActive'] != true) return false;
      if (data['personType'] == 'core_member') return false;

      final related = data['relatedMemberUids'];
      if (related is! List) return false;
      return related.map((item) => item.toString()).contains(coreMemberUid);
    }).toList();

    docs.sort((a, b) {
      final serialCompare = _intValue(a.data()['serialNumber'])
          .compareTo(_intValue(b.data()['serialNumber']));
      if (serialCompare != 0) return serialCompare;
      return (a.data()['name'] ?? '')
          .toString()
          .compareTo((b.data()['name'] ?? '').toString());
    });
    return docs;
  }

  Future<void> _showEventDialog({
    DocumentSnapshot<Map<String, dynamic>>? document,
  }) async {
    final data = document?.data();
    final formKey = GlobalKey<FormState>();

    List<QueryDocumentSnapshot<Map<String, dynamic>>> coreMemberDocs = [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> familyMemberDocs = [];
    bool loadingFamily = false;

    String? selectedCoreMemberUid =
        data?['selectedCoreMemberUid']?.toString();
    String? relatedMemberUid = data?['relatedMemberUid']?.toString();
    String? deceasedMemberDocId = data?['deceasedMemberDocId']?.toString();
    List<QueryDocumentSnapshot<Map<String, dynamic>>> deceasedMemberDocs = [];
    String? selectedPersonDocId;
    String? photoPath = data?['photoPath']?.toString();
    bool uploadingPhoto = false;
    bool savingEvent = false;

    final nameController = TextEditingController(
      text: data?['relatedMemberName']?.toString() ??
          data?['displayName']?.toString() ??
          '',
    );
    final relationshipController = TextEditingController(
      text: data?['relationship']?.toString() ?? '',
    );
    final photoController = TextEditingController(
      text: data?['photoUrl']?.toString() ?? '',
    );
    final messageController = TextEditingController(
      text: data?['message']?.toString() ?? '',
    );

    int month = _intValue(data?['bsMonth'], 1).clamp(1, 12).toInt();
    int day = _intValue(data?['bsDay'], 1).clamp(1, 32).toInt();
    String type = data?['type']?.toString() ?? 'birthday';
    String birthdayPersonType = data?['birthdayPersonType']?.toString() ?? 'family';
    bool isActive = data?['isActive'] != false;

    try {
      coreMemberDocs = await _loadCoreMembers();
      deceasedMemberDocs = await _loadDeceasedMembers();
      if (type == 'memorial') {
        // पुरानो रेकर्डमा deceasedMemberDocId नभए नामबाट मिलाउने।
        if (deceasedMemberDocId == null || deceasedMemberDocId!.isEmpty) {
          final oldName = (data?['displayName'] ?? '').toString().trim();
          for (final person in deceasedMemberDocs) {
            if ((person.data()['name'] ?? '').toString().trim() == oldName &&
                oldName.isNotEmpty) {
              deceasedMemberDocId = person.id;
              break;
            }
          }
        }
        if (!deceasedMemberDocs.any((person) => person.id == deceasedMemberDocId)) {
          deceasedMemberDocId = null;
        }
      }
      if (selectedCoreMemberUid != null &&
          selectedCoreMemberUid!.isNotEmpty) {
        if (birthdayPersonType == 'self') {
          final core = coreMemberDocs.where((doc) =>
              (doc.data()['memberUid']?.toString() ?? doc.id) == selectedCoreMemberUid).toList();
          if (core.isNotEmpty) {
            final coreData = core.first.data();
            relatedMemberUid = selectedCoreMemberUid;
            selectedPersonDocId = core.first.id;
            nameController.text = coreData['name']?.toString() ?? '';
            photoPath = coreData['photoPath']?.toString();
            relationshipController.text = 'मूल सदस्य';
            final dob = (coreData['dateOfBirth'] ?? '').toString().split('-');
            month = _intValue(coreData['dobBsMonth'], dob.length > 1 ? int.tryParse(dob[1]) ?? month : month).clamp(1, 12).toInt();
            day = _intValue(coreData['dobBsDay'], dob.length > 2 ? int.tryParse(dob[2]) ?? day : day).clamp(1, 32).toInt();
          }
        } else {
          familyMemberDocs = await _loadFamilyMembers(selectedCoreMemberUid!);
        if (relatedMemberUid != null) {
          for (final person in familyMemberDocs) {
            if (_memberUid(person.data(), person.id) == relatedMemberUid) {
              selectedPersonDocId = person.id;
              photoPath ??= person.data()['photoPath']?.toString();
              break;
            }
          }
        }
        }
      }
      if (type == 'memorial' && deceasedMemberDocId != null) {
        selectedPersonDocId = deceasedMemberDocId;
        for (final person in deceasedMemberDocs) {
          if (person.id == deceasedMemberDocId) {
            photoPath ??= person.data()['photoPath']?.toString();
            break;
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('सदस्य विवरण लोड गर्न समस्या भयो: $e')),
        );
      }
      nameController.dispose();
      relationshipController.dispose();
      photoController.dispose();
      messageController.dispose();
      return;
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final coreIds = coreMemberDocs
              .map((doc) => doc.data()['memberUid']?.toString() ?? doc.id)
              .where((uid) => uid.isNotEmpty)
              .toSet();
          final validCoreUid = coreIds.contains(selectedCoreMemberUid)
              ? selectedCoreMemberUid
              : null;

          final familyIds = familyMemberDocs
              .map((doc) => _memberUid(doc.data(), doc.id))
              .toSet();
          final validFamilyUid = familyIds.contains(relatedMemberUid)
              ? relatedMemberUid
              : null;

          return AlertDialog(
            title: Text(document == null
                ? 'नयाँ विवरण थप्नुहोस्'
                : 'विवरण सच्याउनुहोस्'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: type,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'विवरणको प्रकार',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'birthday',
                            child: Text('जन्मदिन'),
                          ),
                          DropdownMenuItem(
                            value: 'memorial',
                            child: Text('श्रद्धाञ्जली'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => type = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      if (type == 'birthday') ...[
                        DropdownButtonFormField<String>(
                          value: birthdayPersonType,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'जन्मदिन कसको लागि हो?'),
                          items: const [
                            DropdownMenuItem(value: 'self', child: Text('स्वयं सदस्य')),
                            DropdownMenuItem(value: 'family', child: Text('सदस्यको परिवार')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() {
                              birthdayPersonType = value;
                              relatedMemberUid = null;
                              selectedPersonDocId = null;
                              photoPath = null;
                              familyMemberDocs = [];
                              nameController.clear();
                              relationshipController.clear();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: validCoreUid,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'मूल सदस्य छान्नुहोस्',
                          ),
                          items: coreMemberDocs.map((doc) {
                            final memberData = doc.data();
                            final uid =
                                memberData['memberUid']?.toString() ?? doc.id;
                            return DropdownMenuItem<String>(
                              value: uid,
                              child: Text(
                                memberData['name']?.toString() ?? 'नाम छैन',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).where((item) =>
                              item.value != null && item.value!.isNotEmpty)
                              .toList(),
                          validator: (value) => value == null
                              ? 'मूल सदस्य छान्नुहोस्'
                              : null,
                          onChanged: (value) async {
                            if (value == null) return;
                            final selectedCore = coreMemberDocs.firstWhere((doc) =>
                                (doc.data()['memberUid']?.toString() ?? doc.id) == value);
                            final coreData = selectedCore.data();
                            if (birthdayPersonType == 'self') {
                              setDialogState(() {
                                selectedCoreMemberUid = value;
                                relatedMemberUid = value;
                                selectedPersonDocId = selectedCore.id;
                                photoPath = coreData['photoPath']?.toString();
                                nameController.text = coreData['name']?.toString() ?? '';
                                relationshipController.text = 'मूल सदस्य';
                                final dob = (coreData['dateOfBirth'] ?? '').toString().split('-');
                                month = _intValue(coreData['dobBsMonth'], dob.length > 1 ? int.tryParse(dob[1]) ?? month : month).clamp(1, 12).toInt();
                                day = _intValue(coreData['dobBsDay'], dob.length > 2 ? int.tryParse(dob[2]) ?? day : day).clamp(1, 32).toInt();
                                familyMemberDocs = [];
                                loadingFamily = false;
                              });
                              return;
                            }
                            setDialogState(() {
                              selectedCoreMemberUid = value;
                              relatedMemberUid = null;
                              selectedPersonDocId = null;
                              photoPath = null;
                              familyMemberDocs = [];
                              loadingFamily = true;
                              relationshipController.clear();
                              nameController.clear();
                            });
                            try {
                              final family = await _loadFamilyMembers(value);
                              if (!dialogContext.mounted) return;
                              setDialogState(() {
                                familyMemberDocs = family;
                                loadingFamily = false;
                              });
                            } catch (e) {
                              if (!dialogContext.mounted) return;
                              setDialogState(() => loadingFamily = false);
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'परिवारका सदस्य लोड गर्न समस्या भयो: $e',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        if (birthdayPersonType == 'family') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: validFamilyUid,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'परिवारको सदस्य छान्नुहोस्',
                          ),
                          items: familyMemberDocs.map((doc) {
                            final memberData = doc.data();
                            final uid = _memberUid(memberData, doc.id);
                            final name =
                                memberData['name']?.toString() ?? 'नाम छैन';
                            return DropdownMenuItem<String>(
                              value: uid,
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          validator: (value) => value == null
                              ? 'परिवारको सदस्य छान्नुहोस्'
                              : null,
                          onChanged: loadingFamily || familyMemberDocs.isEmpty
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  final selectedDoc = familyMemberDocs
                                      .firstWhere((doc) =>
                                          _memberUid(doc.data(), doc.id) ==
                                          value);
                                  final memberData = selectedDoc.data();
                                  setDialogState(() {
                                    relatedMemberUid = value;
                                    selectedPersonDocId = selectedDoc.id;
                                    photoPath = memberData['photoPath']?.toString();
                                    nameController.text =
                                        memberData['name']?.toString() ?? '';
                                    relationshipController.text =
                                        memberData['relationship']?.toString() ??
                                            '';
                                    month = _intValue(
                                      memberData['dobBsMonth'],
                                      month,
                                    ).clamp(1, 12).toInt();
                                    day = _intValue(
                                      memberData['dobBsDay'],
                                      day,
                                    ).clamp(1, 32).toInt();
                                  });
                                },
                        ),
                        if (loadingFamily)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(),
                          )
                        else if (selectedCoreMemberUid != null &&
                            familyMemberDocs.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'यस मूल सदस्यसँग सम्बन्धित सक्रिय परिवार सदस्य भेटिएन।',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: relationshipController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'नाता',
                          ),
                        ),
                        const SizedBox(height: 8),
                        ],
                      ],
                      if (type == 'memorial') ...[
                        if (deceasedMemberDocs.isNotEmpty)
                          DropdownButtonFormField<String>(
                            value: deceasedMemberDocId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'दिवंगत व्यक्ति छान्नुहोस्',
                            ),
                            items: deceasedMemberDocs.map((person) {
                              final personName =
                                  person.data()['name']?.toString().trim() ?? '';
                              return DropdownMenuItem<String>(
                                value: person.id,
                                child: Text(personName.isEmpty
                                    ? 'नाम उपलब्ध छैन'
                                    : personName,
                                    overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            validator: (value) => deceasedMemberDocs.isNotEmpty &&
                                    value == null
                                ? 'दिवंगत व्यक्ति छान्नुहोस्'
                                : null,
                            onChanged: (value) {
                              if (value == null) return;
                              final selectedPerson = deceasedMemberDocs
                                  .firstWhere((person) => person.id == value);
                              setDialogState(() {
                                deceasedMemberDocId = value;
                                selectedPersonDocId = value;
                                photoPath = selectedPerson.data()['photoPath']?.toString();
                                nameController.text =
                                    selectedPerson.data()['name']?.toString() ?? '';
                              });
                            },
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              'member_private_details मा isDeceased = true भएको व्यक्ति भेटिएन। नाम तल हातैले लेख्न सक्नुहुन्छ।',
                              style: TextStyle(color: Colors.orange),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: nameController,
                        readOnly: (type == 'memorial' && deceasedMemberDocId != null) ||
                            (type == 'birthday' && birthdayPersonType == 'self'),
                        decoration: InputDecoration(
                          labelText: type == 'memorial'
                              ? 'दिवंगत व्यक्तिको नाम'
                              : 'नाम',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'नाम लेख्नुहोस्'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: month,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'वि.सं. महिना',
                              ),
                              items: List.generate(
                                12,
                                (index) => DropdownMenuItem<int>(
                                  value: index + 1,
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() => month = value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: day,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'वि.सं. गते',
                              ),
                              items: List.generate(
                                32,
                                (index) => DropdownMenuItem<int>(
                                  value: index + 1,
                                  child: Text('${index + 1}'),
                                ),
                              ),
                              onChanged: (value) {
                                if (value != null) {
                                  setDialogState(() => day = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: photoController,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'फोटो URL',
                          hintText: 'https://...',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: uploadingPhoto || selectedPersonDocId == null
                              ? null
                              : () async {
                                  setDialogState(() => uploadingPhoto = true);
                                  try {
                                    final uploadedPath =
                                        await _pickAndUploadMemberPhoto(
                                      selectedPersonDocId!,
                                      isCoreMember: type == 'birthday' && birthdayPersonType == 'self',
                                      memberUid: relatedMemberUid,
                                      memberName: nameController.text.trim(),
                                    );
                                    if (uploadedPath != null &&
                                        dialogContext.mounted) {
                                      setDialogState(() {
                                        photoPath = uploadedPath;
                                        photoController.clear();
                                      });
                                      ScaffoldMessenger.of(dialogContext)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text('फोटो Private Storage मा सुरक्षित भयो।'),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (dialogContext.mounted) {
                                      ScaffoldMessenger.of(dialogContext)
                                          .showSnackBar(
                                        SnackBar(content: Text('फोटो अपलोड समस्या: $e')),
                                      );
                                    }
                                  } finally {
                                    if (dialogContext.mounted) {
                                      setDialogState(() => uploadingPhoto = false);
                                    }
                                  }
                                },
                          icon: uploadingPhoto
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.photo_library_outlined),
                          label: Text(uploadingPhoto ? 'अपलोड हुँदैछ...' : 'Gallery बाट फोटो छान्नुहोस्'),
                        ),
                      ),
                      if (photoPath != null && photoPath!.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Private फोटो सुरक्षित छ',
                            style: TextStyle(color: Colors.green.shade700),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (type == 'memorial')
  TextFormField(
    controller: messageController,
    decoration: const InputDecoration(
      labelText: 'श्रद्धाञ्जली सन्देश',
    ),
    maxLines: 3,
  ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('सक्रिय राख्ने'),
                        value: isActive,
                        onChanged: (value) {
                          setDialogState(() => isActive = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('रद्द गर्नुहोस्'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF173B66),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (uploadingPhoto || savingEvent) ? null : () async {
                  if (savingEvent || uploadingPhoto) return;
                  if (!formKey.currentState!.validate()) return;
                  setDialogState(() => savingEvent = true);

                    final selectedCoreDocs = coreMemberDocs.where((doc) =>
    (doc.data()['memberUid']?.toString() ?? doc.id) ==
    (selectedCoreMemberUid ?? '')).toList();

final selectedCoreMemberName = selectedCoreDocs.isNotEmpty
    ? (selectedCoreDocs.first.data()['name'] ?? '').toString()
    : '';
                  final eventData = <String, dynamic>{
                    'type': type,
                    'birthdayPersonType': type == 'birthday' ? birthdayPersonType : null,
                    'displayName': nameController.text.trim(),
                    'relatedMemberName': type == 'birthday' && birthdayPersonType == 'family'
                        ? nameController.text.trim()
                        : '',
                    'relationship': type == 'birthday' && birthdayPersonType == 'family'
                        ? relationshipController.text.trim()
                        : '',
                    'relatedMemberUid':
                        type == 'birthday' ? relatedMemberUid : null,
                    'deceasedMemberDocId':
                        type == 'memorial' ? deceasedMemberDocId : null,
                    'selectedCoreMemberUid':
                        type == 'birthday' ? selectedCoreMemberUid : null,
                      'selectedCoreMemberName':
    type == 'birthday' ? selectedCoreMemberName : null,
                    'bsMonth': month,
                    'bsDay': day,
                    'photoUrl': photoController.text.trim(),
                    'photoPath': photoPath,
                    'message': messageController.text.trim(),
                    'isActive': isActive,
                    'updatedAt': FieldValue.serverTimestamp(),
                  };

                  try {
                    if (document == null) {
                      eventData['createdAt'] = FieldValue.serverTimestamp();
                      await _events.add(eventData);
                    } else {
                      await _events.doc(document.id).update(eventData);
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('विवरण सफलतापूर्वक सेभ भयो।')),
                      );
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('सेभ गर्न समस्या भयो: $e')),
                      );
                    }
                  } finally {
                    if (dialogContext.mounted) {
                      setDialogState(() => savingEvent = false);
                    }
                  }
                },
                icon: savingEvent
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: Text(savingEvent ? 'सुरक्षित हुँदैछ...' : 'सेभ गर्नुहोस्'),
              ),
            ],
          );
        },
      ),
    );

    nameController.dispose();
    relationshipController.dispose();
    photoController.dispose();
    messageController.dispose();
  }

  Future<void> _deleteEvent(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('विवरण हटाउने?'),
        content: const Text('यो विवरण हटाउन चाहनुहुन्छ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('रद्द'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('हटाउनुहोस्'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _events.doc(id).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('विवरण हटाइयो।')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('हटाउन समस्या भयो: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('जन्मदिन तथा श्रद्धाञ्जली व्यवस्थापन'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEventDialog(),
        icon: const Icon(Icons.add),
        label: const Text('नयाँ विवरण'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _events.orderBy('bsMonth').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('समस्या भयो: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('अहिलेसम्म कुनै विवरण थपिएको छैन।'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 90, top: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final event = doc.data();
              final isMemorial = event['type'] == 'memorial';
              final name = event['displayName']?.toString() ?? '';
              final monthValue = event['bsMonth'] ?? '-';
              final dayValue = event['bsDay'] ?? '-';
              final active = event['isActive'] == true;

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: ListTile(
                  leading: Icon(
                    isMemorial ? Icons.local_florist : Icons.cake,
                    color: isMemorial ? Colors.blueGrey : Colors.purple,
                    size: 30,
                  ),
                  title: Text(name),
                  subtitle: Text(
                    '${isMemorial ? 'श्रद्धाञ्जली' : 'जन्मदिन'} • '
                    'वि.सं. $monthValue/$dayValue • '
                    '${active ? 'सक्रिय' : 'निष्क्रिय'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEventDialog(document: doc);
                      } else if (value == 'delete') {
                        _deleteEvent(doc.id);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('सच्याउनुहोस्'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('हटाउनुहोस्'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
