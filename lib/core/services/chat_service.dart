import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ride_service.dart';

/// Thrown for anything the user should see a readable message about.
class ChatException implements Exception {
  final String message;
  ChatException(this.message);
  @override
  String toString() => message;
}

/// Chat data layer. One thread per ride, stored at
/// `rides/{rideId}/messages/{messageId}` — never a top-level collection, so
/// privacy falls out of the ride's own participants.
class ChatService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _messagesRef(
          String rideId) =>
      _db.collection('rides').doc(rideId).collection('messages');

  static ChatException _mapError(Object e, String action) =>
      ChatException(RideService.mapErrorMessage(e, action));

  // ── Watch ──────────────────────────────────────────
  static Stream<QuerySnapshot<Map<String, dynamic>>> messages(
          String rideId) =>
      _messagesRef(rideId).orderBy('sentAt').limit(200).snapshots();

  /// Derived from [messages] rather than a second query, so a screen showing
  /// both the thread and an unread badge only ever opens one listener shape.
  static Stream<int> unreadCount(String rideId, String uid) {
    return messages(rideId).map((snapshot) => snapshot.docs.where((doc) {
          final readBy = List<String>.from(doc.data()['readBy'] ?? const []);
          return !readBy.contains(uid);
        }).length);
  }

  // ── Send ───────────────────────────────────────────
  static Future<void> send(String rideId, String text) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw ChatException('You need to be logged in to send a message.');
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ChatException('Message can\'t be empty.');
    }
    final capped = trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;

    try {
      await _messagesRef(rideId).add({
        'senderId': uid,
        'text': capped,
        'sentAt': FieldValue.serverTimestamp(),
        'readBy': [uid],
      });
    } catch (e) {
      throw _mapError(e, 'send this message');
    }

    await _notifyNewMessage(rideId: rideId, senderId: uid);
  }

  /// Best-effort in-app notification for the other party. Only fires for the
  /// first unread message in a run — once the recipient already has unread
  /// messages in this ride, further sends add nothing, so a rapid exchange
  /// doesn't flood the notifications tab.
  ///
  /// Deliberately says nothing about the message content — a preview here
  /// could surface on a lock screen or over someone's shoulder.
  static Future<void> _notifyNewMessage({
    required String rideId,
    required String senderId,
  }) async {
    try {
      final ride = (await _db.collection('rides').doc(rideId).get()).data();
      if (ride == null) return;

      final passengerId = ride['passengerId'] as String?;
      final driverId = ride['driverId'] as String?;
      final recipient = senderId == passengerId ? driverId : passengerId;
      if (recipient == null) return;

      final recent = await _messagesRef(rideId)
          .orderBy('sentAt', descending: true)
          .limit(200)
          .get();
      final unreadForRecipient = recent.docs.where((doc) {
        final readBy = List<String>.from(doc.data()['readBy'] ?? const []);
        return !readBy.contains(recipient);
      }).length;
      // The message just sent is already in this count, so >1 means the
      // recipient had unread messages before it.
      if (unreadForRecipient > 1) return;

      // Same comparison RideService.cancelRide uses to resolve a
      // participant's role from the ride document.
      final senderRole = senderId == passengerId ? 'Passenger' : 'Driver';
      final sender = await RideService.userInfo(senderId);
      final name =
          '${sender?['firstName'] ?? ''} ${sender?['lastName'] ?? ''}'
              .trim();
      final message = name.isEmpty
          ? '$senderRole sent you a message.'
          : '$senderRole $name sent you a message.';

      await _db.collection('notifications').add({
        'userId': recipient,
        'title': 'New message',
        'message': message,
        'category': 'ride',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // A failed notification must never fail the message send.
    }
  }

  // ── Read state ─────────────────────────────────────
  /// Firestore can't query "array does not contain", so this reads the
  /// recent window and filters client-side before batching the update.
  static Future<void> markRead(String rideId, String uid) async {
    try {
      final snap = await _messagesRef(rideId)
          .orderBy('sentAt', descending: true)
          .limit(200)
          .get();

      final batch = _db.batch();
      var hasUpdates = false;
      for (final doc in snap.docs) {
        final readBy = List<String>.from(doc.data()['readBy'] ?? const []);
        if (!readBy.contains(uid)) {
          batch.update(doc.reference, {
            'readBy': FieldValue.arrayUnion([uid]),
          });
          hasUpdates = true;
        }
      }
      if (hasUpdates) await batch.commit();
    } catch (_) {
      // Best-effort — unread state just stays as-is until the next try.
    }
  }

  /// Chat closes when the trip ends. The thread stays readable; only sending
  /// is disabled.
  static bool isChatOpen(String? status) =>
      status == 'accepted' || status == 'arrived' || status == 'ongoing';
}
