import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../core/utils/validators.dart';

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
  static final _storage = FirebaseStorage.instance;

  static User? get currentUser => _auth.currentUser;

  // ── Driver Sign Up ─────────────────────────────────
  /// Creates the Auth account, uploads the three documents, then writes the
  /// users/{uid} and drivers/{uid} documents.
  ///
  /// If any step after account creation fails, the Auth account is deleted so
  /// the driver can retry with the same phone number instead of hitting
  /// "email already in use" on a half-finished signup.
  static Future<void> signUpDriver({
    required String firstName,
    required String lastName,
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

    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: Validators.phoneToEmail(phone),
        password: password,
      );

      final uid = cred.user!.uid;

      final licenseUrl =
          await _uploadDocument(uid, 'license.jpg', licensePhoto);
      final orcrUrl = await _uploadDocument(uid, 'orcr.jpg', orcrPhoto);
      final clearanceUrl = await _uploadDocument(
          uid, 'barangay_clearance.jpg', barangayClearancePhoto);

      final batch = _db.batch();

      batch.set(_db.collection('users').doc(uid), {
        'role': 'driver',
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'phone': Validators.normalizePhone(phone),
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
          'licenseUrl': licenseUrl,
          'orcrUrl': orcrUrl,
          'barangayClearanceUrl': clearanceUrl,
        },
        'totalRides': 0,
        'rating': 0,
        'totalEarnings': 0,
        'submittedAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
      });

      await batch.commit();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_authErrorMessage(e));
    } catch (e) {
      // Roll back the orphaned Auth account so the phone number stays usable.
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
  /// Creates the Auth account and writes the users/{uid} document.
  ///
  /// If the Firestore write fails, the Auth account is deleted so the
  /// passenger can retry with the same phone number.
  static Future<void> signUpPassenger({
    required String firstName,
    required String lastName,
    required String phone,
    required String password,
  }) async {
    UserCredential? cred;

    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: Validators.phoneToEmail(phone),
        password: password,
      );

      final uid = cred.user!.uid;

      await _db.collection('users').doc(uid).set({
        'role': 'passenger',
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'phone': Validators.normalizePhone(phone),
        'createdAt': FieldValue.serverTimestamp(),
      });
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
  static Future<void> logIn({
    required String phone,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: Validators.phoneToEmail(phone),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_authErrorMessage(e));
    }
  }

  static Future<void> logOut() => _auth.signOut();

  /// Flips the driver offline before signing out, so they don't stay listed
  /// as available to passengers after leaving the app.
  static Future<void> logOutDriver() async {
    final uid = currentUser?.uid;
    if (uid != null) {
      try {
        await _db.collection('drivers').doc(uid).update({'isOnline': false});
      } catch (_) {}
    }
    await _auth.signOut();
  }

  // ── User role ──────────────────────────────────────
  /// Returns 'driver' | 'passenger', or null if no users/{uid} doc exists.
  static Future<String?> userRole(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['role'] as String?;
  }

  // ── Driver status ──────────────────────────────────
  /// Returns 'pending' | 'approved' | 'rejected', or null if no driver doc.
  static Future<String?> driverStatus(String uid) async {
    final doc = await _db.collection('drivers').doc(uid).get();
    return doc.data()?['status'] as String?;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> driverStream(
          String uid) =>
      _db.collection('drivers').doc(uid).snapshots();

  static Stream<DocumentSnapshot<Map<String, dynamic>>> userStream(
          String uid) =>
      _db.collection('users').doc(uid).snapshots();

  // ── Helpers ────────────────────────────────────────
  static Future<String> _uploadDocument(
      String uid, String fileName, File file) async {
    final ref = _storage.ref('driver_documents/$uid/$fileName');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  static String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This phone number is already registered. Try logging in instead.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect phone number or password.';
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