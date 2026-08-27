import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'red_header.dart';

/// Terms of use. This is a pushed route, so the header's back button falls
/// through to the default `Navigator.maybePop`.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        const RedHeader(
          title: 'Terms and Conditions',
          subtitle: 'Last updated August 2026',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: const [
              _Disclaimer(),
              SizedBox(height: 18),
              _Section(
                title: 'Service description',
                body: 'PolaMove connects passengers with tricycle drivers '
                    'affiliated with the Polangui Tricycle Operators and '
                    'Drivers Association (TODA) within Polangui, Albay. The '
                    'app is a booking tool: it shows available drivers, '
                    'records trip details, and lets a passenger and a driver '
                    'find each other.',
              ),
              _Section(
                title: 'Eligibility',
                body: 'Users must provide accurate details when registering, '
                    'including their name, phone number, email address, and '
                    'barangay. Drivers must additionally submit valid vehicle '
                    'and licence documents, and must be approved by an '
                    'administrator before they can accept bookings. An '
                    'application with unreadable or mismatched documents may '
                    'be rejected.',
              ),
              _Section(
                title: 'Fares and payment',
                body: 'Fares are calculated by ride type and are shown before '
                    'a booking is confirmed. Payment is cash only, paid '
                    'directly to the driver at the end of the trip. PolaMove '
                    'does not process payments and holds no funds at any '
                    'point.',
              ),
              _Section(
                title: 'Conduct',
                body: 'Passengers and drivers are expected to treat each '
                    'other respectfully. Drivers must follow traffic '
                    'regulations and the rules of the Polangui TODA. '
                    'Behaviour that puts either party at risk may lead to an '
                    'account being reviewed.',
              ),
              _Section(
                title: 'Cancellation',
                body: 'Either party may cancel a booking before the trip '
                    'begins. Repeated cancellation may result in an account '
                    'being reviewed by an administrator.',
              ),
              _Section(
                title: 'Limitation of liability',
                body: 'PolaMove facilitates bookings between passengers and '
                    'drivers. It does not operate vehicles and does not '
                    'employ drivers, and it is not responsible for incidents '
                    'occurring during a trip. Responsibility for the vehicle '
                    'and the journey rests with the driver and operator.',
              ),
              _Section(
                title: 'Changes to these terms',
                body: 'These terms may be updated as the service changes. '
                    'Continued use of the app after an update constitutes '
                    'acceptance of the revised terms.',
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'This is a capstone project. These terms are provided for '
      'demonstration purposes.',
      style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
          fontStyle: FontStyle.italic, height: 1.5,
          color: AppColors.textTertiary),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontFamily: 'Syne', fontSize: 14,
            fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13,
            fontWeight: FontWeight.w500, height: 1.6,
            color: AppColors.textSecondary)),
      ]),
    );
  }
}
