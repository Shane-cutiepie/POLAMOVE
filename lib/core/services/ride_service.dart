import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Thrown for anything the user should see a readable message about.
class RideException implements Exception {
  final String message;
  RideException(this.message);
  @override
  String toString() => message;
}

/// Ride data layer.
///
/// Status flow: searching → accepted → arrived → ongoing → completed,
/// or cancelled from any pre-completed state.
///
/// Field names here match what admin/polamove_admin_firebase.js already
/// reads (pickup.name, dropoff.name, rideType, seats, totalFare, status,
/// requestedAt, passengerId, driverId) so the admin console keeps working.
class RideService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _rides =>
      _db.collection('rides');

  /// Turns a Firestore error into something that points at the real cause.
  /// A blanket "check your connection" message hides permission problems and
  /// sends you debugging the wrong thing.
  static RideException _mapError(Object e, String action) {
    assert(() {
      // ignore: avoid_print
      print('RideService error during "$action": $e');
      return true;
    }());

    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return RideException(
              'You don\'t have permission to $action. Please contact the administrator.');
        case 'unavailable':
        case 'deadline-exceeded':
          return RideException(
              'No internet connection. Please check your network and try again.');
        case 'not-found':
          return RideException('This ride no longer exists.');
        case 'failed-precondition':
          return RideException(
              'The database is still preparing. Please try again in a moment.');
        default:
          return RideException('Could not $action. Please try again.');
      }
    }
    return RideException('Could not $action. Please try again.');
  }

  /// Best-effort in-app notification. A failed notification must never break
  /// the ride action that triggered it.
  static Future<void> _notify({
    required String userId,
    required String title,
    required String message,
    required String category,
  }) async {
    try {
      await _db.collection('notifications').add({
        'userId': userId,
        'title': title,
        'message': message,
        'category': category,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Reads a ride for the notification step only — never lets a failed read
  /// surface as an error on an action that already succeeded.
  static Future<Map<String, dynamic>?> _rideData(String rideId) async {
    try {
      final doc = await _rides.doc(rideId).get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  /// The booking screen works in short ids; the rest of the app (admin
  /// console, history filters, driver request card) displays the long name.
  static String _rideTypeName(String shortId) {
    switch (shortId) {
      case 'solo':
        return 'PolaSolo';
      case 'share':
        return 'PolaShare';
      case 'rent':
        return 'PolaRent';
      default:
        return 'PolaSolo';
    }
  }

  // ── Create ─────────────────────────────────────────
  /// Writes a ride in `searching` state and returns its document id.
  static Future<String> createRide({
    required String pickup,
    required String destination,
    required String rideTypeShortId,
    required double baseFare,
    required double surcharge,
    required int seats,
    required int hours,
    required double totalFare,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw RideException('You need to be logged in to book a ride.');
    }

    try {
      final doc = await _rides.add({
        'passengerId': uid,
        'driverId': null,
        'pickup': {'name': pickup},
        'dropoff': {'name': destination},
        'rideType': _rideTypeName(rideTypeShortId),
        'rideTypeShortId': rideTypeShortId,
        'baseFare': baseFare,
        'surcharge': surcharge,
        'seats': seats,
        'hours': hours,
        'totalFare': totalFare,
        'paymentMethod': 'cash',
        'status': 'searching',
        'requestedAt': FieldValue.serverTimestamp(),
        'acceptedAt': null,
        'arrivedAt': null,
        'startedAt': null,
        'completedAt': null,
        'cancelledAt': null,
      });
      return doc.id;
    } catch (e) {
      throw _mapError(e, 'book this ride');
    }
  }

  // ── Watch ──────────────────────────────────────────
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchRide(
          String rideId) =>
      _rides.doc(rideId).snapshots();

  /// Open bookings, oldest first so the longest-waiting passenger is served
  /// before newer ones.
  static Stream<QuerySnapshot<Map<String, dynamic>>> searchingRides() => _rides
      .where('status', isEqualTo: 'searching')
      .orderBy('requestedAt')
      .snapshots();

  // ── Driver actions ─────────────────────────────────
  /// Claims a ride for the signed-in driver. Runs in a transaction so two
  /// drivers tapping Accept at the same moment can't both win.
  static Future<void> acceptRide(String rideId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw RideException('You need to be logged in to accept a ride.');
    }

    String? passengerId;

    try {
      await _db.runTransaction((tx) async {
        final ref = _rides.doc(rideId);
        final snap = await tx.get(ref);

        if (!snap.exists) {
          throw RideException('This booking is no longer available.');
        }
        final status = snap.data()?['status'] as String?;
        if (status == 'cancelled') {
          throw RideException('This booking was cancelled by the passenger.');
        }
        if (status != 'searching') {
          throw RideException('Another driver already took this booking.');
        }
        passengerId = snap.data()?['passengerId'] as String?;

        tx.update(ref, {
          'driverId': uid,
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });
    } on RideException {
      rethrow;
    } catch (e) {
      throw _mapError(e, 'accept this booking');
    }

    final passenger = passengerId;
    if (passenger != null) {
      await _notify(
        userId: passenger,
        title: 'Driver found',
        message:
            'A driver accepted your booking and is on the way to your pickup point.',
        category: 'ride',
      );
    }
  }

  static Future<void> markArrived(String rideId) async {
    await _advance(rideId, 'arrived', 'arrivedAt');

    final passengerId = (await _rideData(rideId))?['passengerId'] as String?;
    if (passengerId != null) {
      await _notify(
        userId: passengerId,
        title: 'Your driver has arrived',
        message: 'Your driver is waiting for you at the pickup point.',
        category: 'ride',
      );
    }
  }

  /// No notification here on purpose — the passenger is watching the live
  /// status screen when the trip starts, so it would only be noise.
  static Future<void> startTrip(String rideId) =>
      _advance(rideId, 'ongoing', 'startedAt');

  /// Completes the ride and rolls the fare into the driver's running totals.
  static Future<void> completeRide(String rideId) async {
    String? passengerId;
    String? completedDriverId;
    double completedFare = 0;

    try {
      await _db.runTransaction((tx) async {
        final ref = _rides.doc(rideId);
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw RideException('This ride no longer exists.');
        }

        final data = snap.data() ?? {};
        final driverId = data['driverId'] as String?;
        final fare = (data['totalFare'] ?? 0).toDouble();

        passengerId = data['passengerId'] as String?;
        completedDriverId = driverId;
        completedFare = fare;

        tx.update(ref, {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        });

        if (driverId != null) {
          tx.update(_db.collection('drivers').doc(driverId), {
            'totalRides': FieldValue.increment(1),
            'totalEarnings': FieldValue.increment(fare),
          });
        }
      });
    } on RideException {
      rethrow;
    } catch (e) {
      throw _mapError(e, 'complete the ride');
    }

    final fareLabel = '₱${completedFare.toStringAsFixed(0)}';
    final passenger = passengerId;
    if (passenger != null) {
      await _notify(
        userId: passenger,
        title: 'Trip completed',
        message:
            'Your trip is complete. Please pay $fareLabel in cash to your driver.',
        category: 'ride',
      );
    }

    final driver = completedDriverId;
    if (driver != null) {
      await _notify(
        userId: driver,
        title: 'Trip completed',
        message:
            'Trip complete. Please collect $fareLabel cash payment from the passenger.',
        category: 'earnings',
      );
    }
  }

  static Future<void> cancelRide(String rideId) async {
    await _advance(rideId, 'cancelled', 'cancelledAt');

    final data = await _rideData(rideId);
    final driverId = data?['driverId'] as String?;
    final passengerId = data?['passengerId'] as String?;

    // Nobody has been matched yet — there is no other party to tell.
    if (driverId == null) return;

    final me = _auth.currentUser?.uid;
    final cancelledByPassenger = me == passengerId;
    final recipient = cancelledByPassenger ? driverId : passengerId;
    if (recipient == null || recipient == me) return;

    await _notify(
      userId: recipient,
      title: 'Ride cancelled',
      message: cancelledByPassenger
          ? 'The passenger cancelled this ride.'
          : 'Your driver cancelled this ride. You can book another tricycle.',
      category: 'ride',
    );
  }

  static Future<void> _advance(
      String rideId, String status, String stampField) async {
    try {
      await _rides.doc(rideId).update({
        'status': status,
        stampField: FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw _mapError(e, 'update the ride');
    }
  }

  // ── History ────────────────────────────────────────
  static Stream<QuerySnapshot<Map<String, dynamic>>> passengerHistory() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _rides
        .where('passengerId', isEqualTo: uid)
        .orderBy('requestedAt', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> driverHistory() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _rides
        .where('driverId', isEqualTo: uid)
        .orderBy('requestedAt', descending: true)
        .snapshots();
  }

  // ── Drivers ────────────────────────────────────────
  /// Only `isOnline` is filtered here — going online already requires an
  /// approved account, and a single-field filter needs no composite index.
  static Stream<QuerySnapshot<Map<String, dynamic>>> onlineDrivers() =>
      _db.collection('drivers').where('isOnline', isEqualTo: true).snapshots();

  // ── Lookups ────────────────────────────────────────
  static Future<Map<String, dynamic>?> userInfo(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> driverInfo(String uid) async {
    try {
      final doc = await _db.collection('drivers').doc(uid).get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }
}
