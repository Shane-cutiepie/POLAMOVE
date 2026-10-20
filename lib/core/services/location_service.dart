import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

/// Writes the signed-in driver's position to `drivers/{uid}.location` while
/// they are online, so passengers can see real tricycles on the map.
///
/// Only runs while the driver is online — tracking a driver who isn't taking
/// bookings would drain their battery and their data for nothing.
class LocationService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static StreamSubscription<Position>? _sub;
  static final _trackingErrors = StreamController<String>.broadcast();
  static bool _hasReportedStreamError = false;

  static Stream<String> get trackingErrors => _trackingErrors.stream;
  static const _maxLocationAge = Duration(minutes: 2);

  /// Asks for permission and returns whether we can read a real position.
  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Reads the current permission status without prompting. Used to decide
  /// whether a rationale needs to be shown before the system dialog —
  /// showing one for a permission already granted would just be noise.
  static Future<bool> hasPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// A marker is only shown when it came from a recent, real GPS fix.
  static bool isFresh(Map<String, dynamic>? driver) {
    if (driver == null || driver['locationApproximate'] == true) return false;
    final updatedAt = driver['locationUpdatedAt'];
    if (updatedAt is! Timestamp) return false;
    final age = DateTime.now().difference(updatedAt.toDate());
    return age >= const Duration(seconds: -30) && age <= _maxLocationAge;
  }

  /// Starts writing position updates. Safe to call twice — the previous
  /// subscription is cancelled first. It never invents a location: if GPS
  /// cannot provide a fix, the driver must remain offline.
  static Future<void> startTracking() async {
    await stopTracking();

    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before sharing your location.');

    final granted = await ensurePermission();
    if (!granted) {
      throw StateError(
        'Turn on location services and allow location access to go online.',
      );
    }

    _hasReportedStreamError = false;
    final Position first;
    try {
      first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      throw StateError(
        'Could not get a live GPS fix. Check your signal and try again.',
      );
    }
    await _write(uid, first.latitude, first.longitude);

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (pos) {
        _write(uid, pos.latitude, pos.longitude).catchError((Object error) {
          _reportTrackingError(
            'Could not save your live location. You have been taken offline.',
          );
        });
      },
      onError: (Object error) {
        _reportTrackingError(
          'Live GPS updates stopped. You have been taken offline.',
        );
      },
    );
  }

  static Future<void> stopTracking() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Clears the stored position when a driver goes offline, so a stale pin
  /// doesn't linger on the passenger map.
  static Future<void> clearLocation() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('drivers').doc(uid).update({
      'location': null,
      'locationUpdatedAt': null,
      'locationApproximate': false,
    });
  }

  static void _reportTrackingError(String message) {
    if (_hasReportedStreamError) return;
    _hasReportedStreamError = true;
    unawaited(stopTracking());
    _trackingErrors.add(message);
  }

  static Future<void> _write(String uid, double lat, double lng) async {
    await _db.collection('drivers').doc(uid).update({
      'location': GeoPoint(lat, lng),
      'locationApproximate': false,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    });
  }
}
