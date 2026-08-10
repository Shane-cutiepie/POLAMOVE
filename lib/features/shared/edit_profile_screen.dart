import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/polangui_barangays.dart';
import '../../core/utils/validators.dart';

/// Edits the name, email and (for drivers) barangay on `users/{uid}`.
///
/// The phone number is deliberately read-only: it is the document key of the
/// `phone_index` lookup that login uses, so changing it needs an index
/// migration rather than a field edit.
class EditProfileScreen extends StatefulWidget {
  final bool isDriver;

  const EditProfileScreen({super.key, required this.isDriver});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _selectedBarangay;
  String _phone = '—';
  String _originalEmail = '';

  bool _loading = true;
  bool _saving = false;
  final Map<String, String?> _errors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
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
      final data = doc.data() ?? {};
      if (!mounted) return;
      setState(() {
        _firstCtrl.text = data['firstName'] ?? '';
        _lastCtrl.text = data['lastName'] ?? '';
        _emailCtrl.text = data['email'] ?? '';
        _originalEmail = data['email'] ?? '';
        _phone = data['phone'] ?? '—';
        final barangay = data['barangay'] as String?;
        _selectedBarangay =
            kPolanguiBarangays.contains(barangay) ? barangay : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _validate() {
    setState(() {
      _errors['firstName'] = Validators.name(_firstCtrl.text, 'First name');
      _errors['lastName'] = Validators.name(_lastCtrl.text, 'Last name');
      _errors['email'] = Validators.email(_emailCtrl.text);
      if (widget.isDriver) {
        _errors['barangay'] =
            Validators.dropdown(_selectedBarangay, 'barangay');
      }
    });
    return _errors.values.every((e) => e == null);
  }

  Future<void> _save() async {
    if (!_validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    final newEmail = Validators.normalizeEmail(_emailCtrl.text);
    final emailChanged = newEmail != Validators.normalizeEmail(_originalEmail);

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'firstName': _firstCtrl.text.trim(),
        'lastName': _lastCtrl.text.trim(),
        'email': newEmail,
        if (widget.isDriver) 'barangay': _selectedBarangay,
      });

      // Firestore holds the new address immediately, but the Auth credential
      // only changes once the user confirms from their inbox.
      if (emailChanged) {
        await user.verifyBeforeUpdateEmail(newEmail);
      }

      if (!mounted) return;
      _snack(emailChanged
          ? 'Profile saved. Check your inbox to confirm your new email address.'
          : 'Profile saved.');
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(_authErrorMessage(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not save your profile. Please try again.');
    }
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered to another account.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'requires-recent-login':
        return 'Please log out and log back in before changing your email.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      default:
        return 'Could not update your email. Please try again.';
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'DM Sans')),
      backgroundColor: AppColors.primaryDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Edit Profile',
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
                _FormField(
                  label: 'First Name',
                  placeholder: 'Juan',
                  controller: _firstCtrl,
                  errorText: _errors['firstName'],
                ),
                const SizedBox(height: 14),
                _FormField(
                  label: 'Last Name',
                  placeholder: 'Dela Cruz',
                  controller: _lastCtrl,
                  errorText: _errors['lastName'],
                ),
                const SizedBox(height: 14),
                _FormField(
                  label: 'Email',
                  placeholder: 'juan@example.com',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  errorText: _errors['email'],
                ),
                if (widget.isDriver) ...[
                  const SizedBox(height: 14),
                  _DropdownField<String>(
                    label: 'Barangay',
                    placeholder: 'Select barangay…',
                    value: _selectedBarangay,
                    items: kPolanguiBarangays,
                    itemLabel: (e) => e,
                    onChanged: (val) => setState(() => _selectedBarangay = val),
                    errorText: _errors['barangay'],
                  ),
                ],
                const SizedBox(height: 14),
                _ReadOnlyField(
                  label: 'Phone Number',
                  value: _phone,
                  caption: 'Contact the administrator to change your phone number.',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.surfaceStrong,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save Changes',
                            style: TextStyle(fontFamily: 'Syne', fontSize: 15,
                                fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final String placeholder;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? errorText;

  const _FormField({
    required this.label,
    required this.placeholder,
    required this.controller,
    this.keyboardType,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11,
          fontWeight: FontWeight.w700, color: AppColors.textSecondary,
          letterSpacing: 0.7)),
      const SizedBox(height: 5),
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14,
            fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: placeholder, errorText: errorText),
      ),
    ]);
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final String placeholder;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final void Function(T?) onChanged;
  final String? errorText;

  const _DropdownField({
    required this.label,
    required this.placeholder,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11,
          fontWeight: FontWeight.w700, color: AppColors.textSecondary,
          letterSpacing: 0.7)),
      const SizedBox(height: 5),
      DropdownButtonFormField<T>(
        value: value,
        hint: Text(placeholder, style: const TextStyle(fontFamily: 'DM Sans',
            fontSize: 14, color: AppColors.textTertiary)),
        items: items.map((e) => DropdownMenuItem(value: e,
            child: Text(itemLabel(e), style: const TextStyle(fontFamily: 'DM Sans',
                fontSize: 14, fontWeight: FontWeight.w500,
                color: AppColors.textPrimary)))).toList(),
        onChanged: onChanged,
        decoration: InputDecoration(filled: true, fillColor: AppColors.surfaceAlt,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          errorText: errorText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0x1C14142A), width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0x1C14142A), width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5))),
        dropdownColor: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12)),
    ]);
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final String caption;

  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11,
          fontWeight: FontWeight.w700, color: AppColors.textSecondary,
          letterSpacing: 0.7)),
      const SizedBox(height: 5),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Text(value, style: const TextStyle(fontFamily: 'DM Sans',
            fontSize: 14, fontWeight: FontWeight.w500,
            color: AppColors.textTertiary)),
      ),
      const SizedBox(height: 6),
      Text(caption, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11,
          color: AppColors.textTertiary)),
    ]);
  }
}
