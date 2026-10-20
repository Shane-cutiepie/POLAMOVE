import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/cancel_reasons.dart';

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
  ///
  /// Shared with ChatService so both data layers report Firestore errors the
  /// same way — callers wrap the message in their own exception type.
  static String mapErrorMessage(Object e, String action) {
    assert(() {
      // ignore: avoid_print
      print('Firestore error during "$action": $e');
      return true;
    }());

    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          return 'You don\'t have permission to $action. Please contact the administrator.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'No internet connection. Please check your network and try again.';
        case 'not-found':
          return 'This ride no longer exists.';
        case 'failed-precondition':
          return 'The database is still preparing. Please try again in a moment.';
        default:
          return 'Could not $action. Please try again.';
      }
    }
    return 'Could not $action. Please try again.';
  }

  static RideException _mapError(Object e, String action) =>
      RideException(mapErrorMessage(e, action));

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

  /// A real delete, not a soft-delete flag — each notification belongs to
  /// exactly one user via `userId`, so removing one never touches anyone
  /// else's inbox.
  static Future<void> deleteNotification(String notifId) async {
    try {
      await _db.collection('notifications').doc(notifId).delete();
    } catch (e) {
      throw _mapError(e, 'delete this notification');
    }
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
    required LatLng pickupPoint,
    required String destination,
    required LatLng destinationPoint,
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

    // Checked here too (not just in the UI) so a client that skips the
    // pre-check can't slip a booking through while paused.
    final cooldown = await activeCooldown(uid);
    if (cooldown != null) {
      throw RideException(
        'Your bookings are paused until ${_formatCooldownTime(cooldown)} because of repeated cancellations.',
      );
    }

    try {
      final doc = await _rides.add({
        'passengerId': uid,
        'driverId': null,
        'pickup': {
          'name': pickup,
          'location': GeoPoint(pickupPoint.latitude, pickupPoint.longitude),
        },
        'dropoff': {
          'name': destination,
          'location': GeoPoint(
            destinationPoint.latitude,
            destinationPoint.longitude,
          ),
        },
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
    String rideId,
  ) => _rides.doc(rideId).snapshots();

  /// Open bookings, oldest first so the longest-waiting passenger is served
  /// before newer ones.
  static Stream<QuerySnapshot<Map<String, dynamic>>> searchingRides() =>
      _rides
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

    final cooldown = await activeCooldown(uid);
    if (cooldown != null) {
      throw RideException(
        'Your bookings are paused until ${_formatCooldownTime(cooldown)} because of repeated cancellations.',
      );
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

  /// Passengers may cancel any time before completion; a ₱20 late fee applies
  /// once the driver has already reached the pickup point (arrived/ongoing).
  /// Drivers may cancel from accepted/arrived/ongoing and are never charged.
  ///
  /// Runs as a transaction so a double-tap can't cancel twice or write two
  /// fees: the second attempt re-reads the ride, sees status already
  /// 'cancelled', and throws before writing anything.
  static Future<void> cancelRide(
    String rideId, {
    required String reason,
    String? reasonText,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw RideException('You need to be logged in to cancel a ride.');
    }

    final trimmedReasonText = reasonText?.trim();
    if (reason == 'other' &&
        (trimmedReasonText == null || trimmedReasonText.isEmpty)) {
      throw RideException('Please describe your reason for cancelling.');
    }
    final cappedReasonText =
        trimmedReasonText == null
            ? null
            : (trimmedReasonText.length > 200
                ? trimmedReasonText.substring(0, 200)
                : trimmedReasonText);

    String? passengerId;
    String? driverId;
    String? role;
    num fee = 0;

    try {
      await _db.runTransaction((tx) async {
        final rideRef = _rides.doc(rideId);
        final userRef = _db.collection('users').doc(uid);

        // All reads before any write — Firestore transactions require it.
        final rideSnap = await tx.get(rideRef);
        final userSnap = await tx.get(userRef);

        if (!rideSnap.exists) {
          throw RideException('This ride no longer exists.');
        }
        final ride = rideSnap.data() ?? {};
        final status = ride['status'] as String?;
        if (status == 'completed' || status == 'cancelled') {
          throw RideException('This ride has already ended.');
        }

        passengerId = ride['passengerId'] as String?;
        driverId = ride['driverId'] as String?;

        if (uid == passengerId) {
          role = 'passenger';
        } else if (uid == driverId) {
          role = 'driver';
        } else {
          throw RideException('You are not part of this ride.');
        }

        fee =
            (role == 'passenger' &&
                    (status == 'arrived' || status == 'ongoing'))
                ? 20
                : 0;

        tx.update(rideRef, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': uid,
          'cancelledByRole': role,
          'cancellationFee': fee,
          'cancelReason': reason,
          'cancelReasonText': reason == 'other' ? cappedReasonText : null,
        });

        // Rate limiting (Part 6) — recorded on the canceller's own user doc,
        // read and written inside this same transaction.
        final now = Timestamp.now();
        final oneHourAgo = Timestamp.fromDate(
          now.toDate().subtract(const Duration(hours: 1)),
        );
        final history =
            ((userSnap.data()?['recentCancellations'] as List?) ?? [])
                .whereType<Timestamp>()
                .toList()
              ..add(now)
              ..sort();
        final trimmedHistory =
            history.length > 10
                ? history.sublist(history.length - 10)
                : history;
        final withinHour =
            trimmedHistory.where((t) => t.compareTo(oneHourAgo) >= 0).length;

        final userUpdate = <String, dynamic>{
          'recentCancellations': trimmedHistory,
        };
        // Five in a rolling hour triggers a 1-hour cooldown from now. The
        // original ask was "banned for the next 3 trips", which can't work —
        // a blocked user takes no trips, so nothing would ever count down.
        // A time-based cooldown is the fix.
        if (withinHour >= 5) {
          userUpdate['cooldownUntil'] = Timestamp.fromDate(
            now.toDate().add(const Duration(hours: 1)),
          );
        }
        tx.set(userRef, userUpdate, SetOptions(merge: true));
      });
    } on RideException {
      rethrow;
    } catch (e) {
      throw _mapError(e, 'cancel this ride');
    }

    await _notifyCancellation(
      passengerId: passengerId,
      driverId: driverId,
      cancelledByRole: role,
      cancellerId: uid,
      fee: fee,
      reason: reason,
      reasonText: cappedReasonText,
    );
  }

  /// Both parties learn who cancelled and why — never a stored copy of the
  /// name, always a fresh read of users/{uid}. Skipped entirely when the ride
  /// was still `searching`, since there's no driver yet to tell.
  static Future<void> _notifyCancellation({
    required String? passengerId,
    required String? driverId,
    required String? cancelledByRole,
    required String cancellerId,
    required num fee,
    required String reason,
    required String? reasonText,
  }) async {
    if (driverId == null || passengerId == null || cancelledByRole == null) {
      return;
    }

    try {
      final canceller = await userInfo(cancellerId);
      final name =
          '${canceller?['firstName'] ?? ''} ${canceller?['lastName'] ?? ''}'
              .trim();
      final displayName = name.isEmpty ? 'The other party' : name;

      final rawLabel = cancelReasonLabel(
        cancelledByRole: cancelledByRole,
        reason: reason,
        reasonText: reasonText,
      );
      final reasonLabel =
          rawLabel.length > 60 ? rawLabel.substring(0, 60) : rawLabel;

      if (cancelledByRole == 'driver') {
        await _notify(
          userId: passengerId,
          title: 'Ride cancelled by your driver',
          message: '$displayName cancelled the trip. Reason: $reasonLabel.',
          category: 'ride',
        );
        return;
      }

      // Passenger cancelled.
      if (fee > 0) {
        await _notify(
          userId: driverId,
          title: 'Late cancellation — ₱20 fee',
          message:
              '$displayName cancelled after you arrived. Please collect the ₱20 late cancellation fee in cash.',
          category: 'earnings',
        );
        await _notify(
          userId: passengerId,
          title: 'Late cancellation fee',
          message:
              'A ₱20 fee applies because your driver had already arrived. Please pay your driver in cash.',
          category: 'ride',
        );
      } else {
        await _notify(
          userId: driverId,
          title: 'Ride cancelled by passenger',
          message: '$displayName cancelled the trip. Reason: $reasonLabel.',
          category: 'ride',
        );
      }
    } catch (_) {
      // A failed notification must never fail the cancellation, which has
      // already committed by the time this runs.
    }
  }

  // ── Rate limiting ──────────────────────────────────
  /// A cooldown that has expired is treated as absent — compared against
  /// DateTime.now() at read time rather than cleaned up by a background job.
  static Future<DateTime?> activeCooldown(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final ts = doc.data()?['cooldownUntil'];
      if (ts is! Timestamp) return null;
      final until = ts.toDate();
      return until.isAfter(DateTime.now()) ? until : null;
    } catch (_) {
      return null;
    }
  }

  /// Cancellations by [uid] within the last hour, from the stored history —
  /// used right after a cancellation completes to decide whether to show the
  /// 3-in-an-hour warning dialog.
  static Future<int> recentCancellationCount(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      final entries = (doc.data()?['recentCancellations'] as List?) ?? [];
      return entries
          .whereType<Timestamp>()
          .where((t) => t.compareTo(cutoff) >= 0)
          .length;
    } catch (_) {
      return 0;
    }
  }

  static String _formatCooldownTime(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:${d.minute.toString().padLeft(2, '0')} $period';
  }

  static Future<void> _advance(
    String rideId,
    String status,
    String stampField,
  ) async {
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
