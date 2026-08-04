/// Form validation for PolaMove.
///
/// Every function returns `null` when the value is valid, or an error message
/// string when it isn't. This matches Flutter's TextFormField validator
/// signature, so these can be dropped into a Form later if needed.
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

  static String? password(String? value) {
    final base = required(value, 'Password');
    if (base != null) return base;
    if (value!.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

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

  /// Philippine plate numbers vary (ABC 1234, ABC 123, 1234 AB, TODA body
  /// numbers). Kept permissive on purpose — rejecting a valid local plate is
  /// worse than accepting an odd one.
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

  /// Converts a phone number into the synthetic email used for Firebase Auth.
  /// The user never sees this — they log in with their phone number.
  static String phoneToEmail(String phone) {
    return '${normalizePhone(phone)}@polamove.app';
  }
}