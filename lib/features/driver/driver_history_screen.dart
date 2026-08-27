import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/cancel_reasons.dart';
import '../../core/services/ride_service.dart';
import '../shared/chat_screen.dart';
import '../shared/red_header.dart';

enum RideTypeFilter { all, solo, share, rent }

enum RideStatus { completed, cancelled }

class _RideRecord {
  final String rideId;
  final String? passengerId;
  final String passengerName;
  final String pickup;
  final String dropoff;
  final RideTypeFilter type;
  final RideStatus status;
  final DateTime date;
  final double baseFare;
  final double surcharge;
  final int seats; // relevant for PolaShare
  final double hours; // relevant for PolaRent
  final double totalFare;
  final double cancellationFee;
  final String? cancelReason;
  final String? cancelReasonText;
  final String? cancelledByRole;

  const _RideRecord({
    required this.rideId,
    this.passengerId,
    required this.passengerName,
    required this.pickup,
    required this.dropoff,
    required this.type,
    required this.status,
    required this.date,
    required this.baseFare,
    required this.surcharge,
    required this.totalFare,
    this.seats = 1,
    this.hours = 0,
    this.cancellationFee = 0,
    this.cancelReason,
    this.cancelReasonText,
    this.cancelledByRole,
  });

  /// The fare the passenger was quoted at booking time, rather than a
  /// recomputation that could drift from what was actually charged.
  double get total => totalFare;

  String get typeLabel {
    switch (type) {
      case RideTypeFilter.solo:
        return 'PolaSolo';
      case RideTypeFilter.share:
        return 'PolaShare';
      case RideTypeFilter.rent:
        return 'PolaRent';
      case RideTypeFilter.all:
        return '';
    }
  }
}

RideTypeFilter _typeFromRide(dynamic rideType) {
  switch (rideType) {
    case 'PolaShare': return RideTypeFilter.share;
    case 'PolaRent':  return RideTypeFilter.rent;
    default:          return RideTypeFilter.solo;
  }
}

class DriverHistoryScreen extends StatefulWidget {
  /// Returns the bottom-nav shell to the Home tab. This screen is a tab, not
  /// a pushed route, so there is nothing for `Navigator.pop` to pop.
  final VoidCallback? onBack;

  const DriverHistoryScreen({super.key, this.onBack});

  @override
  State<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends State<DriverHistoryScreen> {
  RideTypeFilter _filter = RideTypeFilter.all;

  // Passenger names, resolved once per uid so a long list doesn't re-read
  // users/{uid} on every rebuild.
  final Map<String, String> _names = {};

  Future<void> _resolveNames(Iterable<String> passengerIds) async {
    final missing =
        passengerIds.where((id) => !_names.containsKey(id)).toSet();
    if (missing.isEmpty) return;

    for (final id in missing) {
      _names[id] = '—'; // claim the slot so we don't fetch it twice
      final user = await RideService.userInfo(id);
      final name =
          '${user?['firstName'] ?? ''} ${user?['lastName'] ?? ''}'.trim();
      if (name.isNotEmpty) _names[id] = name;
    }
    if (mounted) setState(() {});
  }

  /// Only finished rides belong in history — an accepted or ongoing ride is
  /// still on the tracking screen.
  _RideRecord? _toRecord(Map<String, dynamic> ride, String rideId) {
    final RideStatus status;
    switch (ride['status']) {
      case 'completed':
        status = RideStatus.completed;
        break;
      case 'cancelled':
        status = RideStatus.cancelled;
        break;
      default:
        return null;
    }

    final requestedAt = ride['requestedAt'];
    final passengerId = ride['passengerId'] as String?;

    return _RideRecord(
      rideId: rideId,
      passengerId: passengerId,
      passengerName: passengerId == null ? '—' : (_names[passengerId] ?? '—'),
      pickup: ride['pickup']?['name'] ?? '—',
      dropoff: ride['dropoff']?['name'] ?? '—',
      type: _typeFromRide(ride['rideType']),
      status: status,
      date: requestedAt is Timestamp ? requestedAt.toDate() : DateTime.now(),
      baseFare: (ride['baseFare'] ?? 0).toDouble(),
      surcharge: (ride['surcharge'] ?? 0).toDouble(),
      totalFare: (ride['totalFare'] ?? 0).toDouble(),
      seats: (ride['seats'] ?? 1).toInt(),
      hours: (ride['hours'] ?? 0).toDouble(),
      cancellationFee: (ride['cancellationFee'] ?? 0).toDouble(),
      cancelReason: ride['cancelReason'] as String?,
      cancelReasonText: ride['cancelReasonText'] as String?,
      cancelledByRole: ride['cancelledByRole'] as String?,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      RedHeader(
        title: 'Ride History',
        subtitle: 'Your completed trips',
        onBack: widget.onBack,
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: RideService.driverHistory(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }

          final docs = snapshot.data!.docs;
          final ids = docs
              .map((d) => d.data()['passengerId'] as String?)
              .whereType<String>();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _resolveNames(ids);
          });

          final history = docs
              .map((d) => _toRecord(d.data(), d.id))
              .whereType<_RideRecord>()
              .toList();

          // Filtering happens here rather than in the query, so switching
          // chips costs nothing.
          final records = _filter == RideTypeFilter.all
              ? history
              : history.where((r) => r.type == _filter).toList();

          final totalEarnings = history
              .where((r) => r.status == RideStatus.completed)
              .fold(0.0, (acc, r) => acc + r.total);

          return Column(
            children: [
              _EarningsSummary(total: totalEarnings),
              _FilterRow(
                selected: _filter,
                onSelect: (f) => setState(() => _filter = f),
              ),
              Expanded(
                child: records.isEmpty
                    ? const _EmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: records.length,
                        itemBuilder: (context, index) =>
                            _HistoryCard(record: records[index]),
                      ),
              ),
            ],
          );
        },
        ),
      ),
    ]);
  }
}

