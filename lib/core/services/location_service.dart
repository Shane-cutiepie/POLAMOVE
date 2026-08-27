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

  /// Pins every driver position to Polangui regardless of real GPS.
  ///
  /// Development and demonstration aid: the team tests from outside Polangui,
  /// and the passenger map filters drivers to within 3 km of the town centre,
  /// so real coordinates make the app appear broken. The live GPS path below
  /// is fully implemented — set this to false to enable it for production
  /// deployment.
  static const bool kForcePolanguiLocation = false;

  /// Fallback used when a driver denies location permission: the town centre.
  /// Better than dropping them off the map entirely, and clearly marked in the
  /// document so the UI can treat it as approximate.
  static const double _fallbackLat = 13.29284;
  static const double _fallbackLng = 123.48414;

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

  /// Starts writing position updates. Safe to call twice — the previous
  /// subscription is cancelled first.
  static Future<void> startTracking() async {
    await stopTracking();

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    if (kForcePolanguiLocation) {
      await _writeFallback(uid);
      return;
    }

    final granted = await ensurePermission();
    if (!granted) {
      await _writeFallback(uid);
      return;
    }

    // One immediate write so the driver appears on the map straight away
    // instead of waiting for the first movement of 25 metres.
    try {
      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await _write(uid, first.latitude, first.longitude);
    } catch (_) {
      await _writeFallback(uid);
    }

    // 10 m filter: a tricycle at ~20 km/h covers that in ~2 seconds, so the
    // marker updates about twice as often as the old 25 m filter — enough to
    // read as continuous once animated between points. That's more Firestore
    // writes, but still well within the free tier at this project's scale.
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      _write(uid, pos.latitude, pos.longitude);
    }, onError: (_) {});
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
    try {
      await _db.collection('drivers').doc(uid).update({
        'location': null,
        'locationUpdatedAt': null,
      });
    } catch (_) {}
  }

  /// Permission-denied drivers all fall back to the same coordinates, which
  /// stacks them on a single pixel while the nearby count reports several.
  /// Offsetting by a hash of the uid scatters them ~±150 m around the centre,
  /// and stays deterministic so a driver doesn't jump between writes.
  static Future<void> _writeFallback(String uid) async {
    final h = uid.hashCode;
    final latOffset = ((h % 200) - 100) / 100 * 0.0013;
    final lngOffset = (((h ~/ 200) % 200) - 100) / 100 * 0.0013;
    await _write(uid, _fallbackLat + latOffset, _fallbackLng + lngOffset,
        approximate: true);
  }

  static Future<void> _write(String uid, double lat, double lng,
      {bool approximate = false}) async {
    try {
      await _db.collection('drivers').doc(uid).update({
        'location': GeoPoint(lat, lng),
        'locationApproximate': approximate,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // A failed position write must never interrupt the driver's session.
    }
  }
}
