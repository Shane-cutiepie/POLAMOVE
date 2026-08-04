import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
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

  static const LatLng _polangui = LatLng(13.2924, 123.4866);

  final _navItems = const [
    {'icon': '🏠', 'label': 'Home'},
    {'icon': '🕐', 'label': 'History'},
    {'icon': '🔔', 'label': 'Notifs'},
    {'icon': '👤', 'label': 'Profile'},
  ];

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

  Widget _buildBody() {
    switch (_currentNav) {
      case 0: return _buildHomePage();
      case 1: return const PassengerHistoryScreen();
      case 2: return const PassengerNotificationsScreen();
      case 3: return const PassengerProfileScreen();
      default: return _buildHomePage();
    }
  }

  // ── Home Page ─────────────────────────────────────
  Widget _buildHomePage() {
    return Column(children: [
      _buildTopBar(),
      Expanded(child: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _polangui, initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
          ),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.polamove.app'),
            MarkerLayer(markers: _buildDriverMarkers()),
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
                Text('4', style: TextStyle(fontFamily: 'Syne', fontSize: 19,
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
            onTap: () => _mapController.move(_polangui, 15),
            child: Container(width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1),
                      blurRadius: 8, offset: const Offset(0, 2))]),
              child: const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 18)),
          ),
        ),
      ])),
      _buildBottomSheet(),
    ]);
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
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Hi, Juan! 👋', style: TextStyle(fontFamily: 'Syne',
                      fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('Where to in Polangui today?',
                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.66))),
                ])),
                // Notification bell
                GestureDetector(
                  onTap: () => setState(() => _currentNav = 2),
                  child: Stack(children: [
                    Container(width: 37, height: 37,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: Colors.white.withOpacity(0.2))),
                      child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 18)),
                    Positioned(top: 6, right: 6,
                      child: Container(width: 7, height: 7,
                        decoration: BoxDecoration(color: const Color(0xFFFBBF24),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary, width: 1.5)))),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: Colors.white.withOpacity(0.2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('📍', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 5),
                  const Text('Polangui Centro', style: TextStyle(fontSize: 12,
                      color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withOpacity(0.8), size: 14),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Bottom Sheet ──────────────────────────────────
  Widget _buildBottomSheet() {
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
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BookingScreen())),
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
          _InfoChip(emoji: '🛺', value: '4 Free', label: 'Drivers'),
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
                AnimatedContainer(duration: const Duration(milliseconds: 200),
                  width: 38, height: 27,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primaryTint : Colors.transparent,
                    borderRadius: BorderRadius.circular(50)),
                  child: Center(child: Text(_navItems[i]['icon']!,
                      style: const TextStyle(fontSize: 17)))),
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
  List<Marker> _buildDriverMarkers() {
    final positions = [
      const LatLng(13.2934, 123.4856), const LatLng(13.2914, 123.4876),
      const LatLng(13.2944, 123.4886), const LatLng(13.2904, 123.4846),
    ];
    return positions.map((pos) => Marker(
      point: pos, width: 32, height: 32,
      child: Container(
        decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4),
                blurRadius: 8, offset: const Offset(0, 2))]),
        child: const Center(child: Text('🛺', style: TextStyle(fontSize: 14)))),
    )).toList();
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