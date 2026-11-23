import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'admin_audit_service.dart';
import 'dart:typed_data';
import 'fund_service.dart';
import 'notification_service.dart';

class ExpenseWithdrawalService {
  ExpenseWithdrawalService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AdminAuditService? auditService,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _auditService = auditService ?? AdminAuditService();

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final AdminAuditService _auditService;

  static const String proposalCollection = 'expense_withdrawal_proposals';

  static const Duration votingDuration = Duration(hours: 24);

  static const Duration resubmissionCooldown = Duration(hours: 24);

  CollectionReference<Map<String, dynamic>> get _proposals =>
      _db.collection(proposalCollection);

  CollectionReference<Map<String, dynamic>> get _members =>
      _db.collection('member');

  Future<void> _notifyExpenseMembers({
    required String title,
    required String message,
    required String type,
    required String relatedId,
  }) async {
    try {
      final snapshot = await _members.get();
      final uids = snapshot.docs.map((doc) => doc.id).toList();

      if (uids.isEmpty) return;

      await NotificationService.sendToMembers(
        memberUids: uids,
        title: title,
        message: message,
        type: type,
        relatedId: relatedId,
      );
    } catch (error) {
      print('Expense notification failed: $error');
    }
  }

  static int requiredApprovals(int eligibleVoterCount) {
    if (eligibleVoterCount <= 0) return 0;
    return (eligibleVoterCount * 60 + 99) ~/ 100;
  }

  static double approvalPercentage({
    required int approvals,
    required int eligibleVoterCount,
  }) {
    if (eligibleVoterCount <= 0) return 0;
    return approvals / eligibleVoterCount * 100;
  }

  static bool isAutomaticallyApproved({
    required int approvals,
    required int eligibleVoterCount,
  }) {
    if (eligibleVoterCount <= 0) return false;
    return approvals >= requiredApprovals(eligibleVoterCount);
  }

  static bool canAdminCastTieBreakVote({
    required int approvals,
    required int eligibleVoterCount,
  }) {
    final percentage = approvalPercentage(
      approvals: approvals,
      eligibleVoterCount: eligibleVoterCount,
    );

    return percentage >= 51 && percentage < 60;
  }

