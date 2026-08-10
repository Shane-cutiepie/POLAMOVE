import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/validators.dart';
import 'location_service.dart';

/// Thrown for anything the user should see a readable message about.
class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;

  // ── Driver Sign Up ─────────────────────────────────
  /// Creates the Auth account with the driver's real email, writes the
  /// users/{uid} and drivers/{uid} documents, and registers the phone number
  /// in phone_index so the driver can also log in by phone.
  ///
  /// NOTE: Document photos are stored as device-local file paths rather than
  /// Cloud Storage URLs — Cloud Storage requires the Blaze billing plan, which
  /// this project does not use. See _localDocumentPath() for the swap point.
  ///
  /// If any step after account creation fails, the Auth account is deleted so
  /// the email stays usable instead of hitting "email already in use" on a
  /// half-finished signup.
  static Future<void> signUpDriver({
    required String firstName,
    required String lastName,
    required String email,
    required String dateOfBirth,
    required String phone,
    required String barangay,
    required String password,
    required String plateNo,
    required String licenseNo,
    required String licenseExpiry,
    required String preferredRoute,
    required File licensePhoto,
    required File orcrPhoto,
    required File barangayClearancePhoto,
  }) async {
    UserCredential? cred;
    final cleanEmail = Validators.normalizeEmail(email);
    final cleanPhone = Validators.normalizePhone(phone);

    await _assertPhoneAvailable(cleanPhone);

    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      final uid = cred.user!.uid;
      final batch = _db.batch();

      batch.set(_db.collection('users').doc(uid), {
        'role': 'driver',
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'email': cleanEmail,
        'phone': cleanPhone,
        'barangay': barangay,
        'dateOfBirth': dateOfBirth,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.set(_db.collection('drivers').doc(uid), {
        'plateNo': plateNo.trim().toUpperCase(),
        'licenseNo': licenseNo.trim().toUpperCase(),
        'licenseExpiry': licenseExpiry,
        'preferredRoute': preferredRoute,
        'status': 'pending',
        'isOnline': false,
        'documents': {
          'licenseUrl': _localDocumentPath(licensePhoto),
          'orcrUrl': _localDocumentPath(orcrPhoto),
          'barangayClearanceUrl': _localDocumentPath(barangayClearancePhoto),
        },
        'documentsStoredLocally': true,
        'totalRides': 0,
        'rating': 0,
        'totalEarnings': 0,
        'submittedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
      });

      // Lookup table so login-by-phone can resolve to the account email.
      batch.set(_db.collection('phone_index').doc(cleanPhone), {
        'email': cleanEmail,
        'uid': uid,
      });

      await batch.commit();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_authErrorMessage(e));
    } catch (e) {
      if (cred != null) {
        try {
          await cred.user?.delete();
        } catch (_) {}
      }
      throw AuthException(
          'Could not complete your application. Check your connection and try again.');
    }
  }

  // ── Passenger Sign Up ──────────────────────────────
  static Future<void> signUpPassenger({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
  }) async {
    UserCredential? cred;
    final cleanEmail = Validators.normalizeEmail(email);
    final cleanPhone = Validators.normalizePhone(phone);

    await _assertPhoneAvailable(cleanPhone);

    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      final uid = cred.user!.uid;
      final batch = _db.batch();

      batch.set(_db.collection('users').doc(uid), {
        'role': 'passenger',
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'email': cleanEmail,
        'phone': cleanPhone,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.set(_db.collection('phone_index').doc(cleanPhone), {
        'email': cleanEmail,
        'uid': uid,
      });

      await batch.commit();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_authErrorMessage(e));
    } catch (e) {
      if (cred != null) {
        try {
          await cred.user?.delete();
        } catch (_) {}
      }
      throw AuthException(
          'Could not create your account. Check your connection and try again.');
    }
  }

  // ── Log In ─────────────────────────────────────────
  /// Accepts either an email address or a PH mobile number as [identifier].
  /// Phone numbers are resolved to the account email via phone_index.
  static Future<void> logIn({
    required String identifier,
    required String password,
  }) async {
    final email = await _resolveIdentifier(identifier);

    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_authErrorMessage(e));
    }
  }

  static Future<String> _resolveIdentifier(String identifier) async {
    if (Validators.isEmail(identifier)) {
      return Validators.normalizeEmail(identifier);
    }

    final phone = Validators.normalizePhone(identifier);
    try {
      final doc = await _db.collection('phone_index').doc(phone).get();
      final email = doc.data()?['email'] as String?;
      if (email == null) {
        // Deliberately the same message as a wrong password, so the login
        // screen doesn't reveal which phone numbers are registered.
        throw AuthException('Incorrect email/phone number or password.');
      }
      return email;
    } on AuthException {
      rethrow;
    } catch (_) {
      throw AuthException('No internet connection. Please check your network.');
    }
  }

  /// Blocks a second account on the same phone number. Firebase Auth already
  /// enforces uniqueness on email; phone uniqueness is ours to enforce.
  static Future<void> _assertPhoneAvailable(String phone) async {
    try {
      final doc = await _db.collection('phone_index').doc(phone).get();
      if (doc.exists) {
        throw AuthException(
            'This phone number is already registered. Try logging in instead.');
      }
    } on AuthException {
      rethrow;
    } catch (_) {
      throw AuthException('No internet connection. Please check your network.');
    }
  }

  // ── Log Out ────────────────────────────────────────
  static Future<void> logOut() => _auth.signOut();

  /// Clears the driver's online flag and last known position before signing
  /// out, so they don't stay visible to passengers after closing the app.
  static Future<void> logOutDriver() async {
    await LocationService.stopTracking();
    await LocationService.clearLocation();

    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _db.collection('drivers').doc(uid).update({'isOnline': false});
      } catch (_) {}
    }
    await _auth.signOut();
  }

  // ── Password reset ─────────────────────────────────
  /// Only works with an email address — there's no SMS path on this plan.
  static Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(
          email: Validators.normalizeEmail(email));
    } on FirebaseAuthException catch (e) {
      throw AuthException(_authErrorMessage(e));
    }
  }

  // ── User / role lookups ────────────────────────────
  /// Returns 'passenger' | 'driver', or null if the user doc is missing.
  static Future<String?> userRole(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['role'] as String?;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> userStream(String uid) =>
      _db.collection('users').doc(uid).snapshots();

  // ── Driver status ──────────────────────────────────
  /// Returns 'pending' | 'approved' | 'rejected', or null if no driver doc.
  static Future<String?> driverStatus(String uid) async {
    final doc = await _db.collection('drivers').doc(uid).get();
    return doc.data()?['status'] as String?;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> driverStream(
          String uid) =>
      _db.collection('drivers').doc(uid).snapshots();

  // ── Helpers ────────────────────────────────────────
  /// The single swap point for cloud storage. To move to Cloud Storage later:
  /// add firebase_storage, make this async, upload, return the download URL.
  /// Nothing else in the app needs to change.
  static String _localDocumentPath(File file) => file.path;

  static String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in instead.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email/phone number or password.';
      case 'user-disabled':
        return 'This account has been disabled. Contact the administrator.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
