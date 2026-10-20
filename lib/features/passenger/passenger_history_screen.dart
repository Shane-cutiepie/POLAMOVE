import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/cancel_reasons.dart';
import '../../core/services/ride_service.dart';
import '../shared/chat_screen.dart';
import '../shared/red_header.dart';

class PassengerHistoryScreen extends StatefulWidget {
  /// Returns the bottom-nav shell to the Home tab. This screen is a tab, not
  /// a pushed route, so there is nothing for `Navigator.pop` to pop.
  final VoidCallback? onBack;

  const PassengerHistoryScreen({super.key, this.onBack});

  @override
  State<PassengerHistoryScreen> createState() => _PassengerHistoryScreenState();
}

class _PassengerHistoryScreenState extends State<PassengerHistoryScreen> {
  /// Driver display labels ("Carlos Reyes · POLO-1234") keyed by driver uid,
  /// resolved once per driver so scrolling a long history doesn't re-read
  /// users/{uid} and drivers/{uid} for every row.
  final Map<String, String> _driverLabels = {};

  /// Plain driver names (no plate), keyed by uid — used as the chat
  /// screen's title rather than the combined "name · plate" label above.
  final Map<String, String> _driverNames = {};

  Future<void> _resolveDrivers(Iterable<String> driverIds) async {
    final missing =
        driverIds.where((id) => !_driverLabels.containsKey(id)).toSet();
    if (missing.isEmpty) return;

    for (final id in missing) {
      _driverLabels[id] = '—'; // claim the slot so we don't fetch it twice
      _driverNames[id] = '—';
      final user = await RideService.userInfo(id);
      final driver = await RideService.driverInfo(id);
      final name =
          '${user?['firstName'] ?? ''} ${user?['lastName'] ?? ''}'.trim();
      final plate = driver?['plateNo'] ?? '—';
      _driverNames[id] = name.isEmpty ? '—' : name;
      _driverLabels[id] = '${name.isEmpty ? '—' : name} · $plate';
    }
    if (mounted) setState(() {});
  }

  /// Flattens a ride document into the map shape _RideCard already renders.
  static Map<String, dynamic> _toCard(Map<String, dynamic> ride, String rideId) {
    final type = _shortType(ride['rideType']);
    final fare = (ride['totalFare'] ?? 0).toDouble();
    final requestedAt = ride['requestedAt'];
    final date = requestedAt is Timestamp ? requestedAt.toDate() : null;

    return {
      'rideId': rideId,
      'type': type,
      'emoji': _emoji(type),
      'from': ride['pickup']?['name'] ?? '—',
      'to': ride['dropoff']?['name'] ?? '—',
      'date': date == null ? '—' : _formatDate(date),
      'time': date == null ? '—' : _formatTime(date),
      'fare': '₱${fare.toStringAsFixed(0)}',
      'fareValue': fare,
      'status': _statusLabel(ride['status']),
      'driverId': ride['driverId'] as String?,
      'cancellationFee': (ride['cancellationFee'] ?? 0).toDouble(),
      'cancelReason': ride['cancelReason'] as String?,
      'cancelReasonText': ride['cancelReasonText'] as String?,
      'cancelledByRole': ride['cancelledByRole'] as String?,
    };
  }

  static String _shortType(dynamic rideType) {
    switch (rideType) {
      case 'PolaShare': return 'share';
      case 'PolaRent':  return 'rent';
      default:          return 'solo';
    }
  }

  static String _emoji(String type) {
    switch (type) {
      case 'share': return '👥';
      case 'rent':  return '🗓️';
      default:      return '🚖';
    }
  }

  static String _statusLabel(dynamic status) {
    switch (status) {
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default:          return 'Ongoing';
    }
  }

