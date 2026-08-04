import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class PassengerNotificationsScreen extends StatefulWidget {
  const PassengerNotificationsScreen({super.key});

  @override
  State<PassengerNotificationsScreen> createState() =>
      _PassengerNotificationsScreenState();
}

class _PassengerNotificationsScreenState
    extends State<PassengerNotificationsScreen> {

  final List<Map<String, dynamic>> _notifs = [
    {
      'emoji': '🛺', 'title': 'Driver Found!',
      'body': 'Carlos Reyes (POLO-1234) is on the way to your pickup point.',
      'time': 'Just now', 'read': false, 'type': 'ride',
    },
    {
      'emoji': '✅', 'title': 'Ride Completed',
      'body': 'Your PolaSolo ride to Bicol University is complete. Fare: ₱20.',
      'time': '2h ago', 'read': false, 'type': 'ride',
    },
    {
      'emoji': '🔔', 'title': 'Booking Confirmed',
      'body': 'Your PolaShare booking has been confirmed. ETA: 4 minutes.',
      'time': 'Yesterday', 'read': true, 'type': 'booking',
    },
    {
      'emoji': '❌', 'title': 'Booking Cancelled',
      'body': 'Your ride was cancelled. No available drivers at the moment. Please try again.',
      'time': 'Jul 30', 'read': true, 'type': 'system',
    },
    {
      'emoji': '📢', 'title': 'PolaMove Update',
      'body': 'PolaRent is now available! Rent an entire tricycle by the hour for your errands.',
      'time': 'Jul 28', 'read': true, 'type': 'promo',
    },
  ];

  void _markAllRead() {
    setState(() {
      for (final n in _notifs) n['read'] = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => n['read'] == false).length;
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
                  onTap: _markAllRead,
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
        child: _notifs.isEmpty
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
                itemCount: _notifs.length,
                separatorBuilder: (_, __) => const Divider(height: 1,
                    indent: 60, color: Color(0x1C14142A)),
                itemBuilder: (_, i) {
                  final n = _notifs[i];
                  return GestureDetector(
                    onTap: () => setState(() => n['read'] = true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      color: n['read'] == false
                          ? AppColors.primaryTint.withOpacity(0.5) : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: _notifBg(n['type']),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _notifBorder(n['type'])),
                          ),
                          child: Center(child: Text(n['emoji'],
                              style: const TextStyle(fontSize: 18)))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(n['title'],
                                style: TextStyle(fontFamily: 'Syne', fontSize: 13,
                                    fontWeight: n['read'] == false
                                        ? FontWeight.w700 : FontWeight.w600,
                                    color: AppColors.textPrimary))),
                            Text(n['time'], style: const TextStyle(fontSize: 10,
                                color: AppColors.textTertiary)),
                          ]),
                          const SizedBox(height: 3),
                          Text(n['body'], style: const TextStyle(fontSize: 12,
                              color: AppColors.textSecondary, height: 1.4)),
                        ])),
                        if (n['read'] == false) ...[
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
  }

  Color _notifBg(String type) {
    switch (type) {
      case 'ride': return AppColors.primaryTint;
      case 'booking': return AppColors.successTint;
      case 'promo': return const Color(0x1AB45309);
      default: return AppColors.surfaceAlt;
    }
  }

  Color _notifBorder(String type) {
    switch (type) {
      case 'ride': return AppColors.primary.withOpacity(0.22);
      case 'booking': return AppColors.success.withOpacity(0.3);
      case 'promo': return AppColors.warning.withOpacity(0.3);
      default: return AppColors.border;
    }
  }
}