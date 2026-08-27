import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/polangui_locations.dart';

/// Bottom sheet for choosing one of the named Polangui locations. Returns the
/// chosen name, or null if the sheet was dismissed.
///
/// Hoisted out of booking_screen.dart so the passenger home screen can use the
/// same picker. The list is driven by kPolanguiLocations, so the names offered
/// here and the coordinates the map draws can never drift apart.
Future<String?> showLocationPicker(BuildContext context, String title) async {
  final locations = kPolanguiLocations.keys.toList();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
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
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).padding.bottom),
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
