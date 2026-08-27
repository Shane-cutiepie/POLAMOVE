import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/sound_service.dart';

// TODO: Firebase respect notificationPrefs when writing notifications
/// Stores per-category notification preferences at
/// `users/{uid}.notificationPrefs`.
///
/// Storage only for now — RideService._notify does not read these yet, so
/// switching one off does not stop the notification being written.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  static const _categories = [
    ('ride', 'Ride updates', 'Driver found, arrival, and trip completion'),
    ('earnings', 'Earnings', 'Fare collected and trip payment reminders'),
    ('account', 'Account', 'Application status and document reminders'),
    ('announcement', 'Announcements', 'News from the PolaMove team and TODA'),
  ];

  Map<String, bool> _prefs = {
    'ride': true,
    'earnings': true,
    'account': true,
    'announcement': true,
  };

  bool _soundEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      final stored = doc.data()?['notificationPrefs'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        // Absent keys default to on — a missing preference should never mean
        // the user silently stops receiving something.
        _prefs = {
          for (final c in _categories) c.$1: stored?[c.$1] as bool? ?? true,
        };
        _soundEnabled = stored?['sound'] as bool? ?? true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String key, bool value) async {
    final previous = _prefs[key] ?? true;
    setState(() => _prefs[key] = value);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'notificationPrefs.$key': value,
      });
    } catch (_) {
      // Roll back so the switch can never show a preference that wasn't saved.
      if (!mounted) return;
      setState(() => _prefs[key] = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Could not save your preference. Please try again.',
            style: TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _toggleSound(bool value) async {
    final previous = _soundEnabled;
    setState(() => _soundEnabled = value);
    SoundService.setEnabled(value);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'notificationPrefs.sound': value,
      });
    } catch (_) {
      // Roll back so the switch can never show a preference that wasn't saved.
      if (!mounted) return;
      setState(() => _soundEnabled = previous);
      SoundService.setEnabled(previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Could not save your preference. Please try again.',
            style: TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Notification Settings',
          style: TextStyle(
            fontFamily: 'Syne',
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                for (final c in _categories) ...[
                  _PrefTile(
                    title: c.$2,
                    description: c.$3,
                    value: _prefs[c.$1] ?? true,
                    onChanged: (v) => _toggle(c.$1, v),
                  ),
                  const SizedBox(height: 10),
                ],
                _PrefTile(
                  title: 'Notification sounds',
                  description: 'Play a short chime for new bookings, ride '
                      'updates, and chat messages',
                  value: _soundEnabled,
                  onChanged: _toggleSound,
                ),
              ],
            ),
    );
  }
}

class _PrefTile extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrefTile({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: 'DM Sans',
                fontWeight: FontWeight.w700, fontSize: 14,
                color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(description, style: const TextStyle(fontFamily: 'DM Sans',
                fontWeight: FontWeight.w500, fontSize: 12, height: 1.4,
                color: AppColors.textSecondary)),
          ]),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
        ),
      ]),
    );
  }
}
