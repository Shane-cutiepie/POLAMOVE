import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'red_header.dart';

/// Full informed consent form. Pushed from the research disclosure screen as
/// a normal route, so the header's back button falls through to the default
/// `Navigator.maybePop` and returns to the disclosure.
class ConsentFormScreen extends StatelessWidget {
  const ConsentFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        const RedHeader(
          title: 'Informed Consent Form',
          subtitle: 'Pending BUERB approval',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            // TODO: Replace with the BUERB-approved Informed Consent Form text.
            children: const [
              _Section(title: 'Purpose of the Study',
                  body: 'This section is pending BUERB approval.'),
              _Section(title: 'Procedures',
                  body: 'This section is pending BUERB approval.'),
              _Section(title: 'Voluntary Participation',
                  body: 'This section is pending BUERB approval.'),
              _Section(title: 'Confidentiality',
                  body: 'This section is pending BUERB approval.'),
              _Section(title: 'Risks and Benefits',
                  body: 'This section is pending BUERB approval.'),
              _Section(title: 'Contact Information',
                  body: 'This section is pending BUERB approval.'),
            ],
          ),
        ),
      ]),
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
