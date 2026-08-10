import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/polangui_barangays.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/validators.dart';
import '../driver/driver_home_screen.dart';

class AuthDriverScreen extends StatefulWidget {
  const AuthDriverScreen({super.key});

  @override
  State<AuthDriverScreen> createState() => _AuthDriverScreenState();
}

class _AuthDriverScreenState extends State<AuthDriverScreen> {
  bool _isSignUp = true;
  int _step = 1;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  final Map<String, String?> _errors = {};

  // Step 1
  final _fnCtrl = TextEditingController();
  final _lnCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _phCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  String? _selectedBarangay;

  // Step 2
  final _plateCtrl = TextEditingController();
  final _licCtrl = TextEditingController();
  final _licExpCtrl = TextEditingController();
  String? _selectedRoute;

  // Step 3
  File? _licensePhoto;
  File? _orcrPhoto;
  File? _brgyPhoto;

  // Log In
  final _liPhCtrl = TextEditingController();
  final _liPwCtrl = TextEditingController();
  bool _liObscure = true;

  final ImagePicker _picker = ImagePicker();

  final List<String> _routes = [
    'Centro – Public Market', 'Centro – Bus Terminal',
    'Centro – Bicol University', 'Centro – Hospital', 'All Routes',
  ];

  @override
  void dispose() {
    _fnCtrl.dispose(); _lnCtrl.dispose(); _dobCtrl.dispose();
    _phCtrl.dispose(); _emailCtrl.dispose(); _pwCtrl.dispose(); _plateCtrl.dispose();
    _licCtrl.dispose(); _licExpCtrl.dispose();
    _liPhCtrl.dispose(); _liPwCtrl.dispose();
    super.dispose();
  }

  bool _validateStep1() {
    setState(() {
      _errors['firstName'] = Validators.name(_fnCtrl.text, 'First name');
      _errors['lastName'] = Validators.name(_lnCtrl.text, 'Last name');
      _errors['dateOfBirth'] = Validators.date(_dobCtrl.text, 'Date of birth');
      _errors['phone'] = Validators.phone(_phCtrl.text);
      _errors['email'] = Validators.email(_emailCtrl.text);
      _errors['barangay'] = Validators.dropdown(_selectedBarangay, 'barangay');
      _errors['password'] = Validators.password(_pwCtrl.text);
    });
    return ['firstName', 'lastName', 'dateOfBirth', 'phone', 'email', 'barangay', 'password']
        .every((key) => _errors[key] == null);
  }

  bool _validateStep2() {
    setState(() {
      _errors['plateNo'] = Validators.plateNumber(_plateCtrl.text);
      _errors['licenseNo'] = Validators.licenseNumber(_licCtrl.text);
      _errors['licenseExpiry'] = Validators.date(_licExpCtrl.text, 'License expiry date');
      _errors['preferredRoute'] = Validators.dropdown(_selectedRoute, 'route');
    });
    return ['plateNo', 'licenseNo', 'licenseExpiry', 'preferredRoute']
        .every((key) => _errors[key] == null);
  }

