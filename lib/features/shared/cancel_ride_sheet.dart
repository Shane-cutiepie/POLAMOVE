import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/cancel_reasons.dart';
import '../../core/services/ride_service.dart';

/// One sheet used by both sides of a ride to confirm a cancellation with a
/// reason. Returns once the sheet is dismissed; if the cancellation went
/// through and this was the passenger/driver's 3rd cancellation in the past
/// hour, a follow-up warning dialog is shown on the caller's context (the
/// sheet's own context is gone by then).
Future<bool> showCancelRideSheet(
  BuildContext context, {
  required String rideId,
  required String role, // 'passenger' | 'driver'
  required String? status,
}) async {
  final cancelled = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CancelRideSheet(rideId: rideId, role: role, status: status),
  );

  if (cancelled == true && context.mounted) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final count = await RideService.recentCancellationCount(uid);
      if (count == 3 && context.mounted) {
        _showThirdCancellationWarning(context);
      }
    }
  }

  return cancelled ?? false;
}

void _showThirdCancellationWarning(BuildContext context) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Heads up',
          style: TextStyle(fontFamily: 'Syne', fontSize: 16,
              fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      content: const Text(
        'You\'ve cancelled 3 rides in the past hour. Cancelling 5 times will pause your bookings for 1 hour.',
        style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
            color: AppColors.textSecondary, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Got it',
              style: TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
        ),
      ],
    ),
  );
}

class _CancelRideSheet extends StatefulWidget {
  final String rideId;
  final String role;
  final String? status;

  const _CancelRideSheet({required this.rideId, required this.role, required this.status});

  @override
  State<_CancelRideSheet> createState() => _CancelRideSheetState();
}

class _CancelRideSheetState extends State<_CancelRideSheet> {
  String? _reason;
  final _textController = TextEditingController();
  bool _submitting = false;

  Map<String, String> get _reasons =>
      widget.role == 'driver' ? kDriverCancelReasons : kPassengerCancelReasons;

  bool get _feeApplies =>
      widget.role == 'passenger' &&
      (widget.status == 'arrived' || widget.status == 'ongoing');

  bool get _canConfirm =>
      !_submitting &&
      _reason != null &&
      (_reason != 'other' || _textController.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _textController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final reason = _reason;
    if (reason == null || !_canConfirm) return;
    final reasonText = reason == 'other' ? _textController.text.trim() : null;

    setState(() => _submitting = true);
    final navigator = Navigator.of(context);

    try {
      await RideService.cancelRide(widget.rideId, reason: reason, reasonText: reasonText);
      navigator.pop(true);
    } on RideException catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message, style: const TextStyle(fontFamily: 'DM Sans')),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.surfaceStrong,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),
            const Text('Cancel this ride?',
                style: TextStyle(fontFamily: 'Syne', fontSize: 18,
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            if (_feeApplies) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.22))),
                child: const Text(
                    '⚠️ Your driver has already arrived. A ₱20 late cancellation fee applies, payable in cash to your driver.',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                        color: AppColors.textPrimary, height: 1.4)),
              ),
              const SizedBox(height: 14),
            ],
            ..._reasons.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ReasonRow(
                    label: entry.value,
                    selected: _reason == entry.key,
                    onTap: () => setState(() => _reason = entry.key),
                  ),
                )),
            if (_reason == 'other') ...[
              const SizedBox(height: 4),
              TextField(
                controller: _textController,
                maxLength: 200,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                    color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Tell us more…',
                  hintStyle: const TextStyle(fontFamily: 'DM Sans', color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surfaceAlt,
                  counterStyle: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: _submitting ? null : () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: Color(0x1C14142A), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text('Keep Ride',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 13, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: _canConfirm ? _confirm : null,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.surfaceStrong,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0),
                child: _submitting
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Cancel Ride',
                        style: TextStyle(fontFamily: 'Syne', fontSize: 14, fontWeight: FontWeight.w700)),
              )),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ReasonRow({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 1.5),
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18, color: selected ? AppColors.primary : AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 13, fontWeight: FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.textPrimary))),
        ]),
      ),
    );
  }
}