class _EarningsSummary extends StatelessWidget {
  final double total;
  const _EarningsSummary({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Total Earnings',
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          Text(
            '₱${total.toStringAsFixed(0)}',
            style: const TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final RideTypeFilter selected;
  final ValueChanged<RideTypeFilter> onSelect;

  const _FilterRow({required this.selected, required this.onSelect});

  static const _labels = {
    RideTypeFilter.all: 'All',
    RideTypeFilter.solo: 'PolaSolo',
    RideTypeFilter.share: 'PolaShare',
    RideTypeFilter.rent: 'PolaRent',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: _labels.entries.map((entry) {
          final isSelected = entry.key == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _FilterChip(
              label: entry.value,
              selected: isSelected,
              onTap: () => onSelect(entry.key),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final _RideRecord record;
  const _HistoryCard({required this.record});

  void _openChat(BuildContext context) {
    final passengerId = record.passengerId;
    if (passengerId == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        rideId: record.rideId,
        otherUid: passengerId,
        otherName: record.passengerName,
        otherRole: 'passenger',
      ),
    ));
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year} · $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = record.status == RideStatus.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _Badge(
                    label: record.typeLabel,
                    color: AppColors.primary,
                    background: AppColors.primaryTint,
                  ),
                  const SizedBox(width: 8),
                  _Badge(
                    label: isCompleted ? 'Completed' : 'Cancelled',
                    color: isCompleted ? AppColors.success : AppColors.warning,
                    background: isCompleted
                        ? AppColors.successTint
                        : const Color(0x1AB45309),
                  ),
                ],
              ),
              Text(
                '₱${record.total.toStringAsFixed(0)}',
                style: TextStyle(
                  fontFamily: 'Syne',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: isCompleted
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  record.passengerName,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (record.passengerId != null) ...[
                const SizedBox(width: 8),
                _ChatIconButton(onTap: () => _openChat(context)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          _RouteLine(pickup: record.pickup, dropoff: record.dropoff),
          const SizedBox(height: 10),
          Text(
            _formatDate(record.date),
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
          if (!isCompleted) ...[
            const SizedBox(height: 6),
            Text(
              cancelReasonLabel(
                cancelledByRole: record.cancelledByRole,
                reason: record.cancelReason,
                reasonText: record.cancelReasonText,
              ),
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w500,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            if (record.cancellationFee > 0) ...[
              const SizedBox(height: 3),
              Text(
                'Late cancellation fee: ₱${record.cancellationFee.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: AppColors.warning,
                ),
              ),
            ],
          ],
          if (isCompleted) ...[
            const Divider(height: 24, color: AppColors.border),
            _FareBreakdown(record: record),
          ],
        ],
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  final String pickup;
  final String dropoff;
  const _RouteLine({required this.pickup, required this.dropoff});

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontFamily: 'DM Sans',
      fontWeight: FontWeight.w500,
      fontSize: 13,
      color: AppColors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.circle, size: 8, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(child: Text(pickup, style: textStyle)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 3.5),
          child: Container(
            width: 1,
            height: 14,
            color: AppColors.border,
          ),
        ),
        Row(
          children: [
            const Icon(Icons.location_on, size: 8, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(dropoff, style: textStyle)),
          ],
        ),
      ],
    );
  }
}

class _FareBreakdown extends StatelessWidget {
  final _RideRecord record;
  const _FareBreakdown({required this.record});

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[];
    switch (record.type) {
      case RideTypeFilter.solo:
        rows.add(MapEntry('Base fare', '₱${record.baseFare.toStringAsFixed(0)}'));
        if (record.surcharge > 0) {
          rows.add(MapEntry('Surcharge', '₱${record.surcharge.toStringAsFixed(0)}'));
        }
        break;
      case RideTypeFilter.share:
        rows.add(MapEntry('Fare per seat', '₱${record.baseFare.toStringAsFixed(0)}'));
        rows.add(MapEntry('Seats booked', '${record.seats}'));
        break;
      case RideTypeFilter.rent:
        rows.add(const MapEntry('Rate', '₱60/hr'));
        rows.add(MapEntry('Duration', '${record.hours.toStringAsFixed(0)} hr'));
        break;
      case RideTypeFilter.all:
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  r.key,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  r.value,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total collected (cash)',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '₱${record.total.toStringAsFixed(0)}',
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;

  const _Badge({
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'DM Sans',
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: color,
        ),
      ),
    );
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          const Text(
            'No rides for this filter yet',
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