  bool _validateStep3() {
    if (_licensePhoto == null || _orcrPhoto == null || _brgyPhoto == null) {
      _showError('Please upload all required documents');
      return false;
    }
    return true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitApplication() async {
    if (!_validateStep3()) return;
    setState(() => _isSubmitting = true);
    try {
      await AuthService.signUpDriver(
        firstName: _fnCtrl.text,
        lastName: _lnCtrl.text,
        dateOfBirth: _dobCtrl.text,
        phone: _phCtrl.text,
        email: _emailCtrl.text,
        barangay: _selectedBarangay!,
        password: _pwCtrl.text,
        plateNo: _plateCtrl.text,
        licenseNo: _licCtrl.text,
        licenseExpiry: _licExpCtrl.text,
        preferredRoute: _selectedRoute!,
        licensePhoto: _licensePhoto!,
        orcrPhoto: _orcrPhoto!,
        barangayClearancePhoto: _brgyPhoto!,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _logIn() async {
    setState(() {
      _errors['liPhone'] = Validators.loginIdentifier(_liPhCtrl.text);
      _errors['liPassword'] = Validators.required(_liPwCtrl.text, 'Password');
    });
    if (_errors['liPhone'] != null || _errors['liPassword'] != null) return;

    setState(() => _isSubmitting = true);
    try {
      await AuthService.logIn(
        identifier: _liPhCtrl.text,
        password: _liPwCtrl.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showPickerSheet(Function(File) onPicked) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.surfaceStrong,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),
          Text('Upload Document', style: TextStyle(fontFamily: 'Syne', fontSize: 16,
              fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Choose how you want to upload your photo',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 22),
          _PickerOption(
            icon: Icons.camera_alt_rounded,
            label: 'Take a Photo',
            subtitle: 'Use your camera to capture the document',
            onTap: () async {
              Navigator.pop(context);
              final XFile? photo = await _picker.pickImage(
                  source: ImageSource.camera, imageQuality: 85);
              if (photo != null) onPicked(File(photo.path));
            },
          ),
          const SizedBox(height: 10),
          _PickerOption(
            icon: Icons.photo_library_rounded,
            label: 'Choose from Gallery',
            subtitle: 'Select an existing photo from your gallery',
            onTap: () async {
              Navigator.pop(context);
              final XFile? photo = await _picker.pickImage(
                  source: ImageSource.gallery, imageQuality: 85);
              if (photo != null) onPicked(File(photo.path));
            },
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Color(0x1C14142A), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              child: const Text('Cancel', style: TextStyle(fontFamily: 'DM Sans',
                  fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  String get _badgeLabel {
    if (!_isSignUp) return 'DRIVER';
    switch (_step) {
      case 1: return 'DRIVER — STEP 1 OF 4';
      case 2: return 'DRIVER — STEP 2 OF 4';
      case 3: return 'DRIVER — STEP 3 OF 4';
      case 4: return 'DRIVER — STEP 4 OF 4';
      default: return 'DRIVER';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
              child: _isSignUp ? _buildSignUpStep() : _buildLogIn(),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.primary,
      child: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(1.0, -1.0), radius: 1.2,
              colors: [Color(0x1CFFFFFF), Colors.transparent])))),
        SafeArea(bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 44),
            child: Column(children: [
              if (_isSignUp && _step > 1)
                const SizedBox(height: 6)
              else ...[
                Container(
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(50)),
                  padding: const EdgeInsets.all(4),
                  child: Row(children: [
                    _TabButton(label: 'Sign Up', selected: _isSignUp,
                        onTap: () => setState(() { _isSignUp = true; _step = 1; })),
                    _TabButton(label: 'Log In', selected: !_isSignUp,
                        onTap: () => setState(() { _isSignUp = false; _step = 1; })),
                  ]),
                ),
                const SizedBox(height: 13),
              ],
              const _PolaMoveLogo(fontSize: 25),
              const SizedBox(height: 3),
              Text(_badgeLabel, style: TextStyle(fontFamily: 'Syne', fontSize: 11,
                  fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.62), letterSpacing: 3)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildSignUpStep() {
    switch (_step) {
      case 1: return _buildStep1();
      case 2: return _buildStep2();
      case 3: return _buildStep3();
      case 4: return _buildStep4();
      default: return _buildStep1();
    }
  }

  Widget _buildStep1() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepDots(currentStep: 1, totalSteps: 4),
      const SizedBox(height: 4),
      const _StepLabel('Personal Information'),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: _FormField(label: 'First Name', controller: _fnCtrl, placeholder: 'Carlos',
            errorText: _errors['firstName'])),
        const SizedBox(width: 8),
        Expanded(child: _FormField(label: 'Last Name', controller: _lnCtrl, placeholder: 'Reyes',
            errorText: _errors['lastName'])),
      ]),
      const SizedBox(height: 12),
      _DateField(label: 'Date of Birth', controller: _dobCtrl, placeholder: 'MM/DD/YYYY',
        errorText: _errors['dateOfBirth'],
        onTap: () async {
          final picked = await showDatePicker(context: context,
            initialDate: DateTime(1990), firstDate: DateTime(1950),
            lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
            builder: (context, child) => Theme(data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(primary: AppColors.primary)), child: child!));
          if (picked != null) _dobCtrl.text =
              '${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}';
        },
      ),
      const SizedBox(height: 12),
      _FormField(label: 'Phone Number', controller: _phCtrl, placeholder: '09XX XXX XXXX',
          keyboardType: TextInputType.phone, errorText: _errors['phone']),
      const SizedBox(height: 12),
      _FormField(label: 'Email Address', controller: _emailCtrl,
          placeholder: 'juan@email.com',
          keyboardType: TextInputType.emailAddress,
          errorText: _errors['email']),
      const SizedBox(height: 12),
      _DropdownField<String>(label: 'Barangay', value: _selectedBarangay,
          placeholder: 'Select barangay…', items: kPolanguiBarangays, itemLabel: (e) => e,
          onChanged: (val) => setState(() => _selectedBarangay = val),
          errorText: _errors['barangay']),
      const SizedBox(height: 12),
      _FormField(label: 'Password', controller: _pwCtrl, placeholder: 'Create password',
          obscure: _obscurePassword,
          onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
          errorText: _errors['password']),
      const SizedBox(height: 22),
      _PrimaryButton(label: 'Continue →',
          onTap: () { if (_validateStep1()) { setState(() => _step = 2); } }),
      const SizedBox(height: 10),
      _GhostButton(label: '← Back', onTap: () => Navigator.of(context).pop()),
    ]);
  }

  Widget _buildStep2() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepDots(currentStep: 2, totalSteps: 4),
      const SizedBox(height: 4),
      const _StepLabel('Vehicle Information'),
      const SizedBox(height: 18),
      _FormField(label: 'Tricycle Plate No.', controller: _plateCtrl,
          placeholder: 'e.g. POLO-1234', inputFormatters: [UpperCaseTextFormatter()],
          errorText: _errors['plateNo']),
      const SizedBox(height: 12),
      _FormField(label: "Driver's License No.", controller: _licCtrl,
          placeholder: 'e.g. N01-23-456789', inputFormatters: [UpperCaseTextFormatter()],
          errorText: _errors['licenseNo']),
      const SizedBox(height: 12),
      _DateField(label: 'License Expiry Date', controller: _licExpCtrl, placeholder: 'MM/DD/YYYY',
        errorText: _errors['licenseExpiry'],
        onTap: () async {
          final picked = await showDatePicker(context: context,
            initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2040),
            builder: (context, child) => Theme(data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(primary: AppColors.primary)), child: child!));
          if (picked != null) _licExpCtrl.text =
              '${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}';
        },
      ),
      const SizedBox(height: 12),
      _DropdownField<String>(label: 'Preferred Route', value: _selectedRoute,
          placeholder: 'Select route…', items: _routes, itemLabel: (e) => e,
          onChanged: (val) => setState(() => _selectedRoute = val),
          errorText: _errors['preferredRoute']),
      const SizedBox(height: 22),
      _PrimaryButton(label: 'Continue →',
          onTap: () { if (_validateStep2()) { setState(() => _step = 3); } }),
      const SizedBox(height: 10),
      _GhostButton(label: '← Back', onTap: () => setState(() => _step = 1)),
    ]);
  }

  Widget _buildStep3() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepDots(currentStep: 3, totalSteps: 4),
      const SizedBox(height: 4),
      const _StepLabel('Document Upload'),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.22))),
        child: const Text('📋 Please upload clear photos of your documents. All uploads will be reviewed by the admin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ),
      const SizedBox(height: 18),
      _DocUploadCard(label: "Driver's License",
          description: 'Front side of your valid driver\'s license',
          emoji: '🪪', imageFile: _licensePhoto,
          onTap: () => _showPickerSheet((file) => setState(() => _licensePhoto = file))),
      const SizedBox(height: 12),
      _DocUploadCard(label: 'OR/CR',
          description: 'Official Receipt & Certificate of Registration',
          emoji: '📄', imageFile: _orcrPhoto,
          onTap: () => _showPickerSheet((file) => setState(() => _orcrPhoto = file))),
      const SizedBox(height: 12),
      _DocUploadCard(label: 'Barangay Clearance',
          description: 'Clearance from your barangay in Polangui',
          emoji: '📃', imageFile: _brgyPhoto,
          onTap: () => _showPickerSheet((file) => setState(() => _brgyPhoto = file))),
      const SizedBox(height: 22),
      _PrimaryButton(label: 'Continue →',
          onTap: () { if (_validateStep3()) { setState(() => _step = 4); } }),
      const SizedBox(height: 10),
      _GhostButton(label: '← Back', onTap: () => setState(() => _step = 2)),
    ]);
  }

  Widget _buildStep4() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepDots(currentStep: 4, totalSteps: 4),
      const SizedBox(height: 4),
      const _StepLabel('Review & Submit'),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.22))),
        child: const Text('✅ Please review your information before submitting.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ),
      const SizedBox(height: 18),
      _ReviewSection(title: 'Personal Information', onEdit: () => setState(() => _step = 1), rows: [
        _ReviewRow('Name', '${_fnCtrl.text} ${_lnCtrl.text}'.trim().isEmpty ? '—' : '${_fnCtrl.text} ${_lnCtrl.text}'),
        _ReviewRow('Date of Birth', _dobCtrl.text.isEmpty ? '—' : _dobCtrl.text),
        _ReviewRow('Phone', _phCtrl.text.isEmpty ? '—' : _phCtrl.text),
        _ReviewRow('Email', _emailCtrl.text.isEmpty ? '—' : _emailCtrl.text),
        _ReviewRow('Barangay', _selectedBarangay ?? '—'),
      ]),
      const SizedBox(height: 12),
      _ReviewSection(title: 'Vehicle Information', onEdit: () => setState(() => _step = 2), rows: [
        _ReviewRow('Plate No.', _plateCtrl.text.isEmpty ? '—' : _plateCtrl.text),
        _ReviewRow('License No.', _licCtrl.text.isEmpty ? '—' : _licCtrl.text),
        _ReviewRow('License Expiry', _licExpCtrl.text.isEmpty ? '—' : _licExpCtrl.text),
        _ReviewRow('Preferred Route', _selectedRoute ?? '—'),
      ]),
      const SizedBox(height: 12),
      _ReviewSection(title: 'Documents', onEdit: () => setState(() => _step = 3), rows: [
        _ReviewRow("Driver's License", _licensePhoto != null ? '✅ Uploaded' : '❌ Missing'),
        _ReviewRow('OR/CR', _orcrPhoto != null ? '✅ Uploaded' : '❌ Missing'),
        _ReviewRow('Barangay Clearance', _brgyPhoto != null ? '✅ Uploaded' : '❌ Missing'),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x1C14142A))),
        child: const Text('📋 Your application will be reviewed by the admin. You will be notified once approved.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ),
      const SizedBox(height: 22),
      _PrimaryButton(label: _isSubmitting ? 'Submitting…' : 'Submit for Approval 🛺',
          onTap: _isSubmitting ? null : _submitApplication),
      const SizedBox(height: 10),
      _GhostButton(label: '← Back', onTap: () => setState(() => _step = 3)),
    ]);
  }

  Widget _buildLogIn() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _FormField(label: 'Email or Phone Number', controller: _liPhCtrl,
          placeholder: 'juan@email.com or 09XX XXX XXXX',
          errorText: _errors['liPhone']),
      const SizedBox(height: 12),
      _FormField(label: 'Password', controller: _liPwCtrl, placeholder: 'Your password',
          obscure: _liObscure, onToggleObscure: () => setState(() => _liObscure = !_liObscure),
          errorText: _errors['liPassword']),
      const SizedBox(height: 22),
      _PrimaryButton(label: _isSubmitting ? 'Logging In…' : 'Log In →',
          onTap: _isSubmitting ? null : _logIn),
      const SizedBox(height: 10),
      _GhostButton(label: '← Back', onTap: () => Navigator.of(context).pop()),
    ]);
  }
}

