import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/validators.dart';
import '../auth/auth_driver_screen.dart' show UpperCaseTextFormatter;
import '../shared/form_fields.dart';
import '../shared/red_header.dart';

/// Lets an approved or pending driver correct their tricycle details.
///
/// Changing a plate or licence number invalidates the documents an
/// administrator already verified, so an approved account drops back to
/// pending review. Route and expiry changes do not â€” neither contradicts the
/// documents on file.
///
/// Documents are deliberately not re-uploaded here: verification happens
/// physically through the TODA office, so an in-app photo would not
/// constitute verification. The flag tells the administrator to re-check.
class EditVehicleInfoScreen extends StatefulWidget {
  const EditVehicleInfoScreen({super.key});

  @override
  State<EditVehicleInfoScreen> createState() => _EditVehicleInfoScreenState();
}

class _EditVehicleInfoScreenState extends State<EditVehicleInfoScreen> {
  final _plateCtrl = TextEditingController();
  final _licCtrl = TextEditingController();
  final _licExpCtrl = TextEditingController();
  final Map<String, String?> _errors = {};

  bool _loading = true;
  bool _saving = false;

  // Stored values, normalised, so a re-typed plate isn't mistaken for a change.
  String _originalPlate = '';
  String _originalLicense = '';
  String _driverStatus = 'pending';

  /// Plate and licence are stored uppercased and trimmed by signUpDriver, so
  /// comparisons use the same normalisation: a case-only or whitespace-only
  /// edit is not a change and must not cost the driver their approval.
  static String _norm(String value) => value.trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _licCtrl.dispose();
    _licExpCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .get();
      final data = doc.data() ?? {};
      if (!mounted) return;

      setState(() {
        _plateCtrl.text = data['plateNo'] ?? '';
        _licCtrl.text = data['licenseNo'] ?? '';
        _licExpCtrl.text = data['licenseExpiry'] ?? '';
        _originalPlate = _norm(_plateCtrl.text);
        _originalLicense = _norm(_licCtrl.text);
        _driverStatus = data['status'] ?? 'pending';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Could not load your vehicle details. Please try again.');
    }
  }

  bool _validate() {
    setState(() {
      _errors['plateNo'] = Validators.plateNumber(_plateCtrl.text);
      _errors['licenseNo'] = Validators.licenseNumber(_licCtrl.text);
      _errors['licenseExpiry'] =
          Validators.date(_licExpCtrl.text, 'License expiry date');
    });
    return ['plateNo', 'licenseNo', 'licenseExpiry']
        .every((key) => _errors[key] == null);
  }

  Future<void> _save() async {
    if (!_validate()) return;

    final newPlate = _norm(_plateCtrl.text);
    final newLicense = _norm(_licCtrl.text);
    final plateChanged = newPlate != _originalPlate;
    final licenseChanged = newLicense != _originalLicense;
    final revokesApproval =
        _driverStatus == 'approved' && (plateChanged || licenseChanged);

    if (revokesApproval) {
      final confirmed = await _confirmReapproval();
      if (!confirmed || !mounted) return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);

    final update = <String, dynamic>{
      'plateNo': newPlate,
      'licenseNo': newLicense,
      'licenseExpiry': _licExpCtrl.text,
    };

    if (revokesApproval) {
      update.addAll({
        'status': 'pending',
        'reviewedAt': null,
        'reviewedBy': null,
        'documentsOutdated': true,
        'documentChangeNote': _changeNote(
          plateChanged: plateChanged,
          licenseChanged: licenseChanged,
          newPlate: newPlate,
          newLicense: newLicense,
        ),
      });
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .update(update);
      if (revokesApproval) await _notifyReapproval(uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Could not save your vehicle details. Please try again.');
      return;
    }

    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
        revokesApproval
            ? 'Vehicle details saved. Your application is pending review.'
            : 'Vehicle details saved.',
        style: const TextStyle(fontFamily: 'DM Sans'),
      ),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    navigator.pop();
  }

