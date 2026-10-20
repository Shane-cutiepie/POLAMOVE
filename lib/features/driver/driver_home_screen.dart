import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/polangui_locations.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/message_alert_service.dart';
import '../../core/services/ride_service.dart';
import '../../core/services/sound_service.dart';
import '../../core/utils/map_platform.dart';
import '../shared/location_rationale_sheet.dart';
import '../shared/research_disclosure_screen.dart';
import 'driver_tracking_screen.dart';
import 'driver_history_screen.dart';
import 'driver_notifications_screen.dart';
import 'driver_profile_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with TickerProviderStateMixin {
  int _currentNav = 0;
  bool _isOnline = false;
  bool _hasRequest = false;
  String _driverStatus = 'pending';
  bool _statusLoaded = false;
  String _firstName = '';
  late AnimationController _requestController;
  late Animation<Offset> _requestSlide;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  final MapController _mapController = MapController();
  gmaps.GoogleMapController? _googleMapController;

  // All-time totals, mirrored from the drivers/{uid} document.
  double _totalEarnings = 0;
  int _totalRides = 0;

  // Live incoming request
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _requestSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  StreamSubscription<String>? _locationErrorSub;
  String? _requestRideId;
  Map<String, dynamic>? _requestData;
  String _requestPassengerName = '—';

  /// Rides this driver has declined. Session-only: they'll see it again next
  /// time they go online, which is intended — another driver may have
  /// declined it too and the passenger is still waiting.
  final Set<String> _declinedRideIds = {};

  @override
  void initState() {
    super.initState();
    _requestController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _requestSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _requestController, curve: Curves.easeOutCubic),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _watchDriverStatus();
    _locationErrorSub = LocationService.trackingErrors.listen(
      _takeOfflineAfterLocationError,
    );
    _loadFirstName();
    SoundService.loadPreference();
    MessageAlertService.start();
    ResearchDisclosureScreen.maybeShow(context);
  }

  /// Live rather than a one-off read, so an admin approving the account flips
  /// the Go Online toggle on without the driver restarting the app.
  void _watchDriverStatus() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _statusSub = AuthService.driverStream(uid).listen(
      (doc) {
        final data = doc.data();
        if (!mounted) return;
        final resumeLocation = !_statusLoaded && data?['isOnline'] == true;
        setState(() {
          _driverStatus = data?['status'] ?? 'pending';
          _isOnline = data?['isOnline'] ?? false;
          // completeRide() increments both, so the top bar updates itself
          // the moment a trip finishes.
          _totalEarnings = (data?['totalEarnings'] ?? 0).toDouble();
          _totalRides = (data?['totalRides'] ?? 0).toInt();
          _statusLoaded = true;
        });
        if (resumeLocation) _resumeLocationTracking();
        // Keep the booking feed in step with what the database says.
        if (_isOnline) {
          _subscribeToRequests();
        } else {
          _unsubscribeFromRequests();
        }
      },
      onError: (_) {
        if (mounted) setState(() => _statusLoaded = true);
      },
    );
  }

  Future<void> _loadFirstName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted) return;
      setState(() => _firstName = doc.data()?['firstName'] ?? '');
    } catch (_) {}
  }

  void _subscribeToRequests() {
    if (_requestSub != null) return;
    // A freshly-attached listener fires immediately with every ride already
    // searching. That first delivery must stay silent — only requests that
    // arrive after this driver is already watching should chime. Scoped to
    // this subscription (not an instance field) so going offline and back
    // online starts a fresh "first snapshot" each time.
    var isFirstSnapshot = true;
    _requestSub = RideService.searchingRides().listen((snap) async {
      final playSound = !isFirstSnapshot;
      isFirstSnapshot = false;

      if (!mounted) return;

      // The ride currently on screen vanished — another driver accepted
      // it, or the passenger cancelled. Drop it silently and fall through
      // to look for a replacement in this same snapshot.
      if (_hasRequest &&
          _requestRideId != null &&
          !snap.docs.any((d) => d.id == _requestRideId)) {
        _clearRequest();
      }

      // Leave the card alone while the driver is deciding on one.
      if (_hasRequest) return;

      final doc = _firstUndeclined(snap.docs);
      if (doc == null) {
        _clearRequest();
        return;
      }
      final data = doc.data();
      final passengerId = data['passengerId'] as String?;
      final user =
          passengerId == null ? null : await RideService.userInfo(passengerId);
      if (!mounted) return;

      final name =
          '${user?['firstName'] ?? ''} ${user?['lastName'] ?? ''}'.trim();
      _requestRideId = doc.id;
      _requestData = data;
      _requestPassengerName = name.isEmpty ? '—' : name;

      setState(() => _hasRequest = true);
      _requestController.forward();

      if (playSound &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        SoundService.rideAlert();
      }
    }, onError: (_) {});
  }

  void _unsubscribeFromRequests() {
    _requestSub?.cancel();
    _requestSub = null;
    _clearRequest();
  }

  /// Oldest-first order is preserved from the query — this just skips over
  /// rides the driver has already said no to this session.
  QueryDocumentSnapshot<Map<String, dynamic>>? _firstUndeclined(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final doc in docs) {
      if (!_declinedRideIds.contains(doc.id)) return doc;
    }
    return null;
  }

  void _clearRequest() {
    _requestRideId = null;
    _requestData = null;
    _requestPassengerName = '—';
    if (_hasRequest && mounted) setState(() => _hasRequest = false);
    _requestController.reset();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _requestSub?.cancel();
    _locationErrorSub?.cancel();
    LocationService.stopTracking();
    _requestController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleOnline() async {
    if (_driverStatus != 'approved') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _driverStatus == 'rejected'
                ? 'Your application was not approved. Please contact the administrator.'
                : 'Your application is still under review. You can go online once approved.',
            style: const TextStyle(fontFamily: 'DM Sans'),
          ),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    final next = !_isOnline;

    if (next) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final cooldown =
          uid == null ? null : await RideService.activeCooldown(uid);
      if (cooldown != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Your bookings are paused until ${_formatCooldownTime(cooldown)} because of repeated cancellations.',
                style: const TextStyle(fontFamily: 'DM Sans'),
              ),
              backgroundColor: AppColors.primaryDark,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }

      // A rationale for a permission already granted would just be noise —
      // only show it ahead of the system dialog the first time.
      if (!await LocationService.hasPermission()) {
        if (!mounted) return;
        final proceed = await showLocationRationaleSheet(context);
        // Dismissed without tapping Continue: stay offline, and don't touch
        // the system permission dialog at all.
        if (!proceed) return;
      }
      try {
        await LocationService.startTracking();
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .update({'isOnline': true});
      } catch (error) {
        await LocationService.stopTracking();
        try {
          await LocationService.clearLocation();
        } catch (_) {
          // Keep the original sign-in/GPS error visible below.
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error.toString().replaceFirst('Bad state: ', ''),
                style: const TextStyle(fontFamily: 'DM Sans'),
              ),
              backgroundColor: AppColors.primaryDark,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }
      if (mounted) setState(() => _isOnline = true);
      _subscribeToRequests();
    } else {
      try {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .update({'isOnline': false});
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not go offline: $error',
                style: const TextStyle(fontFamily: 'DM Sans'),
              ),
              backgroundColor: AppColors.primaryDark,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }
      if (mounted) setState(() => _isOnline = false);
      await LocationService.stopTracking();
      try {
        await LocationService.clearLocation();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You are offline, but your last map position could not be cleared: $error',
                style: const TextStyle(fontFamily: 'DM Sans'),
              ),
              backgroundColor: AppColors.primaryDark,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
      _unsubscribeFromRequests();
    }
  }

  Future<void> _resumeLocationTracking() async {
    try {
      await LocationService.startTracking();
    } catch (error) {
      await _takeOfflineAfterLocationError(
        error.toString().replaceFirst('Bad state: ', ''),
      );
    }
  }

  Future<void> _takeOfflineAfterLocationError(String message) async {
    await LocationService.stopTracking();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      if (uid != null) {
        await FirebaseFirestore.instance.collection('drivers').doc(uid).update({
          'isOnline': false,
        });
      }
      await LocationService.clearLocation();
    } catch (error) {
      message = '$message Could not update your online status: $error';
    }
    if (!mounted) return;
    setState(() => _isOnline = false);
    _unsubscribeFromRequests();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _acceptRide() async {
    final rideId = _requestRideId;
    if (rideId == null) return;
    // Held locally: accepting drops the ride out of the searching feed, and
    // that listener clears _requestData before the push below runs.
    final data = _requestData;
    final passengerName = _requestPassengerName;
    try {
      await RideService.acceptRide(rideId);
      if (!mounted) return;
      setState(() => _hasRequest = false);
      _requestController.reset();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => DriverTrackingScreen(
                rideId: rideId,
                passengerName: passengerName,
                from: data?['pickup']?['name'] ?? '—',
                to: data?['dropoff']?['name'] ?? '—',
                rideType: data?['rideType'] ?? '—',
                fare: '₱${(data?['totalFare'] ?? 0).toStringAsFixed(0)}',
              ),
        ),
      );
    } on RideException catch (e) {
      if (!mounted) return;
      setState(() => _hasRequest = false);
      _requestController.reset();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message,
            style: const TextStyle(fontFamily: 'DM Sans'),
          ),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _declineRide() {
    if (_requestRideId != null) _declinedRideIds.add(_requestRideId!);
    setState(() => _hasRequest = false);
    _requestController.reset();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Booking declined.'),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [Expanded(child: _buildBody()), _buildBottomNav()],
      ),
    );
  }

  /// Back button target for the tab screens, which have no route to pop.
  void _goHome() => setState(() => _currentNav = 0);

  // IndexedStack keeps the Home map and its camera position alive across tabs.
  Widget _buildBody() {
    return IndexedStack(
      index: _currentNav,
      children: [
        _buildHomePage(),
        DriverHistoryScreen(onBack: _goHome),
        DriverNotificationsScreen(onBack: _goHome),
        DriverProfileScreen(onBack: _goHome),
      ],
    );
  }

  Widget _buildHomePage() {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: Stack(
            children: [
              // Map
              _buildMap(),
              // Status pill (top left)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color:
                        _isOnline ? AppColors.success : AppColors.textSecondary,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isOnline ? 'Online' : 'Offline',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Recenter button
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () {
                    if (usesGoogleMaps) {
                      _googleMapController?.animateCamera(
                        gmaps.CameraUpdate.newLatLngZoom(
                          gmaps.LatLng(
                            kPolanguiCentre.latitude,
                            kPolanguiCentre.longitude,
                          ),
                          15,
                        ),
                      );
                    } else {
                      _mapController.move(kPolanguiCentre, 15);
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                ),
              ),
              // Incoming request card
              if (_hasRequest)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SlideTransition(
                    position: _requestSlide,
                    child: _buildRequestCard(),
                  ),
                ),
              // No request / offline hint
              if (!_hasRequest)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildStatusHint(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    if (usesGoogleMaps) {
      return gmaps.GoogleMap(
        initialCameraPosition: gmaps.CameraPosition(
          target: gmaps.LatLng(
            kPolanguiCentre.latitude,
            kPolanguiCentre.longitude,
          ),
          zoom: 15,
        ),
        onMapCreated: (controller) => _googleMapController = controller,
        markers: {
          gmaps.Marker(
            markerId: const gmaps.MarkerId('driver'),
            position: gmaps.LatLng(
              kPolanguiCentre.latitude,
              kPolanguiCentre.longitude,
            ),
            infoWindow: const gmaps.InfoWindow(title: 'Your location'),
          ),
        },
        zoomControlsEnabled: false,
        myLocationButtonEnabled: false,
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: kPolanguiCentre,
        initialZoom: 15,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.polamove.app',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: kPolanguiCentre,
              width: 44,
              height: 44,
              child: ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        _isOnline ? AppColors.primary : AppColors.textTertiary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: (_isOnline
                                ? AppColors.primary
                                : AppColors.textTertiary)
                            .withValues(alpha: 0.4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('🛺', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Top Bar ───────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: AppColors.primary,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.95, -1.0),
                  radius: 1.2,
                  colors: [Color(0x1CFFFFFF), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Column(
                children: [
                  // Name row. The notification bell that used to sit on the right
                  // duplicated the Notifs tab's badge, so it was removed.
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _firstName.isEmpty
                                  ? 'Hi! 🛺'
                                  : 'Hi, $_firstName! 🛺',
                              style: const TextStyle(
                                fontFamily: 'Syne',
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Polangui Tricycle Driver',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.66),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Online/Offline toggle + Earnings row
                  Row(
                    children: [
                      // Toggle pill
                      GestureDetector(
                        onTap: _toggleOnline,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _isOnline
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: _isOnline ? 1.0 : 0.3,
                              ),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 28,
                                height: 16,
                                decoration: BoxDecoration(
                                  color:
                                      _isOnline
                                          ? AppColors.success
                                          : AppColors.textTertiary,
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: AnimatedAlign(
                                  duration: const Duration(milliseconds: 300),
                                  alignment:
                                      _isOnline
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    margin: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isOnline ? 'Online' : 'Go Online',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      _isOnline
                                          ? AppColors.primary
                                          : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Earnings
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '₱${_totalEarnings.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontFamily: 'Syne',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Earnings',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white.withValues(alpha: 0.66),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              width: 1,
                              height: 28,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '$_totalRides',
                                  style: const TextStyle(
                                    fontFamily: 'Syne',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Trips',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white.withValues(alpha: 0.66),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Incoming Request Card ─────────────────────────
  Widget _buildRequestCard() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                const Text('🚖', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _requestData?['rideType'] ?? '—',
                        style: const TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        '0.8 km away',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₱${(_requestData?['totalFare'] ?? 0).toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          // Route
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(width: 1.5, height: 22, color: AppColors.border),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _requestData?['pickup']?['name'] ?? '—',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _requestData?['dropoff']?['name'] ?? '—',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Cash notice
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Text('💵', style: TextStyle(fontSize: 13)),
                SizedBox(width: 8),
                Text(
                  'Please collect cash payment from passenger',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Accept / Decline buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _declineRide,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: const BorderSide(
                        color: Color(0x1C14142A),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      '✗ Decline',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _acceptRide,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '✓ Accept Ride',
                      style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Status Hint ───────────────────────────────────
  Widget _buildStatusHint() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        children: [
          Text(
            _driverStatus != 'approved' ? '📋' : (_isOnline ? '🔍' : '😴'),
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _driverStatus != 'approved'
                      ? 'Application under review'
                      : (_isOnline
                          ? 'Waiting for bookings…'
                          : 'You are offline'),
                  style: const TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _driverStatus != 'approved'
                      ? 'The admin is reviewing your documents. You\'ll be notified once approved.'
                      : (_isOnline
                          ? 'You\'ll be notified when a passenger books a ride'
                          : 'Tap "Go Online" to start accepting bookings'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Nav ────────────────────────────────────
  Widget _buildBottomNav() {
    final items = [
      {'icon': '🏠', 'label': 'Home'},
      {'icon': '🕐', 'label': 'History'},
      {'icon': '🔔', 'label': 'Notifs'},
      {'icon': '👤', 'label': 'Profile'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.only(
        top: 5,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final active = _currentNav == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentNav = i),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 38,
                        height: 27,
                        decoration: BoxDecoration(
                          color:
                              active
                                  ? AppColors.primaryTint
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Center(
                          child: Text(
                            items[i]['icon']!,
                            style: const TextStyle(fontSize: 17),
                          ),
                        ),
                      ),
                      if (items[i]['label'] == 'Notifs')
                        const Positioned(
                          top: -2,
                          right: 0,
                          child: _UnreadBadge(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i]['label']!,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color:
                          active
                              ? AppColors.primaryLight
                              : AppColors.textTertiary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

String _formatCooldownTime(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:${d.minute.toString().padLeft(2, '0')} $period';
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
      stream:
          FirebaseFirestore.instance
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
            child: Text(
              count > 9 ? '9+' : '$count',
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1,
              ),
            ),
          ),
        );
      },
    );
  }
}