// ════════════════════════════════════════════════════
// SHARED WIDGETS
// ════════════════════════════════════════════════════

class _PickerOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _PickerOption({required this.icon, required this.label,
      required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x1C14142A), width: 1.5)),
        child: Row(children: [
          Container(width: 46, height: 46,
            decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.primary.withOpacity(0.22))),
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

class _DocUploadCard extends StatelessWidget {
  final String label;
  final String description;
  final String emoji;
  final File? imageFile;
  final VoidCallback onTap;

  const _DocUploadCard({required this.label, required this.description,
      required this.emoji, required this.imageFile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uploaded = imageFile != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: uploaded ? AppColors.primaryTint : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: uploaded ? AppColors.primary.withOpacity(0.4)
              : const Color(0x1C14142A), width: 1.5),
        ),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(12),
            child: uploaded
                ? Image.file(imageFile!, width: 56, height: 56, fit: BoxFit.cover)
                : Container(width: 56, height: 56,
                    decoration: BoxDecoration(color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x1C14142A))),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontFamily: 'Syne', fontSize: 14,
                fontWeight: FontWeight.w700,
                color: uploaded ? AppColors.primary : AppColors.textPrimary)),
            const SizedBox(height: 3),
            Text(uploaded ? 'Tap to replace photo' : description,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            if (uploaded) ...[
              const SizedBox(height: 4),
              Row(children: [
                Container(width: 6, height: 6,
                    decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                const Text('Photo ready', style: TextStyle(fontSize: 10,
                    fontWeight: FontWeight.w600, color: AppColors.success)),
              ]),
            ],
          ])),
          const SizedBox(width: 8),
          Container(width: 32, height: 32,
            decoration: BoxDecoration(
              color: uploaded ? AppColors.primary : AppColors.surfaceAlt,
              shape: BoxShape.circle,
              border: Border.all(color: uploaded ? AppColors.primary : const Color(0x1C14142A)),
            ),
            child: Icon(uploaded ? Icons.check_rounded : Icons.upload_rounded,
                color: uploaded ? Colors.white : AppColors.textTertiary, size: 16)),
        ]),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepDots({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps * 2 - 1, (i) {
        if (i.isOdd) return const SizedBox(width: 5);
        final step = i ~/ 2 + 1;
        final active = step == currentStep;
        final done = step < currentStep;
        return AnimatedContainer(duration: const Duration(milliseconds: 280),
          width: active ? 26 : 16, height: 3,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : done ? AppColors.primaryDark : AppColors.surfaceStrong,
            borderRadius: BorderRadius.circular(3)));
      }));
  }
}

