import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/research_notice.dart';

/// Shown immediately before the system location permission dialog, so a
/// driver understands why PolaMove is asking before the OS asks for them.
///
/// Returns true only if the driver tapped Continue. Dismissing the sheet any
/// other way (tap-outside, swipe down) resolves to false — the caller must
/// not request the permission or go online in that case.
Future<bool> showLocationRationaleSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _LocationRationaleSheet(),
  );
  return result ?? false;
}

class _LocationRationaleSheet extends StatelessWidget {
  const _LocationRationaleSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.surfaceStrong,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          const Text(kLocationRationaleTitle,
              style: TextStyle(fontFamily: 'Syne', fontSize: 18,
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          const Text(kLocationRationaleBody,
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                  color: AppColors.textSecondary, height: 1.5)),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
              child: const Text(kLocationRationaleContinueButton,
                  style: TextStyle(fontFamily: 'Syne', fontSize: 14,
                      fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            ),
          ),
        ],
      ),
    );
  }
}
