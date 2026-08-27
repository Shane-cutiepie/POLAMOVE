import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/polangui_locations.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/ride_service.dart';
import '../shared/cancel_ride_sheet.dart';
import '../shared/chat_screen.dart';
import '../shared/user_avatar.dart';

class DriverTrackingScreen extends StatefulWidget {
  final String rideId;
  final String passengerName;
  final String from;
  final String to;
  final String rideType;
  final String fare;

  const DriverTrackingScreen({
    super.key,
    required this.rideId,
    required this.passengerName,
    required this.from,
    required this.to,
    required this.rideType,
    required this.fare,
  });

  @override
  State<DriverTrackingScreen> createState() => _DriverTrackingScreenState();
}

class _DriverTrackingScreenState extends State<DriverTrackingScreen> {
  int _step = 0; // 0=Heading to pickup, 1=Arrived, 2=Trip, 3=Done
  bool _busy = false;

  // Passenger avatar, fetched once per passenger from users/{uid}.
  String? _loadedPassengerId;
  int _passengerAvatarIndex = 0;
  String? _passengerAvatarUrl;

  // Set directly from the ride stream — unlike the avatar, chat doesn't need
  // to wait on an async lookup to know who the other party is.
  String? _passengerId;
  String? _rideStatus;

  final _stepTitles = [
    'Heading to Pickup',
    'Arrived at Pickup 📍',
    'Trip in Progress 🏁',
    'Trip Complete ✅',
  ];

  final _stepSubs = [
    '🗺️ Navigate to passenger',
    '⏳ Waiting for passenger to board',
    '🛣️ Driving to destination',
    '💰 Collect cash payment from passenger',
  ];

  final _stepBtnLabels = [
    '📍 I\'ve Arrived at Pickup',
    '🏁 Passenger Boarded — Start Trip',
    '✅ Trip Complete',
    '',
  ];

  Color get _statusColor {
    switch (_step) {
      case 0: return AppColors.primary;
      case 1: return const Color(0xFFB45309);
      case 2: return AppColors.success;
      case 3: return AppColors.primaryDark;
      default: return AppColors.primary;
    }
  }

  int _stepFromStatus(String? status) {
    switch (status) {
      case 'accepted':  return 0;
      case 'arrived':   return 1;
      case 'ongoing':   return 2;
      case 'completed': return 3;
      default:          return 0;
    }
  }

  /// Each button press moves the ride forward in Firestore; the step the
  /// screen shows follows from the document, never from local state.
  Future<void> _advanceStep(int step) async {
    setState(() => _busy = true);
    try {
      switch (step) {
        case 0:
          await RideService.markArrived(widget.rideId);
          break;
        case 1:
          await RideService.startTrip(widget.rideId);
          break;
        case 2:
          await RideService.completeRide(widget.rideId);
          break;
      }
    } on RideException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message, style: const TextStyle(fontFamily: 'DM Sans')),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reads the passenger's chosen preset avatar once per passenger. Called
  /// from a post-frame callback so it never setStates during build.
  Future<void> _loadPassengerAvatar(String passengerId) async {
    _loadedPassengerId = passengerId;
    final user = await RideService.userInfo(passengerId);
    if (!mounted) return;
    setState(() {
      _passengerAvatarIndex = (user?['avatarIndex'] ?? 0) as int;
      _passengerAvatarUrl = user?['avatarUrl'] as String?;
    });
  }

