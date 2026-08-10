/// Form validation for PolaMove.
///
/// Every function returns `null` when the value is valid, or an error message
/// string when it isn't.
class Validators {
  Validators._();

  static String? required(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? name(String? value, String fieldName) {
    final base = required(value, fieldName);
    if (base != null) return base;
    if (value!.trim().length < 2) {
      return '$fieldName is too short';
    }
    if (!RegExp(r"^[a-zA-ZñÑ\s\-'\.]+$").hasMatch(value.trim())) {
      return '$fieldName has invalid characters';
    }
    return null;
  }

  // ── Email ──────────────────────────────────────────
  static String? email(String? value) {
    final base = required(value, 'Email');
    if (base != null) return base;
    if (!isEmail(value!)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// True when the string looks like an email rather than a phone number.
  /// Used at login to decide how to resolve the identifier.
  static bool isEmail(String value) {
    return RegExp(r'^[\w\.\-\+]+@[\w\-]+(\.[\w\-]+)+$').hasMatch(value.trim());
  }

  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  // ── Phone ──────────────────────────────────────────
  /// Accepts Philippine mobile formats: 09XXXXXXXXX, +639XXXXXXXXX,
  /// 639XXXXXXXXX — with or without spaces and dashes.
  static String? phone(String? value) {
    final base = required(value, 'Phone number');
    if (base != null) return base;

    final digits = normalizePhone(value!);
    if (digits.length != 11 || !digits.startsWith('09')) {
      return 'Enter a valid PH mobile number (09XXXXXXXXX)';
    }
    return null;
  }

  /// Strips formatting and converts any accepted format to 09XXXXXXXXX.
  static String normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('63') && digits.length == 12) {
      digits = '0${digits.substring(2)}';
    }
    return digits;
  }

  /// Login accepts either an email address or a phone number.
  static String? loginIdentifier(String? value) {
    final base = required(value, 'Email or phone number');
    if (base != null) return base;
    if (isEmail(value!)) return null;
    final digits = normalizePhone(value);
    if (digits.length != 11 || !digits.startsWith('09')) {
      return 'Enter a valid email or PH mobile number';
    }
    return null;
  }

  // ── Password ───────────────────────────────────────
  static String? password(String? value) {
    final base = required(value, 'Password');
    if (base != null) return base;
    if (value!.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  // ── Misc fields ────────────────────────────────────
  static String? dropdown(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return 'Please select a $fieldName';
    }
    return null;
  }

  static String? date(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Philippine plate numbers vary (ABC 1234, ABC 123, TODA body numbers).
  /// Kept permissive on purpose — rejecting a valid local plate is worse than
  /// accepting an odd one.
  static String? plateNumber(String? value) {
    final base = required(value, 'Plate number');
    if (base != null) return base;
    final cleaned = value!.replaceAll(RegExp(r'[\s\-]'), '');
    if (cleaned.length < 4 || cleaned.length > 10) {
      return 'Enter a valid plate number';
    }
    return null;
  }

  /// LTO format: N01-23-456789
  static String? licenseNumber(String? value) {
    final base = required(value, 'License number');
    if (base != null) return base;
    final cleaned = value!.replaceAll(RegExp(r'[\s]'), '');
    if (cleaned.length < 10) {
      return 'Enter a valid license number';
    }
    return null;
  }
}
