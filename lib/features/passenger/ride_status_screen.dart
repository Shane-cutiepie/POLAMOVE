import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/polangui_locations.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/ride_service.dart';
import '../../core/services/sound_service.dart';
import '../shared/animated_map_marker.dart';
import '../shared/cancel_ride_sheet.dart';
import '../shared/chat_screen.dart';
import '../shared/user_avatar.dart';

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

  final _stepLabels = ['Search', 'Found', 'Arrived', 'Trip', 'Done'];
  final _stepEmojis = ['🔍', '🛺', '📍', '🏁', '✅'];

  // Driver details, fetched once when a driver is assigned to the ride
  String? _assignedDriverId;
  String _driverName = '—';
  String _driverPlate = '—';
  String _driverTrips = '0';
  int _driverAvatarIndex = 0;
  String? _driverAvatarUrl;

  // Set directly from the ride stream, for the cancel sheet's fee logic.
  String? _rideStatus;

  final MapController _mapController = MapController();
  static final Distance _distance = const Distance();

  /// Beyond this from the map's current centre, the driver has drifted far
  /// enough off-screen to be worth recentring for.
  static const double _recentreThresholdMeters = 200;

  // Firestore's .snapshots() returns a new Stream instance on every call, so
  // this is cached per driverId rather than created inline in build() —
  // otherwise every unrelated ride-document change (a status update, a
  // field write) would tear down and re-subscribe this stream, dropping the
  // last known driver position and re-triggering the map for no reason.
  String? _driverStreamDriverId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _driverLocationStream;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _watchDriverLocation(
      String? driverId) {
    if (driverId == null) return null;
    if (_driverStreamDriverId != driverId) {
      _driverStreamDriverId = driverId;
      _driverLocationStream = FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .snapshots();
    }
    return _driverLocationStream;
  }

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
      _driverTrips = '${driver?['totalRides'] ?? 0}';
      _driverAvatarIndex = (user?['avatarIndex'] ?? 0) as int;
      _driverAvatarUrl = user?['avatarUrl'] as String?;
    });
  }

  void _openChat() {
    final driverId = _assignedDriverId;
    if (driverId == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        rideId: widget.rideId,
        otherUid: driverId,
        otherName: _driverName,
        otherRole: 'driver',
      ),
    ));
  }

  Future<void> _cancelRide() async {
    final cancelled = await showCancelRideSheet(context,
        rideId: widget.rideId, role: 'passenger', status: _rideStatus);
    if (cancelled && mounted) Navigator.of(context).pop();
  }

  /// Recentres on the driver once they've drifted more than ~200 m from
  /// what's currently on screen — far enough to have wandered off the
  /// visible map. Checked against the real driver position, not the
  /// animated marker: the animated marker can lag it by up to the ~1.2 s
  /// animation duration, so checking that instead would recentre a beat
  /// late and fight the animation still catching up.
  ///
  /// Comparing against the map's *current* centre (rather than tracking the
  /// last recentre point separately) is what keeps this from firing on
  /// every position update: after a recentre, the centre itself becomes the
  /// driver's position, so the next 200 m has to accumulate again before
  /// another one fires — small per-update drift alone never crosses the
  /// threshold. A user who has panned away is measured from wherever they
  /// panned to, same as anyone else.
  ///
  /// Deferred to a post-frame callback because it's reached from within
  /// build() (the driver-location StreamBuilder below), and
  /// MapController.move() notifies its listeners synchronously — calling it
  /// mid-build risks a "setState during build" error.
  void _maybeRecentreOnDriver(LatLng driverPos) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final metres = _distance.as(
          LengthUnit.Meter, _mapController.camera.center, driverPos);
      if (metres > _recentreThresholdMeters) {
        _mapController.move(driverPos, _mapController.camera.zoom);
      }
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
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
          RideService.cancelRide(widget.rideId, reason: 'changed_mind')
              .catchError((_) {});
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
            // Read the previous value before overwriting it: comparing the
            // two is both the transition check below and, for free, the
            // initial-snapshot guard — _rideStatus starts null, so the very
            // first delivery (including one that opens straight onto an
            // already-accepted ride) never reads as "just left searching".
            final previousStatus = _rideStatus;
            _rideStatus = ride['status'] as String?;
            _currentStep = _stepFromStatus(_rideStatus);

            if (previousStatus == 'searching' && _rideStatus == 'accepted') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    WidgetsBinding.instance.lifecycleState ==
                        AppLifecycleState.resumed) {
                  SoundService.rideAlert();
                }
              });
            }

            final driverId = ride['driverId'] as String?;
            if (driverId != null && driverId != _assignedDriverId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _loadDriver(driverId);
              });
            }

            return _buildContent(context, driverId);
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, String? driverId) {
    return Column(children: [
        // Step bar
        _buildStepBar(),
        // Status header
        _buildStatusHeader(),
        // Map
        Expanded(child: Stack(children: [
          // Driver's live location, from drivers/{driverId} — no driver
          // assigned yet (still searching) falls back to the town centre,
          // matching the marker's old fixed position.
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _watchDriverLocation(driverId) ??
                const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty(),
            builder: (context, driverSnap) {
              final loc = driverSnap.data?.data()?['location'];
              // Real (non-interpolated) position, used both as the marker's
              // animation target and for the recentre check below — kept
              // null rather than falling back to kPolanguiCentre so "no
              // driver position yet" doesn't look like a real, on-target
              // driver.
              final driverPos =
                  loc is GeoPoint ? LatLng(loc.latitude, loc.longitude) : null;
              if (driverPos != null) _maybeRecentreOnDriver(driverPos);

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: kPolanguiCentre, initialZoom: 15,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.polamove.app'),
                  AnimatedMapMarker(
                    target: driverPos ?? kPolanguiCentre, width: 36, height: 36,
                    builder: (context, pos) => Container(
                      decoration: BoxDecoration(color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 10)]),
                      child: const Center(child: Text('🛺', style: TextStyle(fontSize: 16)))),
                  ),
                ],
              );
            },
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
                child: UserAvatar(avatarUrl: _driverAvatarUrl,
                    avatarIndex: _driverAvatarIndex, size: 46, emojiSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_driverName, style: const TextStyle(fontFamily: 'Syne', fontSize: 14,
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text('🛺 $_driverPlate · Red Tricycle',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text('🛺 $_driverTrips trips',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ])),
              _ChatButton(rideId: widget.rideId, onTap: _openChat),
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

/// Chat entry point on the driver card, with a small unread-message dot
/// positioned the same way as the bottom-nav Notifs tab badge.
class _ChatButton extends StatelessWidget {
  final String rideId;
  final VoidCallback onTap;
  const _ChatButton({required this.rideId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return GestureDetector(
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 1.5)),
          child: const Center(child: Text('💬', style: TextStyle(fontSize: 16)))),
        if (uid != null)
          Positioned(top: -2, right: -2, child: StreamBuilder<int>(
            stream: ChatService.unreadCount(rideId, uid),
            builder: (context, snapshot) {
              if ((snapshot.data ?? 0) == 0) return const SizedBox.shrink();
              return Container(width: 10, height: 10,
                decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 1.5)));
            },
          )),
      ]),
    );
  }
}