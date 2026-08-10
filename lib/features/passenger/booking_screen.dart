import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/ride_service.dart';
import 'ride_status_screen.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  String _selectedType = 'solo';
  int _seats = 3;
  int _rentHours = 2;
  String? _pickup;
  String? _destination;
  bool _isBooking = false;

  static const double _basefare = 15.0;
  static const double _soloSurcharge = 1.3;
  static const double _rentRate = 60.0;

  double? get _fare {
    if (_pickup == null || _destination == null) return null;
    switch (_selectedType) {
      case 'solo': return _basefare * _soloSurcharge;
      case 'share': return _basefare * _seats;
      case 'rent': return _rentRate * _rentHours;
      default: return null;
    }
  }

  String get _fareLabel {
    final f = _fare;
    if (f == null) return '₱—';
    return '₱${f.toStringAsFixed(0)}';
  }

  String get _fareNote {
    if (_pickup == null || _destination == null) return 'Select pickup & destination';
    switch (_selectedType) {
      case 'solo': return 'PolaSolo — exclusive ride';
      case 'share': return 'PolaShare — $_seats seat${_seats > 1 ? 's' : ''}';
      case 'rent': return 'PolaRent — ${_rentHours}h exclusive rental';
      default: return '';
    }
  }

  Future<void> _bookRide() async {
    if (_pickup == null || _destination == null) return;
    setState(() => _isBooking = true);
    try {
      final rideId = await RideService.createRide(
        pickup: _pickup!,
        destination: _destination!,
        rideTypeShortId: _selectedType,
        baseFare: _basefare,
        surcharge: _selectedType == 'solo' ? _basefare * (_soloSurcharge - 1) : 0,
        seats: _selectedType == 'share' ? _seats : 1,
        hours: _selectedType == 'rent' ? _rentHours : 0,
        totalFare: _fare ?? 0,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => RideStatusScreen(
          rideId: rideId,
          pickup: _pickup!,
          destination: _destination!,
          rideType: _selectedType,
          fare: _fare ?? 0,
        ),
      ));
    } on RideException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message, style: const TextStyle(fontFamily: 'DM Sans')),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        // Header
        _buildHeader(context),
        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Location card
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 13, 15, 0),
                child: _buildLocationCard(),
              ),
              // Fare box
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 9, 15, 0),
                child: _buildFareBox(),
              ),
              // Ride type label
              const Padding(
                padding: EdgeInsets.fromLTRB(15, 14, 15, 7),
                child: Text('Choose Ride Type',
                    style: TextStyle(fontFamily: 'Syne', fontSize: 14,
                        fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              // PolaSolo
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 8),
                child: _RideTypeCard(
                  id: 'solo', emoji: '🚖', name: 'PolaSolo',
                  description: 'Exclusive ride — just for you\nNo waiting · Small surcharge added',
                  price: _pickup != null && _destination != null
                      ? '₱${(_basefare * _soloSurcharge).toStringAsFixed(0)}' : '₱—',
                  selected: _selectedType == 'solo',
                  onTap: () => setState(() => _selectedType = 'solo'),
                  extra: null,
                ),
              ),
              // PolaShare
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 8),
                child: _RideTypeCard(
                  id: 'share', emoji: '👥', name: 'PolaShare',
                  description: 'Group ride — fare × seats booked',
                  price: _pickup != null && _destination != null
                      ? '₱${(_basefare * _seats).toStringAsFixed(0)}' : '₱—',
                  selected: _selectedType == 'share',
                  onTap: () => setState(() => _selectedType = 'share'),
                  extra: _selectedType == 'share'
                      ? _buildSeatSelector() : null,
                ),
              ),
              // PolaRent
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 8),
                child: _RideTypeCard(
                  id: 'rent', emoji: '🗓️', name: 'PolaRent',
                  description: 'Rent the whole tricycle by the hour\nPerfect for errands, groceries & trips',
                  price: _selectedType == 'rent'
                      ? '₱${(_rentRate * _rentHours).toStringAsFixed(0)}' : '₱—',
                  selected: _selectedType == 'rent',
                  onTap: () => setState(() => _selectedType = 'rent'),
                  extra: _selectedType == 'rent'
                      ? _buildRentHoursSelector() : null,
                ),
              ),
            ]),
          ),
        ),
        // Book button
        _buildBookButton(context),
      ]),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(width: 34, height: 34,
                decoration: BoxDecoration(color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.border, width: 1.5)),
                child: const Icon(Icons.chevron_left_rounded,
                    color: AppColors.textSecondary, size: 20)),
            ),
            const SizedBox(width: 10),
            const Text('Book a Ride', style: TextStyle(fontFamily: 'Syne',
                fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ]),
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(children: [
        // Pickup row
        _LocationRow(
          isDot: true, isFrom: true,
          label: _pickup ?? 'Select pickup…',
          hasValue: _pickup != null,
          onTap: () async {
            final result = await _showLocationPicker(context, 'Set Pickup Location');
            if (result != null) setState(() => _pickup = result);
          },
        ),
        // Divider line
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Divider(height: 16, color: AppColors.border),
        ),
        // Destination row
        _LocationRow(
          isDot: true, isFrom: false,
          label: _destination ?? 'Select destination…',
          hasValue: _destination != null,
          onTap: () async {
            final result = await _showLocationPicker(context, 'Set Destination');
            if (result != null) setState(() => _destination = result);
          },
        ),
      ]),
    );
  }

  Widget _buildFareBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(children: [
        const Text('💰', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total Fare', style: TextStyle(fontSize: 11,
              color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          Text(_fareLabel, style: const TextStyle(fontFamily: 'Syne', fontSize: 22,
              fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          Text(_fareNote, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
        ])),
      ]),
    );
  }

  Widget _buildSeatSelector() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        const Text('Seats:', style: TextStyle(fontSize: 12,
            color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        ...([2, 3, 4, 5].map((s) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => setState(() => _seats = s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34, height: 30,
              decoration: BoxDecoration(
                color: _seats == s ? AppColors.primary : AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _seats == s ? AppColors.primary : AppColors.border, width: 1.5),
              ),
              child: Center(child: Text('$s', style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _seats == s ? Colors.white : AppColors.textSecondary))),
            ),
          ),
        ))),
      ]),
    );
  }

  Widget _buildRentHoursSelector() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Hours:', style: TextStyle(fontSize: 12,
              color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          ...([1, 2, 3, 4].map((h) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => setState(() => _rentHours = h),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _rentHours == h ? AppColors.primary : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _rentHours == h ? AppColors.primary : AppColors.border, width: 1.5),
                ),
                child: Text('${h}h', style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _rentHours == h ? Colors.white : AppColors.textSecondary)),
              ),
            ),
          ))),
        ]),
        const SizedBox(height: 8),
        Text('🗺️ Driver stays with you the whole rental\n📍 Coverage: Polangui & nearby barangays',
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, height: 1.6)),
      ]),
    );
  }

  Widget _buildBookButton(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(15, 10, 15, MediaQuery.of(context).padding.bottom + 14),
      child: SizedBox(width: double.infinity,
        child: ElevatedButton(
          onPressed: (_pickup != null && _destination != null && !_isBooking)
              ? _bookRide
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.surfaceStrong,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
          child: _isBooking
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Book Ride Now 🛺', style: TextStyle(fontFamily: 'Syne',
                  fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Future<String?> _showLocationPicker(BuildContext context, String title) async {
    final locations = [
      'Polangui Centro', 'Public Market', 'Bus Terminal',
      'Bicol University Polangui', 'Polangui General Hospital',
      'Lidong', 'Sabang', 'San Francisco', 'Santa Cruz', 'Yapad',
    ];
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(children: [
                Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.surfaceStrong,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 14),
                Text(title, style: const TextStyle(fontFamily: 'Syne', fontSize: 15,
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search location in Polangui…',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.textTertiary, size: 18),
                    filled: true, fillColor: AppColors.surfaceAlt,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0x1C14142A))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0x1C14142A))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                  ),
                ),
              ]),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(alignment: Alignment.centerLeft,
                child: Text('Suggested Locations', style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5)))),
            Expanded(child: ListView.separated(
              controller: controller,
              itemCount: locations.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 52,
                  color: Color(0x1C14142A)),
              itemBuilder: (_, i) => ListTile(
                leading: Container(width: 34, height: 34,
                  decoration: BoxDecoration(color: AppColors.primaryTint,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.location_on_rounded,
                      color: AppColors.primary, size: 16)),
                title: Text(locations[i], style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                subtitle: Text('Polangui, Albay', style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
                onTap: () => Navigator.pop(context, locations[i]),
              ),
            )),
          ]),
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final bool isDot;
  final bool isFrom;
  final String label;
  final bool hasValue;
  final VoidCallback onTap;

  const _LocationRow({required this.isDot, required this.isFrom,
      required this.label, required this.hasValue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(children: [
        Container(width: 10, height: 10,
          decoration: BoxDecoration(
            color: isFrom ? AppColors.success : AppColors.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: (isFrom ? AppColors.success : AppColors.primary).withOpacity(0.3),
                blurRadius: 4)],
          )),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
            color: hasValue ? AppColors.textPrimary : AppColors.textTertiary),
            overflow: TextOverflow.ellipsis)),
        Text('MAP ›', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: isFrom ? AppColors.primaryLight : AppColors.textTertiary)),
      ]),
    );
  }
}

class _RideTypeCard extends StatelessWidget {
  final String id;
  final String emoji;
  final String name;
  final String description;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  final Widget? extra;

  const _RideTypeCard({required this.id, required this.emoji, required this.name,
      required this.description, required this.price, required this.selected,
      required this.onTap, required this.extra});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border, width: 1.5),
          boxShadow: selected ? [BoxShadow(color: AppColors.primary.withOpacity(0.12),
              blurRadius: 16, offset: const Offset(0, 4))] : [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontFamily: 'Syne', fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primary : AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(fontSize: 11,
                  color: AppColors.textSecondary, height: 1.5)),
            ])),
            const SizedBox(width: 8),
            Text(price, style: TextStyle(fontFamily: 'Syne', fontSize: 16,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.primary : AppColors.textPrimary)),
          ]),
          if (extra != null) extra!,
        ]),
      ),
    );
  }
}