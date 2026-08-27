import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/research_notice.dart';
import 'consent_form_screen.dart';

/// Research participation disclosure required by the BUERB submission.
///
/// Shown once per installation, per account — see [maybeShow]. The user can
/// only leave by tapping the agree button: no back button, no
/// swipe-to-dismiss.
class ResearchDisclosureScreen extends StatelessWidget {
  const ResearchDisclosureScreen({super.key});

  static String _prefsKey(String uid) => 'research_disclosure_seen_$uid';

  /// Storing this on the user document alone wouldn't re-show it after a
  /// reinstall, and storing it only locally wouldn't distinguish two
  /// accounts on one device — so the flag is local, keyed by uid.
  ///
  /// Called from each home screen's initState, the same place
  /// SoundService.loadPreference() and MessageAlertService.start() already
  /// run, which covers all three entry paths: signup, login, and splash
  /// restore.
  static Future<void> maybeShow(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey(uid)) ?? false) return;
    if (!context.mounted) return;

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ResearchDisclosureScreen(),
      fullscreenDialog: true,
    ));
  }

  /// The flag is written only here, after the user taps agree — never when
  /// the screen is merely shown.
  Future<void> _agree(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey(uid), true);
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(children: [
          const _DisclosureHeader(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, viewport) {
                return SingleChildScrollView(
                  padding: EdgeInsets.only(
                      top: 22, bottom: 24 + MediaQuery.of(context).padding.bottom),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: viewport.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const _DisclosureCard(),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _AgreeButton(onTap: () => _agree(context)),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _ViewConsentButton(onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const ConsentFormScreen()))),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ════════════════════════════════════════════════════

/// Matches the app's red header treatment (gradient over the brand red,
/// SafeArea, Syne title) but with no back button — this screen cannot be
/// dismissed except by agreeing.
class _DisclosureHeader extends StatelessWidget {
  const _DisclosureHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      child: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(1.0, -1.0), radius: 1.2,
              colors: [Color(0x1CFFFFFF), Colors.transparent])))),
        SafeArea(bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Text(kResearchDisclosureTitle,
                style: const TextStyle(fontFamily: 'Syne', fontSize: 15,
                    fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

/// Card holding the headline and the five disclosure paragraphs. Matches the
/// card treatment used elsewhere in the app (e.g. about_screen.dart).
class _DisclosureCard extends StatelessWidget {
  const _DisclosureCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(kResearchDisclosureHeadline,
            style: TextStyle(fontFamily: 'Syne', fontSize: 18,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary,
                height: 1.3)),
        const SizedBox(height: 16),
        const _Paragraph(kResearchDisclosureIntro),
        const _Paragraph(kResearchDisclosureDataUse),
        const _Paragraph(kResearchDisclosureVoluntary),
        const _Paragraph(kResearchDisclosureConfidentiality),
        const _Paragraph(kResearchDisclosureContact, last: true),
      ]),
    );
  }
}

class _Paragraph extends StatelessWidget {
  final String text;
  final bool last;
  const _Paragraph(this.text, {this.last = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Text(text, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13,
          fontWeight: FontWeight.w500, height: 1.6, color: AppColors.textSecondary)),
    );
  }
}

class _AgreeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AgreeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: double.infinity,
      child: ElevatedButton(onPressed: onTap,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
            foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
        child: const Text(kResearchDisclosureAgreeButton, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Syne', fontSize: 14,
                fontWeight: FontWeight.w700, letterSpacing: 0.3))));
  }
}

class _ViewConsentButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewConsentButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: double.infinity,
      child: OutlinedButton(onPressed: onTap,
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: const BorderSide(color: Color(0x1C14142A), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        child: const Text(kResearchDisclosureViewConsentButton,
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 13, fontWeight: FontWeight.w600))));
  }
}
