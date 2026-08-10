import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/validators.dart';

/// Re-authenticates with the current password, then sets a new one.
///
/// The email comes from the Auth user, which is authoritative for the
/// credential. The `users/{uid}` copy can be ahead of it — an email change
/// writes Firestore immediately but only moves the Auth credential once the
/// user clicks the verification link — so re-authenticating with the Firestore
/// value would fail with an address the user believes is correct.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _currentObscure = true;
  bool _newObscure = true;
  bool _confirmObscure = true;
  bool _saving = false;

  final Map<String, String?> _errors = {};

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _errors['current'] =
          Validators.required(_currentCtrl.text, 'Current password');
      _errors['new'] = Validators.password(_newCtrl.text);
      _errors['confirm'] = _confirmCtrl.text != _newCtrl.text
          ? 'Passwords do not match'
          : null;
    });
    return _errors.values.every((e) => e == null);
  }

  Future<void> _submit() async {
    if (!_validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      // Shouldn't happen — every account is created with an email credential.
      _snack('You need to be signed in to change your password.');
      return;
    }

    setState(() => _saving = true);

    try {
      final cred = EmailAuthProvider.credential(
        email: email,
        password: _currentCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(_newCtrl.text);

      if (!mounted) return;
      _snack('Password changed successfully.');
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(_authErrorMessage(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not change your password. Please try again.');
    }
  }

  /// Mirrors AuthService._authErrorMessage so the wording stays consistent
  /// with the login and signup screens.
  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Your current password is incorrect.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'requires-recent-login':
        return 'Please log out and log back in before changing your password.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      default:
        return 'Something went wrong. Please try again.';
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
          'Change Password',
          style: TextStyle(
            fontFamily: 'Syne',
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _PasswordField(
            label: 'Current Password',
            placeholder: 'Enter your current password',
            controller: _currentCtrl,
            obscure: _currentObscure,
            onToggleObscure: () =>
                setState(() => _currentObscure = !_currentObscure),
            errorText: _errors['current'],
          ),
          const SizedBox(height: 14),
          _PasswordField(
            label: 'New Password',
            placeholder: 'At least 6 characters',
            controller: _newCtrl,
            obscure: _newObscure,
            onToggleObscure: () => setState(() => _newObscure = !_newObscure),
            errorText: _errors['new'],
          ),
          const SizedBox(height: 14),
          _PasswordField(
            label: 'Confirm New Password',
            placeholder: 'Re-enter your new password',
            controller: _confirmCtrl,
            obscure: _confirmObscure,
            onToggleObscure: () =>
                setState(() => _confirmObscure = !_confirmObscure),
            errorText: _errors['confirm'],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
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
                  : const Text('Change Password',
                      style: TextStyle(fontFamily: 'Syne', fontSize: 15,
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final String label;
  final String placeholder;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final String? errorText;

  const _PasswordField({
    required this.label,
    required this.placeholder,
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
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
        obscureText: obscure,
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14,
            fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: placeholder,
          errorText: errorText,
          suffixIcon: GestureDetector(
            onTap: onToggleObscure,
            child: Icon(
                obscure ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                color: AppColors.textTertiary, size: 18),
          ),
        ),
      ),
    ]);
  }
}
