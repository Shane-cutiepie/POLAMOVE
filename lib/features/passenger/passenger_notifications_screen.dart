import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';

class PassengerNotificationsScreen extends StatefulWidget {
  const PassengerNotificationsScreen({super.key});

  @override
  State<PassengerNotificationsScreen> createState() =>
      _PassengerNotificationsScreenState();
}

class _PassengerNotificationsScreenState
    extends State<PassengerNotificationsScreen> {

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('notifications');

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream(String uid) => _collection
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots();

  /// One batched write rather than a loop of individual updates — marking a
  /// full inbox read should cost one round trip, not fifty.
  Future<void> _markAllRead(String uid) async {
    try {
      final unread = await _collection
          .where('userId', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .get();
      if (unread.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Could not update your notifications. Please try again.',
            style: TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _markRead(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      await ref.update({'read': true});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream(uid),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final unread =
            docs.where((d) => d.data()['read'] == false).length;

        return Column(children: [
          // Header
          Container(
            color: AppColors.surface,
            child: SafeArea(bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Notifications', style: TextStyle(fontFamily: 'Syne',
                        fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(unread > 0 ? '$unread unread' : 'All caught up!',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ])),
                  if (unread > 0)
                    GestureDetector(
                      onTap: () => _markAllRead(uid),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(color: AppColors.primaryTint,
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(color: AppColors.primary.withOpacity(0.22))),
                        child: const Text('Mark all read', style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0x1C14142A)),
          // Notif list
          Expanded(
            child: !snapshot.hasData
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : docs.isEmpty
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('🔔', style: TextStyle(fontSize: 48)),
                        SizedBox(height: 12),
                        Text('No notifications yet', style: TextStyle(fontFamily: 'Syne',
                            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 4),
                        Text('Ride updates will appear here',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ]))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1,
                            indent: 60, color: Color(0x1C14142A)),
                        itemBuilder: (_, i) {
                          final doc = docs[i];
                          final n = doc.data();
                          final isRead = n['read'] == true;
                          return GestureDetector(
                            onTap: isRead ? null : () => _markRead(doc.reference),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              color: !isRead
                                  ? AppColors.primaryTint.withOpacity(0.5) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: _accentTint(n['category']),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _accentBorder(n['category'])),
                                  ),
                                  child: Center(child: Icon(_icon(n['category']),
                                      size: 20, color: _accent(n['category'])))),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(n['title'] ?? '—',
                                        style: TextStyle(fontFamily: 'Syne', fontSize: 13,
                                            fontWeight: !isRead
                                                ? FontWeight.w700 : FontWeight.w600,
                                            color: AppColors.textPrimary))),
                                    Text(_relativeTime(n['createdAt']),
                                        style: const TextStyle(fontSize: 10,
                                            color: AppColors.textTertiary)),
                                  ]),
                                  const SizedBox(height: 3),
                                  Text(n['message'] ?? '—', style: const TextStyle(fontSize: 12,
                                      color: AppColors.textSecondary, height: 1.4)),
                                ])),
                                if (!isRead) ...[
                                  const SizedBox(width: 8),
                                  Container(width: 7, height: 7, margin: const EdgeInsets.only(top: 4),
                                      decoration: const BoxDecoration(
                                          color: AppColors.primary, shape: BoxShape.circle)),
                                ],
                              ]),
                            ),
                          );
                        },
                      ),
          ),
        ]);
      },
    );
  }

  // Category treatment mirrors driver_notifications_screen.dart so both
  // inboxes read the same way.
  IconData _icon(dynamic category) {
    switch (category) {
      case 'ride': return Icons.local_taxi_outlined;
      case 'earnings': return Icons.payments_outlined;
      case 'account': return Icons.verified_user_outlined;
      default: return Icons.campaign_outlined;
    }
  }

  Color _accent(dynamic category) {
    switch (category) {
      case 'ride': return AppColors.primary;
      case 'earnings': return AppColors.success;
      case 'account': return AppColors.warning;
      default: return AppColors.textSecondary;
    }
  }

  Color _accentTint(dynamic category) {
    switch (category) {
      case 'ride': return AppColors.primaryTint;
      case 'earnings': return AppColors.successTint;
      case 'account': return const Color(0x1AB45309);
      default: return AppColors.surfaceAlt;
    }
  }

  Color _accentBorder(dynamic category) {
    switch (category) {
      case 'ride': return AppColors.primary.withOpacity(0.22);
      case 'earnings': return AppColors.success.withOpacity(0.3);
      case 'account': return AppColors.warning.withOpacity(0.3);
      default: return AppColors.border;
    }
  }

  /// `createdAt` is null for the moment between a local write and the server
  /// timestamp landing, so it has to be guarded.
  String _relativeTime(dynamic createdAt) {
    if (createdAt is! Timestamp) return '—';
    final t = createdAt.toDate();
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[t.month - 1]} ${t.day}';
  }
}