  /// Admin ले मात्र नयाँ खर्च प्रस्ताव पेश गर्न पाउनेछ।
  /// सबै Admin मतदानबाट अलग रहनेछन्।
  /// प्रस्ताव पेश नगरेका अन्य Admin मात्र विशेष मतदानका
  /// लागि सम्भावित योग्य Admin हुनेछन्।
  Future<String> submitProposal({
    required String title,
    required String category,
    required double amount,
    required String bsDate,
    required DateTime expenseDate,
    required String description,
    required String voucherUrl,
    required String voucherFileName,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('पहिले Login गर्नुहोस्।');
    }

    if (title.trim().isEmpty ||
        category.trim().isEmpty ||
        bsDate.trim().isEmpty) {
      throw Exception('खर्चको शीर्षक, प्रकार र मिति आवश्यक छन्।');
    }

    if (!amount.isFinite || amount <= 0) {
      throw Exception('खर्च रकम शून्यभन्दा बढी हुनुपर्छ।');
    }

    final availableAmount = await FundService().calculateAvailableSavings();

    final maxExpenseAmount = availableAmount * 0.20;

    if (amount > maxExpenseAmount) {
      throw Exception(
        'उपलब्ध रकमको २०% भन्दा बढी खर्च प्रस्ताव राख्न मिल्दैन। '
        'अधिकतम प्रस्ताव रकम रु. ${maxExpenseAmount.toStringAsFixed(2)} हो।',
      );
    }

    // सबै सदस्यको विवरण प्राप्त गर्ने।
    final membersSnapshot = await _members.get();

    final memberDocs = membersSnapshot.docs;

    final adminDocs = memberDocs.where((doc) {
      return (doc.data()['role'] ?? '').toString().toLowerCase() == 'admin';
    }).toList();

    final submitter = adminDocs.where((doc) {
      return doc.id == user.uid;
    }).toList();

    if (submitter.isEmpty) {
      throw Exception('खर्च प्रस्ताव Admin ले मात्र पेश गर्न सक्नुहुन्छ।');
    }

    final adminData = submitter.first.data();
    final adminName = (adminData['name'] ?? 'प्रशासक').toString();

    // Admin सहित सबै सदस्य नियमित मतदाता हुनेछन्।
    final eligibleMembers = memberDocs;

    if (eligibleMembers.isEmpty) {
      throw Exception('मतदानका लागि योग्य सदस्य भेटिएनन्।');
    }

    final voters = eligibleMembers.map((doc) {
      return {
        'uid': doc.id,
        'name': (doc.data()['name'] ?? '').toString(),
        'vote': 'pending',
        'votedAt': null,
      };
    }).toList();

    // प्रस्ताव पेश नगरेका अन्य Admin हरूको सूची।
    final eligibleAdminTieBreakVoters = adminDocs
        .where((doc) => adminDocs.length == 1 || doc.id != user.uid)
        .map((doc) => {
              'uid': doc.id,
              'name': (doc.data()['name'] ?? '').toString(),
            })
        .toList();

    final proposalRef = _proposals.doc();
    final auditEventId = 'expense_proposal_submitted_${proposalRef.id}';

    final deadline = DateTime.now().add(votingDuration);

    await _db.runTransaction((transaction) async {
      // Transaction का सबै पढाइ लेखाइभन्दा पहिले।
      final adminSnapshot = await transaction.get(_members.doc(user.uid));

      if (!adminSnapshot.exists ||
          (adminSnapshot.data()?['role'] ?? '').toString().toLowerCase() !=
              'admin') {
        throw Exception('Admin अनुमति पुष्टि हुन सकेन।');
      }

      final auditRef = await _auditService.prepareRecordInTransaction(
        transaction: transaction,
        eventId: auditEventId,
      );

      transaction.set(proposalRef, {
        'proposalId': proposalRef.id,
        'title': title.trim(),
        'category': category.trim(),
        'amount': amount,
        'bsDate': bsDate.trim(),
        'expenseDate': Timestamp.fromDate(expenseDate),
        'description': description.trim(),
        'submittedByUid': user.uid,
        'submittedByName': adminName,
        'status': 'voting',
        'votingStatus': 'in_progress',
        'votingRound': 1,
        'eligibleVoterUids': eligibleMembers.map((doc) => doc.id).toList(),
        'eligibleVoterCount': eligibleMembers.length,
        'voters': voters,
        'eligibleAdminTieBreakVoters': eligibleAdminTieBreakVoters,
        'adminTieBreakVote': 'not_available',
        'adminTieBreakVotedByUid': null,
        'adminTieBreakVotedByName': null,
        'adminTieBreakVotedAt': null,
        'yesVotes': 0,
        'noVotes': 0,
        'requiredApprovals': requiredApprovals(eligibleMembers.length),
        'votingStartedAt': FieldValue.serverTimestamp(),
        'votingDeadline': Timestamp.fromDate(deadline),
        'submittedAt': FieldValue.serverTimestamp(),
        'approvedAt': null,
        'rejectedAt': null,
        'disbursedAt': null,
        'disbursedByUid': null,
        'disbursedByName': null,
        'proposalVoucherUrl': voucherUrl,
        'proposalVoucherFileName': voucherFileName,
        'proposalVoucherUploadedByUid': user.uid,
        'proposalVoucherUploadedAt': FieldValue.serverTimestamp(),
        'resubmissionAllowedAt': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _auditService.writePreparedRecordInTransaction(
        transaction: transaction,
        auditRef: auditRef,
        data: {
          'adminUid': user.uid,
          'adminName': adminName,
          'action': 'expense_proposal_submitted',
          'targetCollection': proposalCollection,
          'targetDocumentId': proposalRef.id,
          'description': 'नयाँ खर्च प्रस्ताव मतदानका लागि पेश गरियो।',
          'amount': amount,
          'newValues': {
            'title': title.trim(),
            'category': category.trim(),
            'amount': amount,
            'eligibleVoterCount': eligibleMembers.length,
            'requiredApprovals': requiredApprovals(eligibleMembers.length),
          },
        },
      );
    });

    await _notifyExpenseMembers(
      title: 'नयाँ खर्च प्रस्ताव',
      message:
          '$title — रु. ${amount.toStringAsFixed(2)} को खर्च प्रस्ताव मतदानका लागि पेश भयो।',
      type: 'expense_proposal_submitted',
      relatedId: proposalRef.id,
    );

    return proposalRef.id;
  }

  Future<void> castVote({
    required String proposalId,
    required bool approve,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('पहिले Login गर्नुहोस्।');
    }

    final proposalRef = _proposals.doc(proposalId);
    final voteRef = proposalRef.collection('votes').doc(user.uid);

    await _db.runTransaction((transaction) async {
      final proposalSnapshot = await transaction.get(proposalRef);

      final voteSnapshot = await transaction.get(voteRef);

      if (!proposalSnapshot.exists) {
        throw Exception('खर्च प्रस्ताव भेटिएन।');
      }

      if (voteSnapshot.exists) {
        throw Exception('तपाईंले यसअघि नै मत दिइसक्नुभएको छ।');
      }

      final data = proposalSnapshot.data()!;

      if (data['status'] != 'voting') {
        throw Exception('यो प्रस्तावमा मतदान खुला छैन।');
      }

      final deadline = (data['votingDeadline'] as Timestamp).toDate();

      if (!DateTime.now().isBefore(deadline)) {
        throw Exception('मतदान गर्ने समय समाप्त भयो।');
      }

      final eligibleUids = List<String>.from(data['eligibleVoterUids'] ?? []);

      if (!eligibleUids.contains(user.uid)) {
        throw Exception('तपाईं यो मतदानका लागि योग्य हुनुहुन्न।');
      }

      transaction.set(voteRef, {
        'uid': user.uid,
        'vote': approve ? 'yes' : 'no',
        'votedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> castAdminTieBreakVote({
    required String proposalId,
    required bool approve,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('पहिले Login गर्नुहोस्।');
    }

    final proposalRef = _proposals.doc(proposalId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(proposalRef);

      if (!snapshot.exists) {
        throw Exception('खर्च प्रस्ताव भेटिएन।');
      }

      final data = snapshot.data()!;

      if (data['status'] != 'voting') {
        throw Exception('यो प्रस्तावमा Tie-break Vote खुला छैन।');
      }

      if (data['votingStatus'] != 'admin_tiebreak_pending') {
        throw Exception('पहिले Admin ले सदस्यको मत गणना गर्नुपर्छ।');
      }

      final approvals = (data['yesVotes'] as num? ?? 0).toInt();

      final eligibleCount = (data['eligibleVoterCount'] as num? ?? 0).toInt();

      if (!canAdminCastTieBreakVote(
        approvals: approvals,
        eligibleVoterCount: eligibleCount,
      )) {
        throw Exception(
          'Tie-break Vote का लागि ५१% देखि ५९% स्वीकृति आवश्यक छ।',
        );
      }

      final adminRef = _members.doc(user.uid);
      final adminSnapshot = await transaction.get(adminRef);

      if (!adminSnapshot.exists ||
          (adminSnapshot.data()?['role'] ?? '').toString().toLowerCase() !=
              'admin') {
        throw Exception('यो सुविधा Admin का लागि मात्र हो।');
      }

      final eligibleAdmins = List<Map<String, dynamic>>.from(
        (data['eligibleAdminTieBreakVoters'] as List? ?? []).map(
          (item) => Map<String, dynamic>.from(item),
        ),
      );

      final isEligible = eligibleAdmins.any(
        (admin) => admin['uid'] == user.uid,
      );

      if (!isEligible) {
        throw Exception(
          'तपाईं यो प्रस्तावको Tie-break का लागि योग्य हुनुहुन्न।',
        );
      }

      if (data['adminTieBreakVote'] != 'not_available') {
        throw Exception('Tie-break Vote पहिले नै प्रयोग भइसकेको छ।');
      }

      final adminName = (adminSnapshot.data()?['name'] ?? 'प्रशासक').toString();

      final auditRef = await _auditService.prepareRecordInTransaction(
        transaction: transaction,
        eventId: 'expense_tiebreak_${proposalId}_${user.uid}',
      );

      transaction.update(proposalRef, {
        'adminTieBreakVote': approve ? 'approve' : 'reject',
        'adminTieBreakVotedByUid': user.uid,
        'adminTieBreakVotedByName': adminName,
        'adminTieBreakVotedAt': FieldValue.serverTimestamp(),
        'status': approve ? 'approved' : 'rejected',
        'votingStatus': approve ? 'approved' : 'rejected',
        if (approve) 'approvedAt': FieldValue.serverTimestamp(),
        if (!approve) 'rejectedAt': FieldValue.serverTimestamp(),
        if (!approve)
          'resubmissionAllowedAt': Timestamp.fromDate(
            DateTime.now().add(resubmissionCooldown),
          ),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _auditService.writePreparedRecordInTransaction(
        transaction: transaction,
        auditRef: auditRef,
        data: {
          'adminUid': user.uid,
          'adminName': adminName,
          'action': 'expense_admin_tiebreak_vote',
          'targetCollection': proposalCollection,
          'targetDocumentId': proposalId,
          'description': approve
              ? 'Admin Tie-break Vote बाट खर्च प्रस्ताव स्वीकृत भयो।'
              : 'Admin Tie-break Vote बाट खर्च प्रस्ताव अस्वीकृत भयो।',
          'newValues': {
            'adminTieBreakVote': approve ? 'approve' : 'reject',
            'yesVotes': approvals,
            'eligibleVoterCount': eligibleCount,
          },
        },
      );
    });

    await _notifyExpenseMembers(
      title:
          approve ? 'खर्च प्रस्ताव स्वीकृत भयो' : 'खर्च प्रस्ताव अस्वीकृत भयो',
      message: approve
          ? 'Admin Tie-break मतदानबाट खर्च प्रस्ताव अन्तिम रूपमा स्वीकृत भयो।'
          : 'Admin Tie-break मतदानबाट खर्च प्रस्ताव अन्तिम रूपमा अस्वीकृत भयो।',
      type: 'expense_proposal_decision',
      relatedId: proposalId,
    );
  }

  Future<void> finalizeExpiredVoting({
    required String proposalId,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('पहिले Login गर्नुहोस्।');
    }

    final proposalRef = _proposals.doc(proposalId);

    String? finalDecision;

    await _db.runTransaction((transaction) async {
      final adminSnapshot = await transaction.get(_members.doc(user.uid));

      if (!adminSnapshot.exists ||
          (adminSnapshot.data()?['role'] ?? '').toString().toLowerCase() !=
              'admin') {
        throw Exception('यो काम Admin ले मात्र गर्न सक्नुहुन्छ।');
      }

      final snapshot = await transaction.get(proposalRef);

      if (!snapshot.exists) {
        throw Exception('खर्च प्रस्ताव भेटिएन।');
      }

      final data = snapshot.data()!;

      if (data['status'] != 'voting') {
        throw Exception('यो प्रस्ताव अहिले मतदान अवस्थामा छैन।');
      }

      final deadline = (data['votingDeadline'] as Timestamp).toDate();

      final eligibleUids = List<String>.from(data['eligibleVoterUids'] ?? []);

      if (eligibleUids.isEmpty) {
        throw Exception('मतदानका लागि योग्य सदस्य भेटिएनन्।');
      }

      // सबै योग्य सदस्यको व्यक्तिगत मत पढ्ने
      final voteSnapshots = <DocumentSnapshot>[];

      for (final voterUid in eligibleUids) {
        final voteRef = proposalRef.collection('votes').doc(voterUid);

        final voteSnapshot = await transaction.get(voteRef);
        voteSnapshots.add(voteSnapshot);
      }

      final allVoted = voteSnapshots.every(
        (vote) => vote.exists,
      );

      final deadlinePassed = !DateTime.now().isBefore(deadline);

      if (!allVoted && !deadlinePassed) {
        throw Exception(
          'सबै सदस्यको मतदान पूरा भएको छैन। २४ घण्टा पूरा भएपछि मात्र मत गणना गर्न मिल्छ।',
        );
      }

      final approvals = voteSnapshots.where((vote) {
        return vote.exists &&
            vote.data() is Map &&
            (vote.data() as Map)['vote'] == 'yes';
      }).length;

      final rejections = voteSnapshots.where((vote) {
        return vote.exists &&
            vote.data() is Map &&
            (vote.data() as Map)['vote'] == 'no';
      }).length;

      final eligibleCount = eligibleUids.length;

      final percentage = approvalPercentage(
        approvals: approvals,
        eligibleVoterCount: eligibleCount,
      );

      final adminName = (adminSnapshot.data()?['name'] ?? 'प्रशासक').toString();

      if (approvals >= requiredApprovals(eligibleCount)) {
        finalDecision = 'approved';
        final auditRef = await _auditService.prepareRecordInTransaction(
          transaction: transaction,
          eventId: 'expense_voting_approved_$proposalId',
        );

        transaction.update(proposalRef, {
          'yesVotes': approvals,
          'noVotes': rejections,
          'status': 'approved',
          'votingStatus': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        _auditService.writePreparedRecordInTransaction(
          transaction: transaction,
          auditRef: auditRef,
          data: {
            'adminUid': user.uid,
            'adminName': adminName,
            'action': 'expense_voting_approved',
            'targetCollection': proposalCollection,
            'targetDocumentId': proposalId,
            'description':
                'Admin ले सदस्य मतदान गणना गरी खर्च प्रस्ताव स्वीकृत गर्नुभयो।',
            'newValues': {
              'yesVotes': approvals,
              'noVotes': rejections,
              'eligibleVoterCount': eligibleCount,
              'approvalPercentage': percentage,
            },
          },
        );
      } else if (percentage <= 50) {
        finalDecision = 'rejected';
        final auditRef = await _auditService.prepareRecordInTransaction(
          transaction: transaction,
          eventId: 'expense_voting_rejected_$proposalId',
        );

        transaction.update(proposalRef, {
          'yesVotes': approvals,
          'noVotes': rejections,
          'status': 'rejected',
          'votingStatus': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
          'resubmissionAllowedAt': Timestamp.fromDate(
            DateTime.now().add(resubmissionCooldown),
          ),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        _auditService.writePreparedRecordInTransaction(
          transaction: transaction,
          auditRef: auditRef,
          data: {
            'adminUid': user.uid,
            'adminName': adminName,
            'action': 'expense_voting_rejected',
            'targetCollection': proposalCollection,
            'targetDocumentId': proposalId,
            'description':
                '५०% वा कम स्वीकृति प्राप्त भएकाले खर्च प्रस्ताव अस्वीकृत भयो।',
            'newValues': {
              'yesVotes': approvals,
              'noVotes': rejections,
              'eligibleVoterCount': eligibleCount,
              'approvalPercentage': percentage,
            },
          },
        );
      } else {
        transaction.update(proposalRef, {
          'yesVotes': approvals,
          'noVotes': rejections,
          'votingStatus': 'admin_tiebreak_pending',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    if (finalDecision != null) {
      final approved = finalDecision == 'approved';
      await _notifyExpenseMembers(
        title: approved
            ? 'खर्च प्रस्ताव स्वीकृत भयो'
            : 'खर्च प्रस्ताव अस्वीकृत भयो',
        message: approved
            ? 'सदस्य मतदान गणनाबाट खर्च प्रस्ताव स्वीकृत भयो।'
            : 'सदस्य मतदान गणनाबाट खर्च प्रस्ताव अस्वीकृत भयो।',
        type: 'expense_proposal_decision',
        relatedId: proposalId,
      );
    }
  }

  Future<void> resubmitProposal({
    required String proposalId,
    required String title,
    required String category,
    required double amount,
    required String bsDate,
    required DateTime expenseDate,
    required String description,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('पहिले Login गर्नुहोस्।');
    }

    if (title.trim().isEmpty ||
        category.trim().isEmpty ||
        bsDate.trim().isEmpty ||
        !amount.isFinite ||
        amount <= 0) {
      throw Exception('खर्चको विवरण र सही रकम आवश्यक छन्।');
    }

    final membersSnapshot = await _members.get();
    final memberDocs = membersSnapshot.docs;

    final adminDocs = memberDocs.where((doc) {
      return (doc.data()['role'] ?? '').toString().toLowerCase() == 'admin';
    }).toList();

    final eligibleMembers = memberDocs;

    if (eligibleMembers.isEmpty) {
      throw Exception('मतदानका लागि योग्य सदस्य भेटिएनन्।');
    }

    final proposalRef = _proposals.doc(proposalId);

    await _db.runTransaction((transaction) async {
      final adminSnapshot = await transaction.get(_members.doc(user.uid));

      if (!adminSnapshot.exists ||
          (adminSnapshot.data()?['role'] ?? '').toString().toLowerCase() !=
              'admin') {
        throw Exception('यो काम Admin ले मात्र गर्न सक्नुहुन्छ।');
      }

      final proposalSnapshot = await transaction.get(proposalRef);

      if (!proposalSnapshot.exists) {
        throw Exception('खर्च प्रस्ताव भेटिएन।');
      }

      final oldData = proposalSnapshot.data()!;

      if (oldData['status'] != 'rejected') {
        throw Exception('अस्वीकृत प्रस्ताव मात्र पुनः पेश गर्न सकिन्छ।');
      }

      final allowedAt = oldData['resubmissionAllowedAt'];

      if (allowedAt is! Timestamp ||
          DateTime.now().isBefore(allowedAt.toDate())) {
        throw Exception(
            'पुनः प्रस्ताव पेश गर्ने २४ घण्टाको समय पूरा भएको छैन।');
      }

      final oldRound = (oldData['votingRound'] as num? ?? 1).toInt();

      if (oldRound >= 2) {
        throw Exception('दोस्रो मतदान चरण पहिले नै प्रयोग भइसकेको छ।');
      }

      final adminName = (adminSnapshot.data()?['name'] ?? 'प्रशासक').toString();

      final voters = eligibleMembers.map((doc) {
        return {
          'uid': doc.id,
          'name': (doc.data()['name'] ?? '').toString(),
          'vote': 'pending',
          'votedAt': null,
        };
      }).toList();

      final eligibleAdminTieBreakVoters = adminDocs
          .where((doc) => adminDocs.length == 1 || doc.id != user.uid)
          .map((doc) => {
                'uid': doc.id,
                'name': (doc.data()['name'] ?? '').toString(),
              })
          .toList();

      final oldHistory = List<Map<String, dynamic>>.from(
        (oldData['votingHistory'] as List? ?? []).map(
          (item) => Map<String, dynamic>.from(item),
        ),
      );

      oldHistory.add({
        'round': oldRound,
        'yesVotes': oldData['yesVotes'] ?? 0,
        'noVotes': oldData['noVotes'] ?? 0,
        'eligibleVoterCount': oldData['eligibleVoterCount'] ?? 0,
        'requiredApprovals': oldData['requiredApprovals'] ?? 0,
        'votingDeadline': oldData['votingDeadline'],
        'rejectedAt': oldData['rejectedAt'],
        'adminTieBreakVote': oldData['adminTieBreakVote'] ?? 'not_available',
        'adminTieBreakVotedByUid': oldData['adminTieBreakVotedByUid'],
      });

      final auditRef = await _auditService.prepareRecordInTransaction(
        transaction: transaction,
        eventId:
            'expense_proposal_resubmitted_${proposalId}_round_${oldRound + 1}',
      );

      final deadline = DateTime.now().add(votingDuration);

      transaction.update(proposalRef, {
        'title': title.trim(),
        'category': category.trim(),
        'amount': amount,
        'bsDate': bsDate.trim(),
        'expenseDate': Timestamp.fromDate(expenseDate),
        'description': description.trim(),
        'votingHistory': oldHistory,
        'votingRound': oldRound + 1,
        'status': 'voting',
        'votingStatus': 'in_progress',
        'eligibleVoterUids': eligibleMembers.map((doc) => doc.id).toList(),
        'eligibleVoterCount': eligibleMembers.length,
        'voters': voters,
        'eligibleAdminTieBreakVoters': eligibleAdminTieBreakVoters,
        'adminTieBreakVote': 'not_available',
        'adminTieBreakVotedByUid': null,
        'adminTieBreakVotedByName': null,
        'adminTieBreakVotedAt': null,
        'yesVotes': 0,
        'noVotes': 0,
        'requiredApprovals': requiredApprovals(eligibleMembers.length),
        'votingStartedAt': FieldValue.serverTimestamp(),
        'votingDeadline': Timestamp.fromDate(deadline),
        'approvedAt': null,
        'rejectedAt': null,
        'resubmissionAllowedAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _auditService.writePreparedRecordInTransaction(
        transaction: transaction,
        auditRef: auditRef,
        data: {
          'adminUid': user.uid,
          'adminName': adminName,
          'action': 'expense_proposal_resubmitted',
          'targetCollection': proposalCollection,
          'targetDocumentId': proposalId,
          'description':
              'सम्पादन गरिएको खर्च प्रस्ताव दोस्रो मतदानका लागि पुनः पेश गरियो।',
          'amount': amount,
          'newValues': {
            'title': title.trim(),
            'category': category.trim(),
            'amount': amount,
            'votingRound': oldRound + 1,
            'eligibleVoterCount': eligibleMembers.length,
          },
        },
      );
    });
  }

  Future<void> disburseApprovedProposal({
    required String proposalId,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('पहिले Login गर्नुहोस्।');
    }

    final proposalRef = _proposals.doc(proposalId);
    final adminRef = _members.doc(user.uid);

    final fundTransactionRef = _db
        .collection('fund_transactions')
        .doc('expense_withdrawal_$proposalId');

    await _db.runTransaction((transaction) async {
      final adminSnapshot = await transaction.get(adminRef);
      final proposalSnapshot = await transaction.get(proposalRef);
      final fundSnapshot = await transaction.get(fundTransactionRef);

      if (!adminSnapshot.exists ||
          (adminSnapshot.data()?['role'] ?? '').toString().toLowerCase() !=
              'admin') {
        throw Exception('खर्च वितरण Admin ले मात्र गर्न सक्नुहुन्छ।');
      }

      if (!proposalSnapshot.exists) {
        throw Exception('खर्च प्रस्ताव भेटिएन।');
      }

      final data = proposalSnapshot.data()!;

      if (data['status'] != 'approved') {
        throw Exception('स्वीकृत भएको प्रस्ताव मात्र वितरण गर्न सकिन्छ।');
      }

      if (data['disbursedAt'] != null || fundSnapshot.exists) {
        throw Exception('यो खर्च रकम पहिले नै वितरण भइसकेको छ।');
      }

      final voucherUrl = (data['paymentVoucherUrl'] ?? '').toString().trim();

      if (voucherUrl.isEmpty) {
        throw Exception('खर्चको Voucher पहिले अपलोड गर्नुहोस्।');
      }

      final amount = (data['amount'] as num?)?.toInt() ?? 0;

      if (amount <= 0) {
        throw Exception('खर्च रकम सही छैन।');
      }

      final adminName = (adminSnapshot.data()?['name'] ?? 'प्रशासक').toString();

      final auditRef = await _auditService.prepareRecordInTransaction(
        transaction: transaction,
        eventId: 'expense_disbursed_$proposalId',
      );

      transaction.set(fundTransactionRef, {
        'transactionId': fundTransactionRef.id,
        'fundType': 'expense',
        'category': 'expense_withdrawal',
        'transactionType': 'debit',
        'amount': amount,
        'proposalId': proposalId,
        'title': data['title'],
        'description': data['description'],
        'bsDate': data['bsDate'],
        'expenseDate': data['expenseDate'],
        'voucherUrl': voucherUrl,
        'voucherFileName': data['paymentVoucherFileName'],
        'status': 'disbursed',
        'disbursedByUid': user.uid,
        'disbursedByName': adminName,
        'isTest': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(proposalRef, {
        'status': 'disbursed',
        'disbursedAt': FieldValue.serverTimestamp(),
        'disbursedByUid': user.uid,
        'disbursedByName': adminName,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _auditService.writePreparedRecordInTransaction(
        transaction: transaction,
        auditRef: auditRef,
        data: {
          'adminUid': user.uid,
          'adminName': adminName,
          'action': 'expense_disbursed',
          'targetCollection': proposalCollection,
          'targetDocumentId': proposalId,
          'description': 'स्वीकृत खर्च रकम वास्तविक रूपमा वितरण गरियो।',
          'amount': amount,
          'newValues': {
            'status': 'disbursed',
            'fundTransactionId': fundTransactionRef.id,
            'amount': amount,
          },
        },
      );
    });

    await _notifyExpenseMembers(
      title: 'खर्च रकम वितरण भयो',
      message: 'स्वीकृत खर्च प्रस्तावको रकम वास्तविक रूपमा वितरण गरियो।',
      type: 'expense_disbursed',
      relatedId: proposalId,
    );
  }

  Future<Map<String, String>?> uploadVoucher({
    required String proposalId,
    required bool isPdf,
  }) async {
    try {
      String fileName;
      String extension;
      String contentType;
      List<int> fileBytes;

      if (isPdf) {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          withData: true,
        );

        if (result == null || result.files.isEmpty) {
          return null;
        }

        final file = result.files.single;

        if (file.bytes == null) {
          throw Exception('PDF फाइल पढ्न सकिएन।');
        }

        fileName = file.name;
        extension = 'pdf';
        contentType = 'application/pdf';
        fileBytes = file.bytes!;
      } else {
        final image = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );

        if (image == null) {
          return null;
        }

        fileName = image.name;
        extension = fileName.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
        contentType = extension == 'png' ? 'image/png' : 'image/jpeg';
        fileBytes = await image.readAsBytes();
      }

      if (fileBytes.length > 10 * 1024 * 1024) {
        throw Exception('फाइलको आकार १० MB भन्दा कम हुनुपर्छ।');
      }

      final filePath =
          'expense_vouchers/$proposalId/${DateTime.now().millisecondsSinceEpoch}.$extension';

      final uploadResult = await Supabase.instance.client.storage
          .from('expense_vouchers')
          .uploadBinary(
            filePath,
            fileBytes is Uint8List ? fileBytes : Uint8List.fromList(fileBytes),
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: false,
            ),
          )
          .timeout(const Duration(seconds: 30));

      final downloadUrl = Supabase.instance.client.storage
          .from('expense_vouchers')
          .getPublicUrl(filePath);

      return {
        'url': downloadUrl,
        'fileName': fileName,
      };
    } catch (e) {
      throw Exception('Voucher upload असफल भयो: $e');
    }
  }

  Future<void> attachVoucherToProposal({
    required String proposalId,
    required String voucherUrl,
    required String fileName,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('कृपया पहिले Login गर्नुहोस्।');
    }

    final proposalRef = _db.collection(proposalCollection).doc(proposalId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(proposalRef);

      if (!snapshot.exists) {
        throw Exception('Expense Proposal भेटिएन।');
      }

      final data = snapshot.data()!;

      if (data['status'] != 'voting' && data['status'] != 'approved') {
        throw Exception(
          'यस Proposal मा Voucher राख्न मिल्दैन।',
        );
      }

      transaction.update(proposalRef, {
        'paymentVoucherUrl': voucherUrl,
        'paymentVoucherFileName': fileName,
        'paymentVoucherUploadedByUid': user.uid,
        'paymentVoucherUploadedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
