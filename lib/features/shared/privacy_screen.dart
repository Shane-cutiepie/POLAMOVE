import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'red_header.dart';

/// Privacy notice. This is a pushed route, so the header's back button falls
/// through to the default `Navigator.maybePop`.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        const RedHeader(
          title: 'Privacy Policy',
          subtitle: 'Last updated August 2026',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: const [
              _Disclaimer(),
              SizedBox(height: 18),
              _Section(
                title: 'What is collected',
                body: 'At registration PolaMove collects your name, phone '
                    'number, email address, and barangay. Drivers also '
                    'provide a plate number, licence number, licence expiry '
                    'date, preferred route, and photographs of their '
                    'documents. For each booking the app records the pickup '
                    'point, destination, fare, and timestamps. Driver '
                    'location is recorded while a driver is online.',
              ),
              _Section(
                title: 'How it is used',
                body: 'This information is used to match passengers with '
                    'nearby drivers, show trip progress while a booking is '
                    'active, maintain ride history for both parties, and '
                    'allow administrators to verify driver applications.',
              ),
              _Section(
                title: 'Location data',
                body: 'Location is collected from drivers only while they are '
                    'online, and it is cleared when they go offline. '
                    'Passenger location is not tracked.',
              ),
              _Section(
                title: 'Document and photo storage',
                body: 'Driver documents, and any profile photo you choose to '
                    'upload, are hosted by a third-party media hosting '
                    'service. Documents are accessible to administrators '
                    'for verification. Document and photo URLs are '
                    'unguessable but are not access-controlled: anyone '
                    'holding a URL can view the image. This is a '
                    'consequence of the app having no server of its own to '
                    'guard access with, and we would rather state it '
                    'plainly than leave it unsaid.',
              ),
              _Section(
                title: 'Who can see it',
                body: 'During an active booking, a passenger and a driver can '
                    'see each other\'s name and profile photo, where one is '
                    'set, and the passenger can see the driver\'s plate '
                    'number. Administrators can view driver applications and '
                    'ride records. Your data is not sold and is not shared '
                    'with third parties.',
              ),
              _Section(
                title: 'Retention',
                body: 'Ride records are retained so that both passengers and '
                    'drivers keep an accurate trip history, and so that '
                    'administrators can produce reports.',
              ),
              _Section(
                title: 'Contact',
                body: 'Questions about this policy can be directed to the '
                    'PolaMove Support Team through the Polangui TODA office.',
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
