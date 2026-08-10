import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/ride_service.dart';

class RideStatusScreen extends StatefulWidget {
  final String rideId;
  final String pickup;
  final String destination;
  final String rideType;
  final double fare;

  const RideStatusScreen({
    super.key,
    required this.rideId,
    required this.pickup,
    required this.destination,
    required this.rideType,
    required this.fare,
  });

  @override
  State<RideStatusScreen> createState() => _RideStatusScreenState();
}

class _RideStatusScreenState extends State<RideStatusScreen>
    with TickerProviderStateMixin {
  int _currentStep = 0; // 0=Searching, 1=Found, 2=Arrived, 3=Trip, 4=Done
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  static const LatLng _polangui = LatLng(13.2924, 123.4866);

  final _stepLabels = ['Search', 'Found', 'Arrived', 'Trip', 'Done'];
  final _stepEmojis = ['🔍', '🛺', '📍', '🏁', '✅'];

  // Driver details, fetched once when a driver is assigned to the ride
  String? _assignedDriverId;
  String _driverName = '—';
  String _driverPlate = '—';
  String _driverRating = '—';
  String _driverTrips = '0';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _pulseController.repeat(reverse: true);
  }

  int _stepFromStatus(String? status) {
    switch (status) {
      case 'searching': return 0;
      case 'accepted':  return 1;
      case 'arrived':   return 2;
      case 'ongoing':   return 3;
      case 'completed': return 4;
      default:          return 0;
    }
  }

  /// Pulls the assigned driver's name, plate and stats once per driver.
  /// Called from a post-frame callback so it never setStates during build.
  Future<void> _loadDriver(String driverId) async {
    _assignedDriverId = driverId;
    final user = await RideService.userInfo(driverId);
    final driver = await RideService.driverInfo(driverId);
    if (!mounted) return;
    setState(() {
      final first = user?['firstName'] ?? '';
      final last = user?['lastName'] ?? '';
      final name = '$first $last'.trim();
      _driverName = name.isEmpty ? '—' : name;
      _driverPlate = driver?['plateNo'] ?? '—';
      final rating = (driver?['rating'] ?? 0).toDouble();
      _driverRating = rating > 0 ? rating.toStringAsFixed(1) : '—';
      _driverTrips = '${driver?['totalRides'] ?? 0}';
    });
  }

  Future<void> _cancelRide() async {
    try {
      await RideService.cancelRide(widget.rideId);
      if (!mounted) return;
      Navigator.of(context).pop();
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

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String get _statusTitle {
    switch (_currentStep) {
      case 0: return 'Searching for Driver…';
      case 1: return 'Driver Found!';
      case 2: return 'Driver Arrived';
      case 3: return 'On Your Way!';
      case 4: return 'Trip Complete!';
      default: return '';
    }
  }

  String get _statusSub {
    switch (_currentStep) {
      case 0: return '🔍 Looking for available drivers in Polangui';
      case 1: return '🛺 Your driver is on the way';
      case 2: return '📍 Your driver is waiting at the pickup point';
      case 3: return '🗺️ Navigate to ${widget.destination}';
      case 4: return '✅ You have arrived at ${widget.destination}';
      default: return '';
    }
  }

  String get _etaText {
    switch (_currentStep) {
      case 0: return '—';
      case 1: return '3';
      case 2: return '0';
      case 3: return '5';
      case 4: return '✓';
      default: return '—';
    }
  }

  String get _etaLabel {
    switch (_currentStep) {
      case 0: return 'SEARCHING FOR DRIVER';
      case 1: return 'DRIVER ON THE WAY';
      case 2: return 'DRIVER ARRIVED';
      case 3: return 'EN ROUTE';
      case 4: return 'COMPLETED';
      default: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        // Leaving while still searching abandons the ride in Firestore
        // forever otherwise, since nothing else ever clears it. Best-effort:
        // the screen is already gone, so there's nowhere to surface a failure.
        if (_currentStep == 0) {
          RideService.cancelRide(widget.rideId).catchError((_) {});
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: RideService.watchRide(widget.rideId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary));
            }

            final ride = snapshot.data!.data() ?? {};
            // Status is the source of truth — the step is only a view of it.
            _currentStep = _stepFromStatus(ride['status'] as String?);

            final driverId = ride['driverId'] as String?;
            if (driverId != null && driverId != _assignedDriverId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _loadDriver(driverId);
              });
            }

            return _buildContent(context);
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(children: [
        // Step bar
        _buildStepBar(),
        // Status header
        _buildStatusHeader(),
        // Map
        Expanded(child: Stack(children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _polangui, initialZoom: 15,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.polamove.app'),
              MarkerLayer(markers: [
                Marker(point: _polangui, width: 36, height: 36,
                  child: Container(
                    decoration: BoxDecoration(color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 10)]),
                    child: const Center(child: Text('🛺', style: TextStyle(fontSize: 16)))),
                ),
              ]),
            ],
          ),
          // ETA chip
          Positioned(top: 10, right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1),
                      blurRadius: 10)]),
              child: Row(children: [
                const Text('⏱️', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                Text(_etaText == '✓' ? '✓' : '$_etaText min',
                    style: const TextStyle(fontFamily: 'Syne', fontSize: 13,
                        fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ]),
            ),
          ),
        ])),
        // Info panel
        _buildInfoPanel(context),
      ]);
  }

  Widget _buildStepBar() {
    return Container(
      color: AppColors.surface,
      child: SafeArea(bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: List.generate(_stepLabels.length * 2 - 1, (i) {
              if (i.isOdd) {
                final stepIndex = i ~/ 2;
                final filled = stepIndex < _currentStep;
                return Expanded(child: Container(height: 2.5,
                  color: filled ? AppColors.primary : AppColors.surfaceStrong));
              }
              final step = i ~/ 2;
              final active = step == _currentStep;
              final done = step < _currentStep;
              return Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(duration: const Duration(milliseconds: 300),
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : done ? AppColors.primaryDark : AppColors.surfaceAlt,
                    shape: BoxShape.circle,
                    border: Border.all(color: active ? AppColors.primary : done
                        ? AppColors.primaryDark : AppColors.border, width: 1.5),
                  ),
                  child: Center(child: Text(_stepEmojis[step],
                      style: const TextStyle(fontSize: 13)))),
                const SizedBox(height: 3),
                Text(_stepLabels[step], style: TextStyle(fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 0.3,
                    color: active ? AppColors.primary : done ? AppColors.primaryDark : AppColors.textTertiary)),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Container(
      color: AppColors.primary,
      child: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(1.0, -1.0), radius: 1.2,
              colors: [Color(0x1CFFFFFF), Colors.transparent])))),
        Padding(padding: const EdgeInsets.fromLTRB(15, 14, 15, 18),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(width: 31, height: 31,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white.withOpacity(0.2))),
                child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 20))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_statusTitle, style: const TextStyle(fontFamily: 'Syne', fontSize: 15,
                  fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 2),
              Text(_statusSub, style: TextStyle(fontSize: 11,
                  color: Colors.white.withOpacity(0.72))),
            ])),
          ]),
        ),
      ]),
    );
  }

  Widget _buildInfoPanel(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
              blurRadius: 20, offset: const Offset(0, -4))]),
      padding: EdgeInsets.fromLTRB(15, 14, 15, MediaQuery.of(context).padding.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Pull handle
        Center(child: Container(width: 34, height: 3.5,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: AppColors.surfaceStrong,
                borderRadius: BorderRadius.circular(2)))),
        // Driver card (shown after found)
        if (_currentStep >= 1) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 1.5)),
            child: Row(children: [
              Container(width: 46, height: 46,
                decoration: BoxDecoration(color: AppColors.primaryTint,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5)),
                child: const Center(child: Text('👨', style: TextStyle(fontSize: 22)))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_driverName, style: const TextStyle(fontFamily: 'Syne', fontSize: 14,
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text('🛺 $_driverPlate · Red Tricycle',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text('⭐ $_driverRating · $_driverTrips trips',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ])),
              // Call & chat buttons
              Row(children: [
                _ActionBtn(emoji: '📞', onTap: () {}),
                const SizedBox(width: 6),
                _ActionBtn(emoji: '💬', onTap: () {}),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        // ETA row
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_currentStep == 4 ? '✓' : _etaText,
                  style: const TextStyle(fontFamily: 'Syne', fontSize: 28,
                      fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              if (_currentStep != 4) ...[
                const SizedBox(width: 2),
                const Padding(padding: EdgeInsets.only(bottom: 4),
                    child: Text('min', style: TextStyle(fontSize: 12,
                        color: AppColors.textSecondary, fontWeight: FontWeight.w500))),
              ],
            ]),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_etaLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.textSecondary, letterSpacing: 0.5)),
            Text(_currentStep == 0 ? 'Looking for available drivers…' : widget.destination,
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                overflow: TextOverflow.ellipsis),
          ])),
          // Cancel or Done button
          if (_currentStep < 4)
            GestureDetector(
              onTap: _cancelRide,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: AppColors.border, width: 1.5)),
                child: const Text('Cancel', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700, color: AppColors.textSecondary)))),
          if (_currentStep == 4)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: AppColors.primary,
                    borderRadius: BorderRadius.circular(50)),
                child: const Text('Done', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700, color: Colors.white)))),
        ]),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;
  const _ActionBtn({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 36, height: 36,
        decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle,
            border: Border.all(color: AppColors.border, width: 1.5)),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 16)))),
    );
  }
}