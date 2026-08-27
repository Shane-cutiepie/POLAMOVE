import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/ride_service.dart';
import '../shared/red_header.dart';

class PassengerNotificationsScreen extends StatefulWidget {
  /// Returns the bottom-nav shell to the Home tab. This screen is a tab, not
  /// a pushed route, so there is nothing for `Navigator.pop` to pop.
  final VoidCallback? onBack;

  const PassengerNotificationsScreen({super.key, this.onBack});

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

  /// The list is a StreamBuilder, so the row disappears on its own once the
  /// document is gone — nothing to remove from local state here.
  Future<void> _deleteNotification(String notifId) async {
    try {
      await RideService.deleteNotification(notifId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Notification deleted.',
            style: TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } on RideException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message, style: const TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _confirmDelete(String notifId, String title) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _DeleteNotifSheet(title: title),
    );
    if (confirmed == true) _deleteNotification(notifId);
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
          RedHeader(
            title: 'Notifications',
            subtitle: 'Updates about your rides',
            onBack: widget.onBack,
            action: unread > 0
                ? RedHeaderAction(
                    label: 'Mark all read',
                    onTap: () => _markAllRead(uid),
                  )
                : null,
          ),
          Expanded(
            child: !snapshot.hasData
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : docs.isEmpty
                    ? const _EmptyState()
                    : Column(
                        children: [
                          if (unread > 0) _UnreadBanner(count: unread),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final doc = docs[index];
                                final n = doc.data();
                                final isRead = n['read'] == true;
                                final createdAt = n['createdAt'];
                                return _NotifCard(
                                  title: n['title'] ?? '—',
                                  message: n['message'] ?? '—',
                                  category: n['category'],
                                  time: createdAt is Timestamp
                                      ? createdAt.toDate()
                                      : DateTime.now(),
                                  isRead: isRead,
                                  onTap: isRead
                                      ? null
                                      : () => _markRead(doc.reference),
                                  onLongPress: () =>
                                      _confirmDelete(doc.id, n['title'] ?? '—'),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ]);
      },
    );
  }
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

class _UnreadBanner extends StatelessWidget {
  final int count;
  const _UnreadBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.successTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        count == 1 ? '1 unread notification' : '$count unread notifications',
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: AppColors.success,
        ),
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final String title;
  final String message;
  final dynamic category;
  final DateTime time;
  final bool isRead;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;

  const _NotifCard({
    required this.title,
    required this.message,
    required this.category,
    required this.time,
    required this.isRead,
    required this.onTap,
    required this.onLongPress,
  });

  String _relativeTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[t.month - 1]} ${t.day}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: !isRead ? AppColors.successTint : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: !isRead ? AppColors.success : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _accentTint(category),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon(category), size: 20, color: _accent(category)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _relativeTime(time),
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      if (!isRead) ...[
                        const SizedBox(width: 6),
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.notifications_none_rounded,
              size: 48, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Long-press sheet — itself the confirmation step, so Delete acts
/// immediately with no second dialog.
class _DeleteNotifSheet extends StatelessWidget {
  final String title;
  const _DeleteNotifSheet({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.surfaceStrong,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Syne', fontSize: 15,
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 18),
          _DeleteNotifRow(onTap: () => Navigator.pop(context, true)),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: Color(0x1C14142A), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: const Text('Cancel', style: TextStyle(fontFamily: 'DM Sans',
                  fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Styled like _PickerOption in auth_driver_screen.dart, but both the icon
/// and label render in AppColors.primary since this row is a destructive
/// action rather than a neutral navigation option.
class _DeleteNotifRow extends StatelessWidget {
  final VoidCallback onTap;
  const _DeleteNotifRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x1C14142A), width: 1.5)),
        child: Row(children: [
          Container(width: 46, height: 46,
            decoration: BoxDecoration(color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.primary.withOpacity(0.22))),
            child: const Icon(Icons.delete_outline, color: AppColors.primary, size: 22)),
          const SizedBox(width: 13),
          const Expanded(child: Text('Delete notification',
              style: TextStyle(fontFamily: 'Syne', fontSize: 14,
                  fontWeight: FontWeight.w700, color: AppColors.primary))),
        ]),
      ),
    );
  }
}
