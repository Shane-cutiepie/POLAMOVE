/// Preset reasons a driver can give when cancelling a ride, plus a free-text
/// "Other" option. Keys are stored on rides/{rideId}.cancelReason.
const Map<String, String> kDriverCancelReasons = {
  'no_show':          'Passenger did not show up',
  'wrong_location':   'Passenger is not at the pickup point',
  'extra_passengers': 'More passengers than booked',
  'unsafe':           'Unsafe or threatening behaviour',
  'vehicle_issue':    'Vehicle problem',
  'other':            'Other reason',
};

/// Preset reasons a passenger can give when cancelling a ride.
const Map<String, String> kPassengerCancelReasons = {
  'too_long':     'Driver is taking too long',
  'changed_mind': 'Changed my mind',
  'booked_wrong': 'Booked the wrong location',
  'found_other':  'Found another ride',
  'other':        'Other reason',
};

/// Resolves a stored cancellation reason to its display label. When the
/// reason is 'other', the free text stands in for the preset label — shared
/// by the cancellation notifications and both history screens so the mapping
/// only lives in one place.
String cancelReasonLabel({
  required String? cancelledByRole,
  required String? reason,
  required String? reasonText,
}) {
  if (reason == null) return '—';
  if (reason == 'other') {
    return (reasonText != null && reasonText.isNotEmpty) ? reasonText : 'Other reason';
  }
  final map = cancelledByRole == 'driver' ? kDriverCancelReasons : kPassengerCancelReasons;
  return map[reason] ?? reason;
}