class _StepLabel extends StatelessWidget {
  final String text;
  const _StepLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text, textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textTertiary));
}

class _FormField extends StatelessWidget {
  final String label;
  final String placeholder;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;

  const _FormField({required this.label, required this.placeholder, required this.controller,
      this.keyboardType, this.obscure = false, this.onToggleObscure, this.inputFormatters,
      this.errorText});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.7)),
      const SizedBox(height: 5),
      TextFormField(controller: controller, keyboardType: keyboardType,
        obscureText: obscure, inputFormatters: inputFormatters,
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14,
            fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: placeholder, errorText: errorText,
          suffixIcon: onToggleObscure != null
              ? GestureDetector(onTap: onToggleObscure,
                  child: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: AppColors.textTertiary, size: 18)) : null)),
    ]);
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String placeholder;
  final TextEditingController controller;
  final VoidCallback onTap;
  final String? errorText;

  const _DateField({required this.label, required this.placeholder,
      required this.controller, required this.onTap, this.errorText});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.7)),
      const SizedBox(height: 5),
      TextFormField(controller: controller, readOnly: true, onTap: onTap,
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14,
            fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: placeholder, errorText: errorText,
          suffixIcon: const Icon(Icons.calendar_today_outlined,
              color: AppColors.textTertiary, size: 17))),
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

  const _DropdownField({required this.label, required this.placeholder, required this.value,
      required this.items, required this.itemLabel, required this.onChanged, this.errorText});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary, letterSpacing: 0.7)),
      const SizedBox(height: 5),
      DropdownButtonFormField<T>(
        value: value,
        hint: Text(placeholder, style: const TextStyle(fontFamily: 'DM Sans',
            fontSize: 14, color: AppColors.textTertiary)),
        items: items.map((e) => DropdownMenuItem(value: e,
            child: Text(itemLabel(e), style: const TextStyle(fontFamily: 'DM Sans',
                fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)))).toList(),
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
        dropdownColor: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
    ]);
  }
}

