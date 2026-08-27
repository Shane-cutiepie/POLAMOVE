import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/ride_service.dart';
import '../role_selection/role_selection_screen.dart';
import '../shared/about_screen.dart';
import '../shared/avatar_picker_sheet.dart';
import '../shared/change_password_screen.dart';
import '../shared/edit_profile_screen.dart';
import '../shared/help_support_screen.dart';
import '../shared/notification_settings_screen.dart';
import '../shared/privacy_screen.dart';
import '../shared/terms_screen.dart';
import '../shared/user_avatar.dart';

class PassengerProfileScreen extends StatelessWidget {
  /// Returns the bottom-nav shell to the Home tab. This screen is a tab, not
  /// a pushed route, so there is nothing for `Navigator.pop` to pop.
  final VoidCallback? onBack;

  const PassengerProfileScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: AuthService.userStream(FirebaseAuth.instance.currentUser!.uid),
      builder: (context, userSnap) {
        if (userSnap.hasError) {
          return const Center(child: Text('Could not load profile',
              style: TextStyle(fontFamily: 'DM Sans',
                  color: AppColors.textSecondary)));
        }
        if (!userSnap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }

        final user = userSnap.data!.data() ?? {};
        final fullName =
            '${user['firstName'] ?? '—'} ${user['lastName'] ?? ''}'.trim();

        return _buildBody(
          context,
          name: fullName.isEmpty ? '—' : fullName,
          email: user['email'] ?? '—',
          phone: user['phone'] ?? '—',
          avatarIndex: (user['avatarIndex'] ?? 0) as int,
          avatarUrl: user['avatarUrl'] as String?,
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, {
    required String name,
    required String email,
    required String phone,
    required int avatarIndex,
    required String? avatarUrl,
  }) {
    return Column(children: [
      // Red header with avatar
      _buildHeader(context, name, avatarIndex, avatarUrl),
      // Settings list
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(15, 16, 15, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Stats row
            _buildStats(),
            const SizedBox(height: 20),
            // Account section
            _SectionLabel('Account'),
            const SizedBox(height: 8),
            _SettingsCard(items: [
              _SettingsItem(emoji: '👤', label: 'Edit Profile',
                  onTap: () => _openEditProfile(context)),
              _SettingsItem(emoji: '📱', label: 'Phone Number', value: phone,
                  onTap: () => _openEditProfile(context)),
              _SettingsItem(emoji: '🔒', label: 'Change Password',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen()))),
            ]),
            const SizedBox(height: 16),
            // Preferences section
            _SectionLabel('Preferences'),
            const SizedBox(height: 8),
            _SettingsCard(items: [
              _SettingsItem(emoji: '🔔', label: 'Notifications',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const NotificationSettingsScreen()))),
              _SettingsItem(emoji: '🗺️', label: 'Default Location',
                  value: 'Polangui Municipal Hall',
                  onTap: () => _showSoon(context, 'Changing your default location')),
            ]),
            const SizedBox(height: 16),
            // Support section
            _SectionLabel('Support'),
            const SizedBox(height: 8),
            _SettingsCard(items: [
              _SettingsItem(emoji: '❓', label: 'Help & Support',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const HelpSupportScreen()))),
              _SettingsItem(emoji: 'ℹ️', label: 'About PolaMove',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AboutScreen()))),
              _SettingsItem(emoji: '📋', label: 'Terms & Conditions',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TermsScreen()))),
              _SettingsItem(emoji: '🛡️', label: 'Privacy Policy',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PrivacyScreen()))),
            ]),
            const SizedBox(height: 16),
            // App version
            Center(child: Text('PolaMove v1.0.0 · Polangui, Albay',
                style: const TextStyle(fontSize: 11, color: AppColors.textTertiary))),
            const SizedBox(height: 16),
            // Logout button
            SizedBox(width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmLogout(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: BorderSide(color: AppColors.primary.withOpacity(0.4), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('🚪', style: TextStyle(fontSize: 15)),
                  SizedBox(width: 8),
                  Text('Log Out', style: TextStyle(fontFamily: 'Syne', fontSize: 14,
                      fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  /// Mirrors the driver profile's wording so an unbuilt feature says so
  /// plainly instead of doing nothing when tapped.
  static void _showSoon(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$action is not available yet.',
          style: const TextStyle(fontFamily: 'DM Sans')),
      backgroundColor: AppColors.textPrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _openEditProfile(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const EditProfileScreen(isDriver: false)));
  }

  /// Totals are derived from the passenger's own ride documents — there is no
  /// stored counter on the user document to drift from.
  Widget _buildStats() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: RideService.passengerHistory(),
      builder: (context, rideSnap) {
        final docs = rideSnap.data?.docs ?? const [];
        final completed =
            docs.where((d) => d.data()['status'] == 'completed').toList();
        final spent = completed.fold<double>(
            0, (acc, d) => acc + (d.data()['totalFare'] ?? 0).toDouble());

        return Row(children: [
          _StatCard(emoji: '🛺', value: '${completed.length}', label: 'Total Rides'),
          const SizedBox(width: 8),
          _StatCard(emoji: '💰', value: '₱${spent.toStringAsFixed(0)}',
              label: 'Total Spent'),
        ]);
      },
    );
  }

  Widget _buildHeader(BuildContext context, String name, int avatarIndex,
      String? avatarUrl) {
    return Container(
      color: AppColors.primary,
      child: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0.9, -1.0), radius: 1.2,
              colors: [Color(0x1CFFFFFF), Colors.transparent])))),
        SafeArea(bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            child: Row(children: [
              // Matches RedHeader's back control, since this tab has its own
              // taller header rather than using RedHeader directly.
              GestureDetector(
                onTap: onBack ?? () => Navigator.maybePop(context),
                child: Container(width: 31, height: 31,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white.withOpacity(0.2))),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 20)),
              ),
              const SizedBox(width: 10),
              // Avatar
              GestureDetector(
                onTap: () => showAvatarPickerSheet(context, avatarIndex),
                child: Container(width: 60, height: 60,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.4), width: 2)),
                  child: UserAvatar(avatarUrl: avatarUrl, avatarIndex: avatarIndex,
                      size: 60, emojiSize: 28)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontFamily: 'Syne',
                    fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 2),
                Text('Passenger · Polangui',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
              ])),
            ]),
          ),
        ),
      ]),
    );
  }

  void _confirmLogout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.fromLTRB(20, 14, 20,
            32 + MediaQuery.of(sheetContext).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.surfaceStrong,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),
          const Text('🚪', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          const Text('Log Out?', style: TextStyle(fontFamily: 'Syne', fontSize: 18,
              fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('You will be returned to the role selection screen.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 22),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await AuthService.logOut();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                  (route) => false,
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0),
              child: const Text('Yes, Log Out', style: TextStyle(fontFamily: 'Syne',
                  fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: Color(0x1C14142A), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: const Text('Cancel', style: TextStyle(fontFamily: 'DM Sans',
                  fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _StatCard({required this.emoji, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontFamily: 'Syne', fontSize: 15,
              fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary,
              fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: const TextStyle(fontSize: 11,
        fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.8));
  }
}

class _SettingsCard extends StatelessWidget {
  final List<_SettingsItem> items;
  const _SettingsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1.5)),
      child: Column(children: List.generate(items.length * 2 - 1, (i) {
        if (i.isOdd) return const Divider(height: 1, indent: 52, color: Color(0x1C14142A));
        return items[i ~/ 2];
      })),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final String emoji;
  final String label;
  final String? value;
  final VoidCallback onTap;

  const _SettingsItem({required this.emoji, required this.label,
      this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14,
              fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
          if (value != null) ...[
            Text(value!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 18),
        ]),
      ),
    );
  }
}