  static String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _formatTime(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:${d.minute.toString().padLeft(2, '0')} $period';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      RedHeader(
        title: 'Ride History',
        subtitle: 'Your past trips in Polangui',
        onBack: widget.onBack,
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: RideService.passengerHistory(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary));
            }

            final docs = snapshot.data!.docs;
            final driverIds = docs
                .map((d) => d.data()['driverId'] as String?)
                .whereType<String>();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _resolveDrivers(driverIds);
            });

            final rides = docs.map((d) => _toCard(d.data(), d.id)).toList();
            final completed =
                rides.where((r) => r['status'] == 'Completed').toList();
            final spent = completed.fold<double>(
                0, (acc, r) => acc + (r['fareValue'] as double));

            return Column(children: [
              // Summary chips
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
                child: Row(children: [
                  _SummaryChip(label: 'Total Rides',
                      value: '${completed.length}', emoji: '🛺'),
                  const SizedBox(width: 8),
                  _SummaryChip(label: 'Total Spent',
                      value: '₱${spent.toStringAsFixed(0)}', emoji: '💰'),
                  const SizedBox(width: 8),
                  _SummaryChip(label: 'Completed',
                      value: '${completed.length}', emoji: '✅'),
                ]),
              ),
              const Divider(height: 1, color: Color(0x1C14142A)),
              // Ride list
              Expanded(
                child: rides.isEmpty
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
                        itemCount: rides.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _RideCard(
                          ride: rides[i],
                          driverLabel: _driverLabel(rides[i]['driverId']),
                          driverName: _driverName(rides[i]['driverId']),
                        ),
                      ),
              ),
            ]);
          },
        ),
      ),
    ]);
  }

  /// A ride can finish without ever having a driver — cancelled while still
  /// searching — so a missing id is a real state, not a failed lookup.
  String _driverLabel(String? driverId) {
    if (driverId == null) return 'Driver not assigned';
    return '🛺 ${_driverLabels[driverId] ?? '—'}';
  }

  String _driverName(String? driverId) {
    if (driverId == null) return '—';
    return _driverNames[driverId] ?? '—';
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
  final String driverLabel;
  final String driverName;
  const _RideCard({required this.ride, required this.driverLabel, required this.driverName});

  Color get _statusColor => ride['status'] == 'Completed' ? AppColors.success : AppColors.warning;
  Color get _statusBg => ride['status'] == 'Completed' ? AppColors.successTint : const Color(0x1AB45309);

  /// Chat stays readable after a trip ends — but a ride cancelled while still
  /// searching never had a driver, so there's no thread to open.
  bool get _canChat =>
      ride['driverId'] != null &&
      (ride['status'] == 'Completed' || ride['status'] == 'Cancelled');

  void _openChat(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        rideId: ride['rideId'] as String,
        otherUid: ride['driverId'] as String,
        otherName: driverName,
        otherRole: 'driver',
      ),
    ));
  }

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
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.22))),
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
        const SizedBox(height: 8),
        // Driver
        Row(children: [
          Expanded(child: Text(driverLabel, style: const TextStyle(fontSize: 11,
              color: AppColors.textSecondary))),
          if (_canChat) ...[
            const SizedBox(width: 8),
            _ChatIconButton(onTap: () => _openChat(context)),
          ],
        ]),
        if (ride['status'] == 'Cancelled') ...[
          const SizedBox(height: 6),
          Text(
            cancelReasonLabel(
              cancelledByRole: ride['cancelledByRole'] as String?,
              reason: ride['cancelReason'] as String?,
              reasonText: ride['cancelReasonText'] as String?,
            ),
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          if ((ride['cancellationFee'] as double) > 0) ...[
            const SizedBox(height: 3),
            Text(
              'Late cancellation fee: ₱${(ride['cancellationFee'] as double).toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 11, color: AppColors.warning),
            ),
          ],
        ],
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

class _ChatIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ChatIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 30, height: 30,
        decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle,
            border: Border.all(color: AppColors.border, width: 1.5)),
        child: const Center(child: Text('💬', style: TextStyle(fontSize: 14)))),
    );
  }
}
