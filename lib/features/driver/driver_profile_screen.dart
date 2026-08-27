import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../role_selection/role_selection_screen.dart';
import '../shared/about_screen.dart';
import '../shared/avatar_picker_sheet.dart';
import '../shared/change_password_screen.dart';
import '../shared/edit_profile_screen.dart';
import '../shared/help_support_screen.dart';
import '../shared/notification_settings_screen.dart';
import '../shared/red_header.dart';
import '../shared/user_avatar.dart';
import 'edit_vehicle_info_screen.dart';

class DriverProfileScreen extends StatelessWidget {
  /// Returns the bottom-nav shell to the Home tab. This screen is a tab, not
  /// a pushed route, so there is nothing for `Navigator.pop` to pop.
  final VoidCallback? onBack;

  const DriverProfileScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      RedHeader(
        title: 'Profile',
        subtitle: 'Your account and vehicle details',
        onBack: onBack,
      ),
      Expanded(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: AuthService.driverStream(FirebaseAuth.instance.currentUser!.uid),
        builder: (context, driverSnap) {
          if (driverSnap.hasError) {
            return const Center(child: Text('Could not load profile',
                style: TextStyle(fontFamily: 'DM Sans',
                    color: AppColors.textSecondary)));
          }
          if (!driverSnap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }

          final driver = driverSnap.data!.data() ?? {};

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: AuthService.userStream(FirebaseAuth.instance.currentUser!.uid),
            builder: (context, userSnap) {
              final user = userSnap.data?.data() ?? {};

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _ProfileHeader(
                    firstName: user['firstName'] ?? '—',
                    lastName: user['lastName'] ?? '',
                    phone: user['phone'] ?? '—',
                    barangay: user['barangay'] ?? '—',
                    isApproved: driver['status'] == 'approved',
                    avatarIndex: (user['avatarIndex'] ?? 0) as int,
                    avatarUrl: user['avatarUrl'] as String?,
                  ),
                  const SizedBox(height: 16),
                  _StatsRow(
                    totalRides: driver['totalRides'] ?? 0,
                    earnings: (driver['totalEarnings'] ?? 0).toDouble(),
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel('Vehicle & License'),
                  const SizedBox(height: 12),
                  _InfoCard(
                    rows: [
                      _InfoRow(label: 'Plate No.', value: driver['plateNo'] ?? '—'),
                      _InfoRow(label: 'License No.', value: driver['licenseNo'] ?? '—'),
                      _InfoRow(label: 'License Expiry', value: driver['licenseExpiry'] ?? '—'),
                    ],
                    onEdit: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EditVehicleInfoScreen())),
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel('Documents'),
                  const SizedBox(height: 12),
                  _MenuCard(
                    items: [
                      _MenuItem(
                        icon: Icons.badge_outlined,
                        label: "Driver's License",
                        trailing: const _StatusPill(label: 'Verified', isPositive: true),
                        onTap: () => _showSoon(context, 'Viewing document'),
                      ),
                      _MenuItem(
                        icon: Icons.description_outlined,
                        label: 'OR / CR',
                        trailing: const _StatusPill(label: 'Verified', isPositive: true),
                        onTap: () => _showSoon(context, 'Viewing document'),
                      ),
                      _MenuItem(
                        icon: Icons.assignment_outlined,
                        label: 'Barangay Clearance',
                        trailing: const _StatusPill(label: 'Verified', isPositive: true),
                        onTap: () => _showSoon(context, 'Viewing document'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _SectionLabel('Settings'),
                  const SizedBox(height: 12),
                  _MenuCard(
                    items: [
                      _MenuItem(
                        icon: Icons.person_outline,
                        label: 'Edit Personal Info',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const EditProfileScreen(isDriver: true))),
                      ),
                      _MenuItem(
                        icon: Icons.lock_outline,
                        label: 'Change Password',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const ChangePasswordScreen())),
                      ),
                      _MenuItem(
                        icon: Icons.notifications_none_rounded,
                        label: 'Notification Settings',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const NotificationSettingsScreen())),
                      ),
                      _MenuItem(
                        icon: Icons.help_outline,
                        label: 'Help & Support',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const HelpSupportScreen())),
                      ),
                      _MenuItem(
                        icon: Icons.info_outline,
                        label: 'About PolaMove',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const AboutScreen())),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _LogoutButton(onTap: () => _confirmLogout(context)),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'PolaMove v1.0.0',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
        ),
      ),
    ]);
  }

  static void _showSoon(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$action is not available yet.',
          style: const TextStyle(fontFamily: 'DM Sans'),
        ),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Log Out',
          style: TextStyle(
            fontFamily: 'Syne',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          'Are you sure you want to log out of your driver account?',
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await AuthService.logOutDriver();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
                (route) => false,
              );
            },
            child: const Text(
              'Log Out',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String firstName;
  final String lastName;
  final String phone;
  final String barangay;
  final bool isApproved;
  final int avatarIndex;
  final String? avatarUrl;

  const _ProfileHeader({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.barangay,
    required this.isApproved,
    required this.avatarIndex,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => showAvatarPickerSheet(context, avatarIndex),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: UserAvatar(
                avatarUrl: avatarUrl,
                avatarIndex: avatarIndex,
                size: 64,
                emojiSize: 28,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$firstName $lastName',
                  style: const TextStyle(
                    fontFamily: 'Syne',
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$phone · $barangay',
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _StatusPill(
                  label: isApproved ? 'Approved Driver' : 'Pending Approval',
                  isPositive: isApproved,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int totalRides;
  final double earnings;

  const _StatsRow({
    required this.totalRides,
    required this.earnings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatTile(value: '$totalRides', label: 'Total Rides')),
        const SizedBox(width: 12),
        Expanded(child: _StatTile(
            value: '₱${earnings.toStringAsFixed(0)}', label: 'Earnings')),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;

  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontWeight: FontWeight.w500,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Syne',
        fontWeight: FontWeight.w700,
        fontSize: 14,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> rows;
  final VoidCallback onEdit;

  const _InfoCard({required this.rows, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        children: [
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    r.label,
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    r.value,
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Edit Vehicle Info',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });
}

class _MenuCard extends StatelessWidget {
  final List<_MenuItem> items;
  const _MenuCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            InkWell(
              onTap: items[i].onTap,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(i == 0 ? 16 : 0),
                bottom: Radius.circular(i == items.length - 1 ? 16 : 0),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(items[i].icon, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        items[i].label,
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (items[i].trailing != null) items[i].trailing!,
                    if (items[i].trailing == null)
                      const Icon(Icons.chevron_right_rounded,
                          size: 20, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
            if (i != items.length - 1)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool isPositive;

  const _StatusPill({required this.label, required this.isPositive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isPositive ? AppColors.successTint : const Color(0x1AB45309),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'DM Sans',
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: isPositive ? AppColors.success : AppColors.warning,
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.primary),
        label: const Text(
          'Log Out',
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.primary,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}