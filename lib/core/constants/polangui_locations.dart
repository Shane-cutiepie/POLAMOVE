import 'package:latlong2/latlong.dart';

/// The pickup and destination points offered in Polangui, and where each one
/// sits on the map. Single source of truth — referenced by the shared location
/// picker, the passenger home map, and the route keys stored in
/// `settings/fares`.
///
/// Insertion order is the order the picker lists them in, so keep it stable.
///
/// The admin console keeps its own copy of these exact strings in
/// admin/index.html (it cannot import Dart). If this list changes, that copy
/// must change with it or per-route fares will silently fall back to default.
///
/// These are all public landmarks — never barangays, and never a passenger's
/// own address. Pickup is chosen from this fixed list rather than a GPS point
/// or a saved address specifically so that no passenger's home location is
/// ever stored; that follows the project's ethics review guidance on
/// handling location data, not just a UI convenience.
const Map<String, LatLng> kPolanguiLocations = {
  'Polangui Integrated Transport Terminal': LatLng(13.2899, 123.4835),
  'Jollibee Polangui Drive Thru':           LatLng(13.2954, 123.4770),
  'LCC Mall Polangui':                      LatLng(13.3032, 123.4855),
  'Bicol University Polangui Campus':       LatLng(13.30361, 123.47556),
  'Xentro Mall Polangui':                   LatLng(13.2950, 123.4790),
  'Polangui General Comprehensive High School': LatLng(13.2922, 123.4856),
  'Polangui Night Market':                  LatLng(13.28583, 123.49639),
  'Polangui Municipal Hall':                LatLng(13.29284, 123.48414),
  'Biggs Polangui':                         LatLng(13.2958, 123.4792),
  'RHU Polangui Birthing Facility':         LatLng(13.3150, 123.4830),
};

/// The town centre, used as the map's default focus — Polangui Municipal
/// Hall, central and the anchor every map screen opens on.
const LatLng kPolanguiCentre = LatLng(13.29284, 123.48414);

/// Coordinates for a named location. Falls back to the town centre for an
/// unknown or null name — including a name from data written before a
/// location was renamed or removed — so a stale stored value can never leave
/// the map pointing at nowhere.
LatLng locationFor(String? name) =>
    kPolanguiLocations[name] ?? kPolanguiCentre;
