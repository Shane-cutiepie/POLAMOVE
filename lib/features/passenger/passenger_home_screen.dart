import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/polangui_locations.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/message_alert_service.dart';
import '../../core/services/ride_service.dart';
import '../../core/services/sound_service.dart';
import '../shared/animated_map_marker.dart';
import '../shared/location_picker_sheet.dart';
import '../shared/research_disclosure_screen.dart';
import 'booking_screen.dart';
import 'passenger_history_screen.dart';
import 'passenger_notifications_screen.dart';
import 'passenger_profile_screen.dart';

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  int _currentNav = 0;
  final MapController _mapController = MapController();

  static final Distance _distance = const Distance();
  static const double _nearbyRadiusMeters = 3000;

  /// The passenger's chosen pickup point. Not a GPS position — this app does
  /// not track passenger location. Defaults to the town centre.
  String _pickupLocation = 'Polangui Municipal Hall';

  final _navItems = const [
    {'icon': '🏠', 'label': 'Home'},
    {'icon': '🕐', 'label': 'History'},
    {'icon': '🔔', 'label': 'Notifs'},
    {'icon': '👤', 'label': 'Profile'},
  ];

  @override
  void initState() {
    super.initState();
    SoundService.loadPreference();
    MessageAlertService.start();
    ResearchDisclosureScreen.maybeShow(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        Expanded(child: _buildBody()),
        _buildBottomNav(),
      ]),
    );
  }

  /// Back button target for the tab screens, which have no route to pop.
  void _goHome() => setState(() => _currentNav = 0);

  Widget _buildBody() {
    switch (_currentNav) {
      case 0: return _buildHomePage();
      case 1: return PassengerHistoryScreen(onBack: _goHome);
      case 2: return PassengerNotificationsScreen(onBack: _goHome);
      case 3: return PassengerProfileScreen(onBack: _goHome);
      default: return _buildHomePage();
    }
  }

  // ── Home Page ─────────────────────────────────────
  Widget _buildHomePage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: RideService.onlineDrivers(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final nearby = _nearbyCount(docs);

        return Column(children: [
          _buildTopBar(),
          Expanded(child: Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: kPolanguiCentre, initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.polamove.app'),
                // Each driver marker animates independently (see
                // AnimatedMapMarker), so they're placed directly as map
                // children rather than inside one MarkerLayer's static list.
                // Pickup marker last so it draws on top — the passenger's own
                // pickup point must never be hidden behind a tricycle.
                ..._buildDriverMarkers(docs),
                MarkerLayer(markers: [_buildPickupMarker()]),
              ],
            ),
            // Nearby drivers chip
            Positioned(top: 10, right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border, width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12),
                        blurRadius: 12, offset: const Offset(0, 4))]),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$nearby', style: const TextStyle(fontFamily: 'Syne', fontSize: 19,
                        fontWeight: FontWeight.w800, color: AppColors.primaryLight)),
                    Text('Nearby', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary, letterSpacing: 0.3)),
                  ]),
                  const SizedBox(width: 7),
                  const Text('🛺', style: TextStyle(fontSize: 20)),
                ]),
              ),
            ),
            // Recenter button
            Positioned(bottom: 10, right: 10,
              child: GestureDetector(
                onTap: () => _mapController.move(locationFor(_pickupLocation), 15),
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 1.5),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1),
                          blurRadius: 8, offset: const Offset(0, 2))]),
                  child: const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 18)),
              ),
            ),
          ])),
          _buildBottomSheet(nearby),
        ]);
      },
    );
  }

  // ── Top Bar ───────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: AppColors.primary,
      child: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0.95, -1.0), radius: 1.2,
              colors: [Color(0x1CFFFFFF), Colors.transparent])))),
        SafeArea(bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 44),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Greeting spans the full width — the notification bell that
              // used to sit on the right duplicated the Notifs tab's badge.
              SizedBox(width: double.infinity,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: AuthService.userStream(
                        FirebaseAuth.instance.currentUser!.uid),
                    builder: (context, snapshot) {
                      final first =
                          snapshot.data?.data()?['firstName']?.toString() ?? '';
                      return Text(first.isEmpty ? 'Hi! 👋' : 'Hi, $first! 👋',
                          style: const TextStyle(fontFamily: 'Syne',
                              fontSize: 20, fontWeight: FontWeight.w800,
                              color: Colors.white));
                    },
                  ),
                  const SizedBox(height: 2),
                  Text('Where to in Polangui today?',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.66))),
                ]),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _changePickup,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.white.withOpacity(0.2))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('📍', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 5),
                    Text(_pickupLocation, style: const TextStyle(fontSize: 12,
                        color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white.withOpacity(0.8), size: 14),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Bottom Sheet ──────────────────────────────────
  Widget _buildBottomSheet(int nearbyCount) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1),
              blurRadius: 20, offset: const Offset(0, -4))]),
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 6),
      child: Column(children: [
        Center(child: Container(width: 34, height: 3.5,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: AppColors.surfaceStrong,
                borderRadius: BorderRadius.circular(3)))),
        GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => BookingScreen(initialPickup: _pickupLocation))),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border, width: 1.5)),
            child: Row(children: [
              const Text('🛺', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(child: Text('Where are you going?',
                  style: TextStyle(fontSize: 13, color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500))),
              Icon(Icons.chevron_right_rounded, color: AppColors.primaryLight, size: 20),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _InfoChip(emoji: '💰', value: '₱10–₱25', label: 'Est. fare'),
          const SizedBox(width: 6),
          _InfoChip(emoji: '⏱️', value: '2–5 min', label: 'ETA'),
          const SizedBox(width: 6),
          _InfoChip(emoji: '🛺',
              value: nearbyCount == 0 ? 'None' : '$nearbyCount Free',
              label: 'Drivers'),
        ]),
        const SizedBox(height: 6),
      ]),
    );
  }

  // ── Bottom Nav ────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border))),
      padding: EdgeInsets.only(top: 5,
          bottom: MediaQuery.of(context).padding.bottom + 8),
      child: Row(
        children: List.generate(_navItems.length, (i) {
          final active = _currentNav == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentNav = i),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Stack(clipBehavior: Clip.none, children: [
                  AnimatedContainer(duration: const Duration(milliseconds: 200),
                    width: 38, height: 27,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primaryTint : Colors.transparent,
                      borderRadius: BorderRadius.circular(50)),
                    child: Center(child: Text(_navItems[i]['icon']!,
                        style: const TextStyle(fontSize: 17)))),
                  if (_navItems[i]['label'] == 'Notifs')
                    const Positioned(top: -2, right: 0, child: _UnreadBadge()),
                ]),
                const SizedBox(height: 2),
                Text(_navItems[i]['label']!, style: TextStyle(fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: active ? AppColors.primaryLight : AppColors.textTertiary,
                    letterSpacing: 0.3)),
              ]),
            ),
          );
        }),
      ),
    );
  }

  // ── Driver markers ────────────────────────────────
  /// Keyed by the driver's uid (the document id from `onlineDrivers()`) so
  /// each driver keeps its own AnimatedMapMarker state — without a key,
  /// Flutter would match markers by list position, and a reorder (a driver
  /// going offline, a new one appearing) would hand one driver's in-flight
  /// animation to another.
  List<Widget> _buildDriverMarkers(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final markers = <Widget>[];
    for (final d in docs) {
      final loc = d.data()['location'];
      if (loc is! GeoPoint) continue;
      markers.add(AnimatedMapMarker(
        key: ValueKey(d.id),
        target: LatLng(loc.latitude, loc.longitude),
        width: 32, height: 32,
        builder: (context, pos) => Container(
          decoration: BoxDecoration(
            color: AppColors.primary, shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4),
                blurRadius: 8, offset: const Offset(0, 2))]),
          child: const Center(child: Text('🛺', style: TextStyle(fontSize: 14)))),
      ));
    }
    return markers;
  }

  /// The passenger's selected pickup point — a named place, never a device
  /// position. Green against the drivers' red 🛺 pins so "where I'm picked up"
  /// reads apart from "a tricycle" at a glance.
  Marker _buildPickupMarker() {
    return Marker(
      point: locationFor(_pickupLocation),
      width: 36, height: 36,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.success, shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [BoxShadow(color: AppColors.success.withOpacity(0.4),
              blurRadius: 10)]),
        child: const Center(child: Text('📍', style: TextStyle(fontSize: 16)))),
    );
  }

  /// Opens the shared picker and recentres on the chosen place. No permission
  /// prompt and no GPS — the passenger picks from the named Polangui locations.
  Future<void> _changePickup() async {
    final result = await showLocationPicker(context, 'Set Pickup Location');
    if (result == null || !mounted) return;
    setState(() => _pickupLocation = result);
    _mapController.move(locationFor(result), 15);
  }

  /// Drivers further out than this from the chosen pickup are online but not
  /// usefully "nearby", so they aren't advertised on the home screen. Measured
  /// from the pickup point, not the town centre — a passenger picked up on
  /// the other side of town cares about drivers near them, not near centro.
  int _nearbyCount(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final origin = locationFor(_pickupLocation);
    var count = 0;
    for (final d in docs) {
      final loc = d.data()['location'];
      if (loc is! GeoPoint) continue;
      final metres = _distance.as(LengthUnit.Meter,
          origin, LatLng(loc.latitude, loc.longitude));
      if (metres <= _nearbyRadiusMeters) count++;
    }
    return count;
  }
}

/// Live unread notification count, shown on the bottom-nav Notifs tab. Grows
/// only enough to fit a digit.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();

        return Container(
          constraints: const BoxConstraints(minWidth: 14),
          height: 14,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFFBBF24),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
          child: Center(
            child: Text(count > 9 ? '9+' : '$count',
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary, height: 1)),
          ),
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _InfoChip({required this.emoji, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
            Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textTertiary)),
          ])),
        ]),
      ),
    );
  }
}