  void _openChat() {
    final passengerId = _passengerId;
    if (passengerId == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(
        rideId: widget.rideId,
        otherUid: passengerId,
        otherName: widget.passengerName,
        otherRole: 'passenger',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: RideService.watchRide(widget.rideId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final ride = snapshot.data!.data() ?? {};
          _rideStatus = ride['status'] as String?;
          _step = _stepFromStatus(_rideStatus);

          final passengerId = ride['passengerId'] as String?;
          _passengerId = passengerId;
          if (passengerId != null && passengerId != _loadedPassengerId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _loadPassengerAvatar(passengerId);
            });
          }

          return _buildContent(context);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(children: [
        // Status header
        _buildStatusHeader(),
        // Map
        Expanded(child: Stack(children: [
          FlutterMap(
            options: MapOptions(initialCenter: kPolanguiCentre, initialZoom: 15,
              interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag)),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.polamove.app'),
              MarkerLayer(markers: [
                Marker(point: kPolanguiCentre, width: 40, height: 40,
                  child: Container(
                    decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [BoxShadow(color: _statusColor.withOpacity(0.4),
                            blurRadius: 12)]),
                    child: const Center(child: Text('🛺', style: TextStyle(fontSize: 18))))),
                // Passenger marker
                if (_step == 0)
                  Marker(point: const LatLng(13.2934, 123.4876), width: 36, height: 36,
                    child: Container(
                      decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2)),
                      child: const Center(child: Text('🧍', style: TextStyle(fontSize: 16))))),
              ]),
            ],
          ),
        ])),
        // Info panel
        _buildInfoPanel(context),
      ]);
  }

  Widget _buildStatusHeader() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      color: _statusColor,
      child: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(1.0, -1.0), radius: 1.2,
              colors: [Color(0x1CFFFFFF), Colors.transparent])))),
        SafeArea(bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 18),
            child: Row(children: [
              GestureDetector(
                onTap: () => _step == 3 ? Navigator.of(context).pop() : _cancelRide(),
                child: Container(width: 31, height: 31,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white.withOpacity(0.2))),
                  child: Icon(_step == 3 ? Icons.check_rounded : Icons.chevron_left_rounded,
                      color: Colors.white, size: 20))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_stepTitles[_step], style: const TextStyle(fontFamily: 'Syne',
                    fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 2),
                Text(_stepSubs[_step], style: TextStyle(fontSize: 11,
                    color: Colors.white.withOpacity(0.72))),
              ])),
            ]),
          ),
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
        // Passenger card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 1.5)),
          child: Row(children: [
            Container(width: 46, height: 46,
              decoration: BoxDecoration(color: AppColors.primaryTint, shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5)),
              child: UserAvatar(avatarUrl: _passengerAvatarUrl,
                  avatarIndex: _passengerAvatarIndex, size: 46, emojiSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.passengerName, style: const TextStyle(fontFamily: 'Syne',
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text('${widget.rideType} · → ${widget.to}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text('Fare: ${widget.fare} · Cash',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ])),
            _ChatButton(rideId: widget.rideId, onTap: _openChat),
          ]),
        ),
        const SizedBox(height: 12),
        // Route display
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Column(children: [
              Container(width: 8, height: 8,
                  decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
              Container(width: 1.5, height: 18, color: AppColors.border),
              Container(width: 8, height: 8,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
            ]),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.from, style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              Text(widget.to, style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        // Action button
        if (_step < 3)
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : () => _advanceStep(_step),
              style: ElevatedButton.styleFrom(
                backgroundColor: _statusColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(_stepBtnLabels[_step], style: const TextStyle(
                  fontFamily: 'Syne', fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        if (_step == 3) ...[
          // Trip done summary
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.successTint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.success.withOpacity(0.3))),
            child: Row(children: [
              const Text('💰', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Collect ${widget.fare} from passenger',
                    style: const TextStyle(fontFamily: 'Syne', fontSize: 14,
                        fontWeight: FontWeight.w700, color: AppColors.success)),
                const SizedBox(height: 2),
                const Text('Cash payment only',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ])),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('Done — Back to Home 🏠', style: TextStyle(
                  fontFamily: 'Syne', fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _cancelRide() async {
    final cancelled = await showCancelRideSheet(context,
        rideId: widget.rideId, role: 'driver', status: _rideStatus);
    if (cancelled && mounted) Navigator.of(context).pop();
  }
}

/// Chat entry point on the passenger card, with a small unread-message dot
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