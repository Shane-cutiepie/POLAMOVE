import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'red_header.dart';

/// App identity and project attribution. This is a pushed route, so the
/// header's back button falls through to the default `Navigator.maybePop`.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        const RedHeader(
          title: 'About PolaMove',
          subtitle: 'App information',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(15, 16, 15, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // App identity
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border, width: 1.5),
                ),
                child: Column(children: [
                  Container(width: 64, height: 64,
                    decoration: BoxDecoration(color: AppColors.primaryTint,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            width: 1.5)),
                    child: const Center(
                        child: Text('🛺', style: TextStyle(fontSize: 30)))),
                  const SizedBox(height: 12),
                  const Text('PolaMove', style: TextStyle(fontFamily: 'Syne',
                      fontSize: 20, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  const Text('Version 1.0.0',
                      style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                          color: AppColors.textTertiary)),
                  const SizedBox(height: 10),
                  const Text(
                    'A tricycle ride-hailing and transport management app '
                    'for Polangui, Albay.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                        height: 1.5, color: AppColors.textSecondary),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              // Attribution
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 1.5),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Developed by the PolaMove Development Team',
                      style: TextStyle(fontFamily: 'Syne', fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  const Text(
                    'PolaMove is a capstone project of Bachelor of Science in '
                    'Information Systems students at Bicol University '
                    'Polangui Campus.',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                        height: 1.5, color: AppColors.textSecondary),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text('PolaMove v1.0.0 · Polangui, Albay',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                        color: AppColors.textTertiary)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
