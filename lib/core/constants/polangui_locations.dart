import 'package:latlong2/latlong.dart';

/// The pickup and destination points offered in Polangui, and where each one
/// sits on the map. Single source of truth — referenced by the shared location
/// picker, the passenger home map, and the route keys stored in
/// `settings/fares`.
/// Coordinates match the corresponding Google Maps place records.
///
/// Insertion order is the order the picker lists them in, so keep it stable.
///
/// The admin console keeps its own copy of these exact strings in
/// admin/index.html (it cannot import Dart). If this list changes, that copy
/// must change with it or per-route fares will silently fall back to default.
///
/// These public landmarks power the suggested list. Passengers can also pin
/// an exact pickup on Google Maps; that point is stored only on the ride and
/// is never used for background passenger tracking.
const Map<String, LatLng> kPolanguiLocations = {
  'Polangui Integrated Transport Terminal': LatLng(13.2914801, 123.4808825),
  'Jollibee Polangui Drive Thru': LatLng(13.2883507, 123.4890007),
  'LCC Mall Polangui': LatLng(13.2889761, 123.4909201),
  'Bicol University Polangui Campus': LatLng(13.2961829, 123.4846866),
  'Xentro Mall Polangui': LatLng(13.2889230, 123.4888707),
  'Polangui General Comprehensive High School': LatLng(13.2965108, 123.4864775),
  'Polangui Night Market': LatLng(13.2904111, 123.4906832),
  'Polangui Municipal Hall': LatLng(13.2929159, 123.4842578),
  'Biggs Polangui': LatLng(13.2925934, 123.4901474),
  'RHU Polangui Birthing Facility': LatLng(13.2924871, 123.4903247),
};

/// The town centre, using the Google Maps position for Polangui Municipal Hall.
const LatLng kPolanguiCentre = LatLng(13.2929159, 123.4842578);

class PickedLocation {
  final String name;
  final LatLng point;

  const PickedLocation({required this.name, required this.point});
}

PickedLocation pickedLocationFor(String name) =>
    PickedLocation(name: name, point: locationFor(name));

/// Coordinates for a named location. Falls back to the town centre for an
/// unknown or null name — including a name from data written before a
/// location was renamed or removed — so a stale stored value can never leave
/// the map pointing at nowhere.
LatLng locationFor(String? name) => kPolanguiLocations[name] ?? kPolanguiCentre;
