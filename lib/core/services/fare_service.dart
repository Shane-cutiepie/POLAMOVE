import 'package:cloud_firestore/cloud_firestore.dart';

/// Fare configuration, loaded once per session from settings/fares.
///
/// Fares change rarely, so this is a one-time read rather than a listener —
/// a stream would cost a document read per app launch for data that is
/// effectively static.
///
/// Pricing model: the route sets the base fare, the ride type modifies it.
/// PolaRent ignores the route entirely — it is priced by the hour.
class FareService {
  // A flat ₱20 base fare across every route, applied via this same fallback
  // for a route with no settings/fares.routes entry — which today is every
  // route, since none has been configured yet. Real per-route pricing comes
  // later through the admin console; until then this is the rate everyone
  // pays. The other defaults below still mirror what booking_screen.dart
  // hardcoded before fares became configurable, so the app behaves
  // identically when the document is absent.
  static double _defaultBaseFare = 20;
  static double _soloSurcharge = 1.3;
  static int _maxSeats = 5;
  static double _rentHourlyRate = 60;
  static int _rentMinHours = 1;
  static Map<String, num> _routes = {};
  static bool _loaded = false;

  /// Alphabetical ordering makes the key identical for A→B and B→A.
  /// The admin console builds keys the same way — the two must not diverge.
  static String routeKey(String a, String b) =>
      (a.compareTo(b) <= 0) ? '$a|$b' : '$b|$a';

  static bool get isLoaded => _loaded;

  /// Never throws. Offline, permission denied, or a missing document all leave
  /// the defaults in place — a passenger must always be able to book.
  static Future<void> load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('fares')
          .get();
      final data = doc.data();
      if (data == null) return;

      final solo = data['solo'];
      final share = data['share'];
      final rent = data['rent'];

      // defaultBaseFare replaced solo.baseFare when the base fare stopped
      // being PolaSolo-specific. Older documents still carry the old shape.
      final base = data['defaultBaseFare'] ??
          (solo is Map ? solo['baseFare'] : null);
      if (base is num) _defaultBaseFare = base.toDouble();

      if (solo is Map && solo['surcharge'] is num) {
        _soloSurcharge = (solo['surcharge'] as num).toDouble();
      }
      if (share is Map && share['maxSeats'] is num) {
        _maxSeats = (share['maxSeats'] as num).toInt();
      }
      if (rent is Map) {
        if (rent['hourlyRate'] is num) {
          _rentHourlyRate = (rent['hourlyRate'] as num).toDouble();
        }
        if (rent['minHours'] is num) {
          _rentMinHours = (rent['minHours'] as num).toInt();
        }
      }

      final routes = data['routes'];
      if (routes is Map) {
        _routes = {
          for (final entry in routes.entries)
            if (entry.key is String && entry.value is num)
              entry.key as String: entry.value as num,
        };
      }

      _loaded = true;
    } catch (_) {
      // Keep the defaults. Booking must never depend on this read.
    }
  }

  /// The route's configured base fare, or the default when the pair has no
  /// entry — an unpriced route never blocks a booking.
  static double baseFareFor(String? pickup, String? destination) {
    if (pickup == null || destination == null) return _defaultBaseFare;
    final fare = _routes[routeKey(pickup, destination)];
    return fare?.toDouble() ?? _defaultBaseFare;
  }

  static double soloFare(String? pickup, String? destination) =>
      baseFareFor(pickup, destination) * _soloSurcharge;

  static double shareFare(String? pickup, String? destination, int seats) =>
      baseFareFor(pickup, destination) * seats;

  static double rentFare(int hours) => _rentHourlyRate * hours;

  static double get defaultBaseFare => _defaultBaseFare;
  static double get soloSurcharge => _soloSurcharge;
  static int get maxSeats => _maxSeats;
  static int get rentMinHours => _rentMinHours;
}
