import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/profile_avatars.dart';
import '../../core/services/cloudinary_service.dart';

final ImagePicker _picker = ImagePicker();

/// Bottom sheet for picking a profile avatar — either a real photo upload or
/// one of the 16 preset icons. Writes to `users/{uid}` and closes.
///
/// Shared by both profile screens so the passenger and driver pickers cannot
/// drift apart.
///
/// Scroll-controlled on purpose: 16 avatars in a 4-column grid are taller than
/// the 9/16 of the screen a default modal sheet is given, so the grid scrolls
/// inside a DraggableScrollableSheet rather than overflowing its bottom edge.
/// Same pattern as showLocationPicker in location_picker_sheet.dart.
Future<void> showAvatarPickerSheet(
    BuildContext context, int currentIndex) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      // 0.65 fits the whole grid without scrolling on a typical phone; on a
      // short screen the grid scrolls instead of being clipped.
      initialChildSize: 0.65, maxChildSize: 0.9, minChildSize: 0.4,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.surfaceStrong,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 18),
              const Text('Choose Your Avatar',
                  style: TextStyle(fontFamily: 'Syne', fontSize: 16,
                      fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('Pick an icon to show on your profile',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          // Upload options — fixed above the grid rather than scrolling with
          // it, so they're always visible without having to scroll up.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(children: [
              _UploadOption(
                icon: Icons.camera_alt_rounded,
                label: 'Take a Photo',
                subtitle: 'Use your camera to take a profile picture',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUploadPhoto(context, ImageSource.camera);
                },
              ),
              const SizedBox(height: 10),
              _UploadOption(
                icon: Icons.photo_library_rounded,
                label: 'Choose from Gallery',
                subtitle: 'Select a photo from your gallery',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUploadPhoto(context, ImageSource.gallery);
                },
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 14),
              const Align(alignment: Alignment.centerLeft,
                  child: Text('Or pick an icon', style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary))),
            ]),
          ),
          // The grid is the sheet's scrollable, so it takes the sheet's
          // controller and drives drag-to-resize. The bottom pad keeps the last
          // row clear of the gesture bar / home indicator.
          Expanded(
            child: GridView.count(
              controller: controller,
              crossAxisCount: 4,
              padding: EdgeInsets.fromLTRB(20, 22, 20,
                  32 + MediaQuery.of(sheetContext).padding.bottom),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: List.generate(kProfileAvatars.length, (i) {
                final selected = i == currentIndex;
                return GestureDetector(
                  onTap: () => _selectPreset(sheetContext, i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primaryTint : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : AppColors.border,
                          width: 1.5),
                    ),
                    child: Center(
                        child: Text(kProfileAvatars[i],
                            style: const TextStyle(fontSize: 26))),
                  ),
                );
              }),
            ),
          ),
        ]),
      ),
    ),
  );
}

/// Writes the selection, then closes. The sheet is dismissed first so the
/// tap always feels immediate; a failed write surfaces on the screen behind.
///
/// Clears avatarUrl — picking a preset is the only way to remove an uploaded
/// photo (see Part 5 of the spec this implements: no separate "Remove photo"
/// control). avatarIndex is the switch between the two right up until this
/// write, since resolution everywhere else treats a non-null avatarUrl as
/// always winning regardless of avatarIndex's value.
Future<void> _selectPreset(BuildContext sheetContext, int index) async {
  final navigator = Navigator.of(sheetContext);
  final messenger = ScaffoldMessenger.of(sheetContext);
  final uid = FirebaseAuth.instance.currentUser?.uid;

  navigator.pop();
  if (uid == null) return;

  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'avatarIndex': index, 'avatarUrl': null});
  } catch (_) {
    messenger.showSnackBar(SnackBar(
      content: const Text('Could not save your avatar. Please try again.',
          style: TextStyle(fontFamily: 'DM Sans')),
      backgroundColor: AppColors.primaryDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

/// Picks a photo, uploads it to Cloudinary, and writes the URL. Called after
/// the sheet has already closed, so it uses [context] captured before that —
/// sheetContext is unmounted by the time this runs.
///
/// avatarIndex is deliberately left untouched here: a user who uploads, then
/// later picks a preset, should get that preset rather than a stale photo —
/// which only works if avatarIndex was never disturbed by the upload in the
/// first place.
Future<void> _pickAndUploadPhoto(BuildContext context, ImageSource source) async {
  final messenger = ScaffoldMessenger.of(context);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final XFile? picked = await _picker.pickImage(
      source: source, imageQuality: 70, maxWidth: 512);
  if (picked == null) return;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(const SnackBar(
    content: Text('Uploading photo…', style: TextStyle(fontFamily: 'DM Sans')),
    backgroundColor: AppColors.textPrimary,
    behavior: SnackBarBehavior.floating,
    duration: Duration(seconds: 30),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12))),
  ));

  try {
    final url = await CloudinaryService.uploadDocument(
        File(picked.path), publicIdHint: 'avatar');

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'avatarUrl': url,
    });

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: const Text('Profile photo updated.',
          style: TextStyle(fontFamily: 'DM Sans')),
      backgroundColor: AppColors.textPrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  } on CloudinaryException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(e.message, style: const TextStyle(fontFamily: 'DM Sans')),
      backgroundColor: AppColors.primaryDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  } catch (_) {
    // The upload itself succeeded but writing the URL to Firestore failed —
    // distinct from a CloudinaryException, but needs the same treatment:
    // tell the user, and leave their existing avatar in place.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: const Text('Could not update your photo. Please try again.',
          style: TextStyle(fontFamily: 'DM Sans')),
      backgroundColor: AppColors.primaryDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

/// One upload option row — same structure and styling as _PickerOption in
/// auth_driver_screen.dart (a private widget there, so replicated here
/// rather than shared across files).
class _UploadOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _UploadOption({required this.icon, required this.label,
      required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 1.5)),
        child: Row(children: [
          Container(width: 46, height: 46,
            decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.22))),
            child: Icon(icon, color: AppColors.primary, size: 22)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontFamily: 'Syne', fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
        ]),
      ),
    );
  }
}
