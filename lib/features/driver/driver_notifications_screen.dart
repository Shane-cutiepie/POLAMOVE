import 'package:flutter/material.dart';
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

// TODO: Firebase - replace with Firestore stream + FCM push handling
final List<_NotifItem> _mockNotifications = [
  _NotifItem(
    title: 'New ride request nearby',
    message:
        'A passenger in Brgy. Oras is looking for a PolaSolo ride. Go online to receive requests.',
    category: NotifCategory.ride,
    time: DateTime(2026, 8, 4, 7, 45),
    unread: true,
  ),
  _NotifItem(
    title: 'Ride completed',
    message:
        'Your trip with Juan Dela Cruz is complete. Please collect cash payment of ₱20.',
    category: NotifCategory.earnings,
    time: DateTime(2026, 8, 3, 14, 35),
    unread: true,
  ),
  _NotifItem(
    title: 'Application approved',
    message:
        'Your driver application has been approved by the admin. You can now go online and accept rides.',
    category: NotifCategory.account,
    time: DateTime(2026, 8, 2, 10, 12),
  ),
  _NotifItem(
    title: 'TODA general assembly',
    message:
        'The Polangui Tricycle Operators and Drivers Association will hold its monthly assembly on August 10 at the Municipal Hall.',
    category: NotifCategory.announcement,
    time: DateTime(2026, 8, 1, 16, 0),
  ),
  _NotifItem(
    title: 'License expiring soon',
    message:
        'Your driver\'s license expires in 30 days. Please upload a renewed copy to keep your account active.',
    category: NotifCategory.account,
    time: DateTime(2026, 7, 30, 9, 0),
  ),
  _NotifItem(
    title: 'Ride cancelled by passenger',
    message:
        'Ana Villareal cancelled the ride request from Brgy. Quirangay before pickup.',
    category: NotifCategory.ride,
    time: DateTime(2026, 7, 29, 11, 20),
  ),
];

class DriverNotificationsScreen extends StatefulWidget {
  const DriverNotificationsScreen({super.key});

  @override
  State<DriverNotificationsScreen> createState() =>
      _DriverNotificationsScreenState();
}

class _DriverNotificationsScreenState extends State<DriverNotificationsScreen> {
  late List<_NotifItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(_mockNotifications);
  }

  int get _unreadCount => _items.where((n) => n.unread).length;

  void _markAllRead() {
    // TODO: Firebase - batch update read status in Firestore
    setState(() {
      _items = _items
          .map((n) => _NotifItem(
                title: n.title,
                message: n.message,
                category: n.category,
                time: n.time,
                unread: false,
              ))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
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
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
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
      body: _items.isEmpty
          ? const _EmptyState()
          : Column(
              children: [
                if (_unreadCount > 0) _UnreadBanner(count: _unreadCount),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: _items.length,
                    itemBuilder: (context, index) =>
                        _NotifCard(item: _items[index]),
                  ),
                ),
              ],
            ),
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
    final now = DateTime(2026, 8, 4, 8, 0); // TODO: Firebase - use DateTime.now()
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