class _ReviewSection extends StatelessWidget {
  final String title;
  final VoidCallback onEdit;
  final List<Widget> rows;

  const _ReviewSection({required this.title, required this.onEdit, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x1C14142A), width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Row(children: [
            Text(title, style: const TextStyle(fontFamily: 'Syne', fontSize: 13,
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const Spacer(),
            GestureDetector(onTap: onEdit,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: AppColors.primary.withOpacity(0.22))),
                child: const Text('Edit', style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                    fontWeight: FontWeight.w700, color: AppColors.primary)))),
          ])),
        const Divider(height: 1, color: Color(0x1C14142A)),
        ...rows,
      ]),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
      ]));
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
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

class _PolaMoveLogo extends StatelessWidget {
  final double fontSize;
  const _PolaMoveLogo({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final letter in ['P', 'o', 'l', 'a', 'M'])
          Text(letter, style: TextStyle(fontFamily: 'Syne', fontSize: fontSize,
              fontWeight: FontWeight.w800, color: Colors.white, height: 1, letterSpacing: -0.5)),
        SizedBox(width: fontSize * 0.68, height: fontSize * 0.68,
            child: CustomPaint(painter: _WheelPainter())),
        for (final letter in ['v', 'e'])
          Text(letter, style: TextStyle(fontFamily: 'Syne', fontSize: fontSize,
              fontWeight: FontWeight.w800, color: Colors.white, height: 1, letterSpacing: -0.5)),
      ]);
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
      child: GestureDetector(onTap: onTap,
        child: AnimatedContainer(duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
            boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(0.17),
                blurRadius: 10, offset: const Offset(0, 2))] : []),
          child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 13, fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : Colors.white.withOpacity(0.58))))));
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}