import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class PassengerHistoryScreen extends StatelessWidget {
  const PassengerHistoryScreen({super.key});

  final List<Map<String, dynamic>> _rides = const [
    {
      'type': 'solo', 'emoji': '🚖',
      'from': 'Polangui Centro', 'to': 'Bicol University',
      'date': 'Aug 1, 2026', 'time': '8:14 AM',
      'fare': '₱20', 'status': 'Completed',
    },
    {
      'type': 'share', 'emoji': '👥',
      'from': 'Public Market', 'to': 'Lidong',
      'date': 'Jul 30, 2026', 'time': '3:42 PM',
      'fare': '₱30', 'status': 'Completed',
    },
    {
      'type': 'rent', 'emoji': '🗓️',
      'from': 'Polangui Centro', 'to': 'Multiple stops',
      'date': 'Jul 28, 2026', 'time': '10:00 AM',
      'fare': '₱120', 'status': 'Completed',
    },
    {
      'type': 'solo', 'emoji': '🚖',
      'from': 'Bus Terminal', 'to': 'Sabang',
      'date': 'Jul 25, 2026', 'time': '6:55 PM',
      'fare': '₱20', 'status': 'Cancelled',
    },
    {
      'type': 'share', 'emoji': '👥',
      'from': 'Polangui Hospital', 'to': 'Centro',
      'date': 'Jul 22, 2026', 'time': '1:30 PM',
      'fare': '₱15', 'status': 'Completed',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header
      Container(
        color: AppColors.surface,
        child: SafeArea(bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ride History', style: TextStyle(fontFamily: 'Syne',
                  fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text('Your past trips in Polangui',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
        ),
      ),
      // Summary chips
      Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(15, 0, 15, 14),
        child: Row(children: [
          _SummaryChip(label: 'Total Rides', value: '5', emoji: '🛺'),
          const SizedBox(width: 8),
          _SummaryChip(label: 'Total Spent', value: '₱205', emoji: '💰'),
          const SizedBox(width: 8),
          _SummaryChip(label: 'Completed', value: '4', emoji: '✅'),
        ]),
      ),
      const Divider(height: 1, color: Color(0x1C14142A)),
      // Ride list
      Expanded(
        child: _rides.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('🛺', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text('No rides yet', style: TextStyle(fontFamily: 'Syne',
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(height: 4),
                Text('Your ride history will appear here',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ]))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 20),
                itemCount: _rides.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _RideCard(ride: _rides[i]),
              ),
      ),
    ]);
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final String emoji;
  const _SummaryChip({required this.label, required this.value, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontFamily: 'Syne', fontSize: 15,
              fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary,
              fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  const _RideCard({required this.ride});

  Color get _statusColor => ride['status'] == 'Completed' ? AppColors.success : AppColors.warning;
  Color get _statusBg => ride['status'] == 'Completed' ? AppColors.successTint : const Color(0x1AB45309);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Top row
        Row(children: [
          Container(width: 38, height: 38,
            decoration: BoxDecoration(color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.primary.withOpacity(0.22))),
            child: Center(child: Text(ride['emoji'], style: const TextStyle(fontSize: 18)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_rideTypeName, style: const TextStyle(fontFamily: 'Syne', fontSize: 13,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text('${ride['date']} · ${ride['time']}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(ride['fare'], style: const TextStyle(fontFamily: 'Syne', fontSize: 15,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _statusBg, borderRadius: BorderRadius.circular(50)),
              child: Text(ride['status'], style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.w700, color: _statusColor)),
            ),
          ]),
        ]),
        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0x1C14142A)),
        const SizedBox(height: 10),
        // Route row
        Row(children: [
          Column(children: [
            Container(width: 8, height: 8,
                decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
            Container(width: 1.5, height: 16, color: AppColors.border),
            Container(width: 8, height: 8,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
          ]),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ride['from'], style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Text(ride['to'], style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ])),
        ]),
      ]),
    );
  }

  String get _rideTypeName {
    switch (ride['type']) {
      case 'solo': return 'PolaSolo';
      case 'share': return 'PolaShare';
      case 'rent': return 'PolaRent';
      default: return 'Ride';
    }
  }
}