import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';

class DriverTrackingScreen extends StatefulWidget {
  final String passengerName;
  final String from;
  final String to;
  final String rideType;
  final String fare;

  const DriverTrackingScreen({
    super.key,
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

  static const LatLng _polangui = LatLng(13.2924, 123.4866);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        // Status header
        _buildStatusHeader(),
        // Map
        Expanded(child: Stack(children: [
          FlutterMap(
            options: MapOptions(initialCenter: _polangui, initialZoom: 15,
              interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag)),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.polamove.app'),
              MarkerLayer(markers: [
                Marker(point: _polangui, width: 40, height: 40,
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
      ]),
    );
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
                onTap: () => _step == 3 ? Navigator.of(context).pop() : _showCancelDialog(),
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
              child: const Center(child: Text('🧍', style: TextStyle(fontSize: 22)))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.passengerName, style: const TextStyle(fontFamily: 'Syne',
                  fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text('${widget.rideType} · → ${widget.to}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text('Fare: ${widget.fare} · Cash',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ])),
            Row(children: [
              _ActionBtn(emoji: '📞', onTap: () {}),
              const SizedBox(width: 6),
              _ActionBtn(emoji: '💬', onTap: () {}),
            ]),
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
              onPressed: () => setState(() => _step++),
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

  void _showCancelDialog() {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.surfaceStrong,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),
          const Text('❌', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          const Text('Cancel Trip?', style: TextStyle(fontFamily: 'Syne', fontSize: 18,
              fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('Are you sure you want to cancel this ride?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 22),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0),
              child: const Text('Yes, Cancel Trip', style: TextStyle(fontFamily: 'Syne',
                  fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: Color(0x1C14142A), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: const Text('Keep Ride', style: TextStyle(fontFamily: 'DM Sans',
                  fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
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
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 16)))));
  }
}