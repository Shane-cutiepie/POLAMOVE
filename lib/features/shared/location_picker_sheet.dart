import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/polangui_locations.dart';
import '../../core/utils/map_platform.dart';

Future<PickedLocation?> showLocationPicker(
  BuildContext context,
  String title, {
  PickedLocation? initialLocation,
}) {
  return Navigator.of(context).push<PickedLocation>(
    MaterialPageRoute(
      builder:
          (_) => _LocationPickerScreen(
            title: title,
            initialLocation: initialLocation,
          ),
    ),
  );
}

class _LocationPickerScreen extends StatefulWidget {
  final String title;
  final PickedLocation? initialLocation;

  const _LocationPickerScreen({required this.title, this.initialLocation});

  @override
  State<_LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<_LocationPickerScreen> {
  static const _mapStyle =
      '[{"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]}]';

  final _searchController = TextEditingController();
  final _fallbackMapController = MapController();
  gmaps.GoogleMapController? _googleMapController;
  late LatLng _mapCentre;
  PickedLocation? _selected;
  String _query = '';

  List<String> get _visibleLocations =>
      kPolanguiLocations.keys
          .where((name) => name.toLowerCase().contains(_query.toLowerCase()))
          .toList();

  @override
  void initState() {
    super.initState();
    _selected = widget.initialLocation;
    _mapCentre = widget.initialLocation?.point ?? kPolanguiCentre;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectLandmark(String name) {
    final place = pickedLocationFor(name);
    setState(() => _selected = place);
    _focus(place.point);
  }

  void _selectMapCentre() {
    _selectMapPoint(_mapCentre);
  }

  void _selectMapPoint(LatLng point) {
    final pin = PickedLocation(
      name:
          'Map pin (${point.latitude.toStringAsFixed(5)}, '
          '${point.longitude.toStringAsFixed(5)})',
      point: point,
    );
    setState(() {
      _selected = pin;
      _mapCentre = point;
    });
    _focus(point);
  }

  void _focus(LatLng point) {
    if (usesGoogleMaps) {
      _googleMapController?.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(_toGoogleLatLng(point), 17),
      );
    } else {
      _fallbackMapController.move(point, 17);
    }
  }

  gmaps.LatLng _toGoogleLatLng(LatLng point) =>
      gmaps.LatLng(point.latitude, point.longitude);

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: 'Syne',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                Positioned.fill(child: _buildMap()),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.touch_app_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selected?.name ?? 'Choose your pickup point',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Move the map so the single pin is on your pickup',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 28),
                      child: Icon(
                        Icons.location_pin,
                        color: AppColors.primary,
                        size: 46,
                        shadows: [Shadow(color: Colors.white, blurRadius: 5)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Center(
                    child: ElevatedButton.icon(
                      onPressed: _selectMapCentre,
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text('Set pickup at map center'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: 'Search Polangui pickup locations',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
                suffixIcon:
                    _query.isEmpty
                        ? null
                        : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _query.isEmpty ? 'Pickup locations' : 'Matching locations',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(flex: 4, child: _buildLocationList()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      selected == null
                          ? null
                          : () => Navigator.pop(context, selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: Text(
                    selected == null
                        ? 'Choose a pickup location'
                        : 'Use ${selected.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (usesGoogleMaps) {
      return gmaps.GoogleMap(
        initialCameraPosition: gmaps.CameraPosition(
          target: _toGoogleLatLng(_mapCentre),
          zoom: widget.initialLocation == null ? 15 : 17,
        ),
        style: _mapStyle,
        onMapCreated: (controller) => _googleMapController = controller,
        onTap:
            (point) => _selectMapPoint(LatLng(point.latitude, point.longitude)),
        onCameraMove: (position) {
          _mapCentre = LatLng(
            position.target.latitude,
            position.target.longitude,
          );
        },
        zoomControlsEnabled: false,
        myLocationButtonEnabled: false,
      );
    }

    return FlutterMap(
      mapController: _fallbackMapController,
      options: MapOptions(
        initialCenter: _mapCentre,
        initialZoom: widget.initialLocation == null ? 15 : 17,
        onPositionChanged: (camera, _) => _mapCentre = camera.center,
        onTap: (_, point) => _selectMapPoint(point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.polamove.app',
        ),
      ],
    );
  }

  Widget _buildLocationList() {
    final locations = _visibleLocations;
    if (locations.isEmpty) {
      return const Center(
        child: Text(
          'No saved Polangui pickup locations match your search.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: locations.length,
      separatorBuilder:
          (_, __) =>
              const Divider(height: 1, indent: 48, color: Color(0x1C14142A)),
      itemBuilder: (context, index) {
        final name = locations[index];
        final point = locationFor(name);
        final selected = _selected?.name == name;
        return ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: AppColors.primaryTint,
          leading: Icon(
            selected ? Icons.check_circle_rounded : Icons.location_on_rounded,
            color: selected ? AppColors.success : AppColors.primary,
          ),
          title: Text(
            name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${point.latitude.toStringAsFixed(5)}, '
            '${point.longitude.toStringAsFixed(5)} · Polangui, Albay',
            style: const TextStyle(fontSize: 10),
          ),
          onTap: () => _selectLandmark(name),
        );
      },
    );
  }
}
