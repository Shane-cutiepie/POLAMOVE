import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';

enum NotifCategory { ride, earnings, account, announcement }

class _NotifItem {
  final String title;
  final String message;
  final NotifCategory category;
  final DateTime time;
  final bool unread;

  const _NotifItem({
    required this.title,
    required this.message,
    required this.category,
    required this.time,
    this.unread = false,
  });

  IconData get icon {
    switch (category) {
      case NotifCategory.ride:
        return Icons.local_taxi_outlined;
      case NotifCategory.earnings:
        return Icons.payments_outlined;
      case NotifCategory.account:
        return Icons.verified_user_outlined;
      case NotifCategory.announcement:
        return Icons.campaign_outlined;
    }
  }

  Color get accent {
    switch (category) {
      case NotifCategory.ride:
        return AppColors.primary;
      case NotifCategory.earnings:
        return AppColors.success;
      case NotifCategory.account:
        return AppColors.warning;
      case NotifCategory.announcement:
        return AppColors.textSecondary;
    }
  }

  Color get accentTint {
    switch (category) {
      case NotifCategory.ride:
        return AppColors.primaryTint;
      case NotifCategory.earnings:
        return AppColors.successTint;
      case NotifCategory.account:
        return const Color(0x1AB45309);
      case NotifCategory.announcement:
        return AppColors.surfaceAlt;
    }
  }
}

class DriverNotificationsScreen extends StatefulWidget {
  const DriverNotificationsScreen({super.key});

  @override
  State<DriverNotificationsScreen> createState() =>
      _DriverNotificationsScreenState();
}

class _DriverNotificationsScreenState extends State<DriverNotificationsScreen> {
  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('notifications');

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream(String uid) => _collection
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots();

  _NotifItem _toItem(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    return _NotifItem(
      title: data['title'] ?? '—',
      message: data['message'] ?? '—',
      category: _categoryFrom(data['category']),
      // Null for the moment between the local write and the server timestamp
      // landing, which reads as the newest entry either way.
      time: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      unread: data['read'] == false,
    );
  }

  NotifCategory _categoryFrom(dynamic value) {
    switch (value) {
      case 'ride':
        return NotifCategory.ride;
      case 'earnings':
        return NotifCategory.earnings;
      case 'account':
        return NotifCategory.account;
      default:
        return NotifCategory.announcement;
    }
  }

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
        content: const Text(
            'Could not update your notifications. Please try again.',
            style: TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream(uid),
      builder: (context, snapshot) {
        final items =
            (snapshot.data?.docs ?? const []).map((d) => _toItem(d.data())).toList();
        final unreadCount = items.where((n) => n.unread).length;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            title: const Text(
              'Notifications',
              style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: AppColors.textPrimary,
              ),
            ),
            actions: [
              if (unreadCount > 0)
                TextButton(
                  onPressed: () => _markAllRead(uid),
                  child: const Text(
                    'Mark all read',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          body: !snapshot.hasData
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : items.isEmpty
                  ? const _EmptyState()
                  : Column(
                      children: [
                        if (unreadCount > 0) _UnreadBanner(count: unreadCount),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            itemCount: items.length,
                            itemBuilder: (context, index) =>
                                _NotifCard(item: items[index]),
                          ),
                        ),
                      ],
                    ),
        );
      },
    );
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
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        count == 1 ? '1 unread notification' : '$count unread notifications',
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final _NotifItem item;
  const _NotifCard({required this.item});

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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: item.unread ? AppColors.primaryTint : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.unread ? AppColors.primary : AppColors.border,
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
              color: item.accentTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, size: 20, color: item.accent),
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
                        item.title,
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
                      _relativeTime(item.time),
                      style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    if (item.unread) ...[
                      const SizedBox(width: 6),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
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
