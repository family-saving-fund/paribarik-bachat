
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardAnniversaryBanner extends StatefulWidget {
  final String memberName;

  const DashboardAnniversaryBanner({
    super.key,
    required this.memberName,
  });

  @override
  State<DashboardAnniversaryBanner> createState() =>
      _DashboardAnniversaryBannerState();
}

class _DashboardAnniversaryBannerState
    extends State<DashboardAnniversaryBanner> {
  late DateTime _nepalNow;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _updateNepalTime();

    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(_updateNepalTime);
      }
    });
  }

  void _updateNepalTime() {
    _nepalNow = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 45),
    );
  }
Future<String?> _getSignedPhotoUrl(String photoPath) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) return null;

    final response = await Supabase.instance.client.functions.invoke(
      'family-photo-access-',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'action': 'signed-url',
        'path': photoPath,
      },
    );

    final data = response.data;
    if (response.status >= 200 &&
        response.status < 300 &&
        data is Map &&
        data['success'] == true) {
      return data['signedUrl']?.toString();
    }
  } catch (e) {
    debugPrint('फोटो URL प्राप्त गर्न समस्या: $e');
  }

  return null;
}
    
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bsDate = NepaliDateTime.fromDateTime(
      DateTime(
        _nepalNow.year,
        _nepalNow.month,
        _nepalNow.day,
        12,
      ),
    );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('dashboard_anniversaries')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final events = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data();
          return data['bsMonth'] == bsDate.month &&
              data['bsDay'] == bsDate.day;
        }).toList();

        if (events.isEmpty) {
          return _welcomeBanner();
        }

        return Column(
          children: events.map((doc) {
            final data = doc.data();
            final isMemorial = data['type'] == 'memorial';
            final name = (data['displayName'] ?? '').toString();
            final message = isMemorial
    ? (data['message'] ?? '').toString()
    : 'पारिवारिक बचत कोष परिवारको तर्फबाट तपाईंलाई जन्मदिनको हार्दिक मंगलमय शुभकामना। तपाईंको जीवन सुस्वास्थ्य, दीर्घायु, सुख, शान्ति, समृद्धि र सफलताले भरिपूर्ण रहोस्।';
            final photoPath = (data['photoPath'] ?? '').toString();
final oldPhotoUrl = (data['photoUrl'] ?? '').toString();
               
final relatedMemberName =
    (data['relatedMemberName'] ?? '').toString();
final relationship =
    (data['relationship'] ?? '').toString();
              final selectedCoreMemberName =
    (data['selectedCoreMemberName'] ?? '').toString();
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isMemorial
                      ? const [
                          Color(0xFF263238),
                          Color(0xFF455A64),
                        ]
                      : const [
                          Color(0xFF102A43),
                          Color(0xFF167D66),
                        ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isMemorial
                      ? const Color(0xFFB0BEC5)
                      : const Color(0xFFE8C56A),
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    isMemorial
                        ? 'हार्दिक श्रद्धाञ्जली'
                        : '🎂 जन्मदिनको हार्दिक शुभकामना 🎉',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  FutureBuilder<String?>(
  future: photoPath.isNotEmpty
      ? _getSignedPhotoUrl(photoPath)
      : Future<String?>.value(oldPhotoUrl),
  builder: (context, photoSnapshot) {
    final url = photoSnapshot.data ?? '';

    if (url.isEmpty) {
      return const SizedBox.shrink();
    }

    
return Padding(
  padding: const EdgeInsets.only(top: 12),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
        const Text(
  '🎉',
  style: TextStyle(fontSize: 48),
),
      const SizedBox(width: 12),
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.amber,
            width: 3,
          ),
        ),
        child: ClipOval(
          child: Image.network(
            url,
            width: 109,
            height: 109,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.person,
              color: Colors.white,
              size: 70,
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
        const Text(
  '🎉',
  style: TextStyle(fontSize: 48),
),
    ],
  ),
);
  },
),

 const SizedBox(height: 10),
  Text(
  name,
  textAlign: TextAlign.center,
  style: const TextStyle(
  color: Colors.white,
  fontSize: 20,
  fontWeight: FontWeight.bold,
                    ),
                  ),
                     if (!isMemorial &&
    relatedMemberName.isNotEmpty &&
    relationship.isNotEmpty &&
    selectedCoreMemberName.isNotEmpty)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      '${selectedCoreMemberName}${(relationship.trim() == 'श्रीमती' || relationship.trim() == 'छोरी') ? 'की' : 'का'} $relationship $relatedMemberName',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _welcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF102A43),
            Color(0xFF185078),
            Color(0xFF167D66),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE8C56A),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'नमस्कार 🙏',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            widget.memberName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'पारिवारिक बचत कोषमा स्वागत छ।',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