  String _changeNote({
    required bool plateChanged,
    required bool licenseChanged,
    required String newPlate,
    required String newLicense,
  }) {
    final String what;
    if (plateChanged && licenseChanged) {
      what = 'Plate changed from $_originalPlate to $newPlate and licence '
          'number from $_originalLicense to $newLicense.';
    } else if (plateChanged) {
      what = 'Plate changed from $_originalPlate to $newPlate.';
    } else {
      what = 'Licence number changed from $_originalLicense to $newLicense.';
    }
    return '$what Documents on file may not match.';
  }

  /// Best-effort: a failed notification must not undo a save that succeeded.
  Future<void> _notifyReapproval(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': uid,
        'title': 'Re-approval required',
        'message': 'Your vehicle details changed, so your account is pending '
            'administrative review again. You will not be able to accept '
            'bookings until an administrator approves it.',
        'category': 'account',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<bool> _confirmReapproval() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Re-approval required',
          style: TextStyle(
            fontFamily: 'Syne',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          'Changing your plate or licence number means your application must '
          'be reviewed again. You won\'t be able to accept bookings until an '
          'administrator approves it.',
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
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
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Save Anyway',
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
    return confirmed ?? false;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'DM Sans')),
      backgroundColor: AppColors.primaryDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  /// A stored expiry can already be in the past â€” which is often exactly why
  /// the driver is here â€” and showDatePicker asserts if initialDate falls
  /// before firstDate.
  DateTime _initialExpiryDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final parts = _licExpCtrl.text.split('/');
    if (parts.length == 3) {
      final month = int.tryParse(parts[0]);
      final day = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (month != null && day != null && year != null) {
        final parsed = DateTime(year, month, day);
        if (!parsed.isBefore(today)) return parsed;
      }
    }
    return today;
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _initialExpiryDate(),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(2040),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _licExpCtrl.text =
        '${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        const RedHeader(
          title: 'Vehicle Information',
          subtitle: 'Update your tricycle details',
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    AppFormField(
                        label: 'Tricycle Plate No.',
                        controller: _plateCtrl,
                        placeholder: 'e.g. POLO-1234',
                        inputFormatters: [UpperCaseTextFormatter()],
                        errorText: _errors['plateNo']),
                    const SizedBox(height: 12),
                    AppFormField(
                        label: "Driver's License No.",
                        controller: _licCtrl,
                        placeholder: 'e.g. N01-23-456789',
                        inputFormatters: [UpperCaseTextFormatter()],
                        errorText: _errors['licenseNo']),
                    const SizedBox(height: 12),
                    AppDateField(
                        label: 'License Expiry Date',
                        controller: _licExpCtrl,
                        placeholder: 'MM/DD/YYYY',
                        errorText: _errors['licenseExpiry'],
                        onTap: _pickExpiry),
                    const SizedBox(height: 14),
                    const _DocumentsNote(),
                    const SizedBox(height: 22),
                    _SaveButton(saving: _saving, onTap: _saving ? null : _save),
                  ]),
                ),
        ),
      ]),
    );
  }
}

/// Sets expectations before the driver edits: papers are checked in person,
/// so there is nothing to upload here.
class _DocumentsNote extends StatelessWidget {
  const _DocumentsNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border)),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ðŸ“‹', style: TextStyle(fontSize: 13)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Changing your plate or licence number sends your account back '
            'for review. Documents are verified at the TODA office, not in '
            'the app.',
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, height: 1.45,
                color: AppColors.textSecondary),
          ),
        ),
      ]),
    );
  }
}

/// Matches _PrimaryButton in auth_driver_screen.dart, with a busy state. The
/// spinner is white rather than AppColors.primary because it sits on the
/// filled red button, where the brand colour would be invisible.
class _SaveButton extends StatelessWidget {
  final bool saving;
  final VoidCallback? onTap;

  const _SaveButton({required this.saving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0),
        child: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Text('Save Changes',
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3)),
      ),
    );
  }
}
