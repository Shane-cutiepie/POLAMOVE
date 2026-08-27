import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'red_header.dart';

/// Support contact information. This is a pushed route, so the header's back
/// button falls through to the default `Navigator.maybePop`.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        const RedHeader(
          title: 'Help & Support',
          subtitle: 'Getting help with PolaMove',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(15, 16, 15, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Card(
                emoji: '🛺',
                title: 'PolaMove Support Team',
                body: 'Support for PolaMove is handled by the PolaMove Support '
                    'Team through the Polangui TODA office. Visit the office '
                    'during working hours for help with your account, a '
                    'booking, or a driver application.',
              ),
              const SizedBox(height: 12),
              _Card(
                emoji: '📋',
                title: 'Driver applications',
                body: 'New driver accounts are reviewed by an administrator. '
                    'Approval is based on the documents submitted during '
                    'registration, so make sure they are clear and readable.',
              ),
              const SizedBox(height: 12),
              _Card(
                emoji: '💵',
                title: 'Payments',
                body: 'All PolaMove trips are paid in cash directly to the '
                    'driver at the end of the ride. The app does not process '
                    'payments.',
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;

  const _Card({required this.emoji, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: const TextStyle(fontFamily: 'Syne',
                fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(body, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13,
            height: 1.5, color: AppColors.textSecondary)),
      ]),
    );
  }
}
