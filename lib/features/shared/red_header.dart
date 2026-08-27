import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// The red page header used across the app, matching the status header in
/// ride_status_screen.dart.
///
/// [onBack] exists because the history and notification screens are tabs
/// inside a bottom-nav shell rather than pushed routes, so `Navigator.pop`
/// has nothing to pop. The shell passes a callback that returns it to the
/// Home tab; pushed routes leave it null and get the normal pop.
class RedHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  /// Optional trailing widget, e.g. the "Mark all read" button.
  final Widget? action;

  const RedHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      child: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(1.0, -1.0), radius: 1.2,
              colors: [Color(0x1CFFFFFF), Colors.transparent])))),
        SafeArea(bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 18),
            child: Row(children: [
              GestureDetector(
                onTap: onBack ?? () => Navigator.maybePop(context),
                child: Container(width: 31, height: 31,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white.withOpacity(0.2))),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 20))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontFamily: 'Syne', fontSize: 15,
                    fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11,
                    color: Colors.white.withOpacity(0.72))),
              ])),
              if (action != null) action!,
            ]),
          ),
        ),
      ]),
    );
  }
}

/// White text button for the header's trailing slot.
class RedHeaderAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const RedHeaderAction({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(label, style: const TextStyle(fontFamily: 'DM Sans',
            fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}
