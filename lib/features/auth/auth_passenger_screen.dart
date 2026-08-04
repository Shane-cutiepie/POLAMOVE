import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/validators.dart';
import '../passenger/passenger_home_screen.dart';

class AuthPassengerScreen extends StatefulWidget {
  const AuthPassengerScreen({super.key});

  @override
  State<AuthPassengerScreen> createState() => _AuthPassengerScreenState();
}

class _AuthPassengerScreenState extends State<AuthPassengerScreen> {
  bool _isSignUp = true;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  final Map<String, String?> _errors = {};

  // Sign Up controllers
  final _fnCtrl = TextEditingController();
  final _lnCtrl = TextEditingController();
  final _phCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();

  // Log In controllers
  final _liPhCtrl = TextEditingController();
  final _liPwCtrl = TextEditingController();

  bool _validateSignUp() {
    setState(() {
      _errors['firstName'] = Validators.name(_fnCtrl.text, 'First name');
      _errors['lastName'] = Validators.name(_lnCtrl.text, 'Last name');
      _errors['phone'] = Validators.phone(_phCtrl.text);
      _errors['password'] = Validators.password(_pwCtrl.text);
    });
    return _errors.values.every((e) => e == null);
  }

  Future<void> _submitSignUp() async {
    if (!_validateSignUp()) return;
    setState(() => _isSubmitting = true);
    try {
      await AuthService.signUpPassenger(
        firstName: _fnCtrl.text,
        lastName: _lnCtrl.text,
        phone: _phCtrl.text,
        password: _pwCtrl.text,
      );
      if (!mounted) return;
      _goToHome();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitLogIn() async {
    setState(() => _isSubmitting = true);
    try {
      await AuthService.logIn(phone: _liPhCtrl.text, password: _liPwCtrl.text);
      if (!mounted) return;
      _goToHome();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _fnCtrl.dispose();
    _lnCtrl.dispose();
    _phCtrl.dispose();
    _pwCtrl.dispose();
    _liPhCtrl.dispose();
    _liPwCtrl.dispose();
    super.dispose();
  }

  void _goToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PassengerHomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                child: _isSignUp ? _buildSignUp() : _buildLogIn(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: AppColors.primary,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1.0, -1.0),
                  radius: 1.2,
                  colors: [Color(0x1CFFFFFF), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 46),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _TabButton(
                          label: 'Sign Up',
                          selected: _isSignUp,
                          onTap: () => setState(() => _isSignUp = true),
                        ),
                        _TabButton(
                          label: 'Log In',
                          selected: !_isSignUp,
                          onTap: () => setState(() => _isSignUp = false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 13),
                  const _PolaMoveLogo(fontSize: 25),
                  const SizedBox(height: 3),
                  Text(
                    'PASSENGER',
                    style: TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(0.62),
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignUp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _FormField(label: 'First Name', controller: _fnCtrl, placeholder: 'Maria',
                errorText: _errors['firstName'])),
            const SizedBox(width: 8),
            Expanded(child: _FormField(label: 'Last Name', controller: _lnCtrl, placeholder: 'Santos',
                errorText: _errors['lastName'])),
          ],
        ),
        const SizedBox(height: 12),
        _FormField(label: 'Phone', controller: _phCtrl, placeholder: '09XX XXX XXXX',
            keyboardType: TextInputType.phone, errorText: _errors['phone']),
        const SizedBox(height: 12),
        _FormField(label: 'Password', controller: _pwCtrl, placeholder: 'Create password',
            obscure: _obscurePassword,
            onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
            errorText: _errors['password']),
        const SizedBox(height: 20),
        _PrimaryButton(label: _isSubmitting ? 'Creating Account…' : 'Create Account →',
            onTap: _isSubmitting ? null : _submitSignUp),
        const SizedBox(height: 10),
        _GhostButton(label: '← Back', onTap: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _buildLogIn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormField(label: 'Phone', controller: _liPhCtrl, placeholder: '09XX XXX XXXX',
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        _FormField(label: 'Password', controller: _liPwCtrl, placeholder: 'Your password',
            obscure: _obscurePassword,
            onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword)),
        const SizedBox(height: 20),
        _PrimaryButton(label: _isSubmitting ? 'Logging In…' : 'Log In →',
            onTap: _isSubmitting ? null : _submitLogIn),
        const SizedBox(height: 10),
        _GhostButton(label: '← Back', onTap: () => Navigator.of(context).pop()),
      ],
    );
  }
}

// ── Shared Widgets ──────────────────────────────────

class _PolaMoveLogo extends StatelessWidget {
  final double fontSize;
  const _PolaMoveLogo({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final letter in ['P', 'o', 'l', 'a', 'M'])
          Text(letter, style: TextStyle(fontFamily: 'Syne', fontSize: fontSize,
              fontWeight: FontWeight.w800, color: Colors.white, height: 1, letterSpacing: -0.5)),
        SizedBox(width: fontSize * 0.68, height: fontSize * 0.68,
            child: CustomPaint(painter: _WheelPainter())),
        for (final letter in ['v', 'e'])
          Text(letter, style: TextStyle(fontFamily: 'Syne', fontSize: fontSize,
              fontWeight: FontWeight.w800, color: Colors.white, height: 1, letterSpacing: -0.5)),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white..strokeWidth = 2.5
        ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final fill = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final spoke = Paint()..color = Colors.white..strokeWidth = 1.6..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1.5;
    canvas.drawCircle(c, r, paint);
    canvas.drawCircle(c, size.width * 0.125, fill);
    final offsets = [[1.0, 0.0], [0.707, 0.707], [0.0, 1.0], [-0.707, 0.707]];
    final inner = size.width * 0.125;
    for (final o in offsets) {
      canvas.drawLine(Offset(c.dx + o[0] * inner, c.dy + o[1] * inner),
          Offset(c.dx + o[0] * r, c.dy + o[1] * r), spoke);
      canvas.drawLine(Offset(c.dx - o[0] * inner, c.dy - o[1] * inner),
          Offset(c.dx - o[0] * r, c.dy - o[1] * r), spoke);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withOpacity(0.17), blurRadius: 10, offset: const Offset(0, 2))]
                : [],
          ),
          child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 13, fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : Colors.white.withOpacity(0.58))),
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final String placeholder;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final String? errorText;

  const _FormField({required this.label, required this.placeholder, required this.controller,
      this.keyboardType, this.obscure = false, this.onToggleObscure, this.errorText});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.7)),
      const SizedBox(height: 5),
      TextFormField(
        controller: controller, keyboardType: keyboardType, obscureText: obscure,
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14,
            fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: placeholder, errorText: errorText,
          suffixIcon: onToggleObscure != null
              ? GestureDetector(onTap: onToggleObscure,
                  child: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.textTertiary, size: 18))
              : null),
      ),
    ]);
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: double.infinity,
      child: ElevatedButton(onPressed: onTap,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
            foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0, shadowColor: AppColors.primary.withOpacity(0.38)),
        child: Text(label, style: const TextStyle(fontFamily: 'Syne', fontSize: 14,
            fontWeight: FontWeight.w700, letterSpacing: 0.3))));
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: double.infinity,
      child: OutlinedButton(onPressed: onTap,
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: const BorderSide(color: Color(0x1C14142A), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
        child: Text(label, style: const TextStyle(fontFamily: 'DM Sans',
            fontSize: 13, fontWeight: FontWeight.w600))));
  }
}