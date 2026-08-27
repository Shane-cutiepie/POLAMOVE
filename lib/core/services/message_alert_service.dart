import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'chat_service.dart';
import 'sound_service.dart';

/// Plays [SoundService.message] for a new chat message anywhere in the app,
/// not just while [ChatScreen] happens to be open on that ride.
///
/// Finds "the active ride" rather than watching every ride the user has ever
/// been part of: at most one ride can be accepted/arrived/ongoing for a given
/// user at a time (the booking and driver-acceptance flows both enforce
/// this), and among a user's own rides that one is always the most recently
/// requested — a driver can't accept a second ride before finishing the
/// first, and a passenger can't book a second before the first ends. So "most
/// recent by requestedAt, if its status is still active" reliably identifies
/// it, using the exact same (passengerId, requestedAt) / (driverId,
/// requestedAt) query shape RideService.passengerHistory() and
/// driverHistory() already rely on — reusing an index Firestore already has
/// to serve those screens, rather than needing a new composite index for an
/// OR-across-fields query.
class MessageAlertService {
  MessageAlertService._();

  static const _activeStatuses = {'accepted', 'arrived', 'ongoing'};

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _passengerRideSub;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _driverRideSub;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _messagesSub;

  // A uid is a passenger account or a driver account, never both, so in
  // practice only one of these is ever non-null — but both are tracked so
  // one listener's "nothing active" result never clobbers what the other
  // just found.
  static String? _passengerActiveRideId;
  static String? _driverActiveRideId;
  static String? _subscribedRideId;

  static bool _firstMessageSnapshot = true;
  static Set<String> _seenMessageIds = {};

  /// Set by ChatScreen while it's open for [_suppressedRideId], so this
  /// background listener doesn't play a second sound for a message the open
  /// chat screen already chimed for. Keyed by ride id rather than a plain
  /// bool: a chat screen open on a *different* (e.g. historical) ride must
  /// not silence a genuinely new message on the ride this service is
  /// actually tracking as active.
  static String? _suppressedRideId;

  static void suppress(String rideId) => _suppressedRideId = rideId;

  static void unsuppress(String rideId) {
    if (_suppressedRideId == rideId) _suppressedRideId = null;
  }

  /// Idempotent — safe to call again without a prior stop().
  static void start() {
    stop();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final rides = FirebaseFirestore.instance.collection('rides');

    _passengerRideSub = rides
        .where('passengerId', isEqualTo: uid)
        .orderBy('requestedAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      _passengerActiveRideId = _extractActiveRideId(snap);
      _syncMessagesSubscription();
    }, onError: (_) {});

    _driverRideSub = rides
        .where('driverId', isEqualTo: uid)
        .orderBy('requestedAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      _driverActiveRideId = _extractActiveRideId(snap);
      _syncMessagesSubscription();
    }, onError: (_) {});
  }

  static String? _extractActiveRideId(
      QuerySnapshot<Map<String, dynamic>> snap) {
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    final status = doc.data()['status'] as String?;
    return _activeStatuses.contains(status) ? doc.id : null;
  }

  /// Swaps or cancels the messages subscription when the active ride changes
  /// or ends. A completed ride must not keep being listened to.
  static void _syncMessagesSubscription() {
    final activeId = _passengerActiveRideId ?? _driverActiveRideId;
    if (activeId == _subscribedRideId) return;

    _messagesSub?.cancel();
    _messagesSub = null;
    _subscribedRideId = activeId;

    // Fresh ride, fresh initial-snapshot guard — attaching to a new ride's
    // thread must not chime for messages already sitting in it.
    _firstMessageSnapshot = true;
    _seenMessageIds = {};

    if (activeId == null) return;

    _messagesSub =
        ChatService.messages(activeId).listen(_onMessagesSnapshot, onError: (_) {});
  }

  /// Same initial-snapshot and seen-id-diffing guards as chat_screen's
  /// _handleNewMessages: skip the listener's first delivery outright, then
  /// diff doc ids (not content) on every later delivery so a readBy update
  /// from someone marking the thread read is never mistaken for a new
  /// message.
  static void _onMessagesSnapshot(
      QuerySnapshot<Map<String, dynamic>> snap) {
    final docs = snap.docs;
    final currentIds = docs.map((d) => d.id).toSet();
    final isFirst = _firstMessageSnapshot;
    _firstMessageSnapshot = false;

    if (isFirst) {
      _seenMessageIds = currentIds;
      return;
    }

    final newIds = currentIds.difference(_seenMessageIds);
    _seenMessageIds = currentIds;
    if (newIds.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final hasIncoming = docs.any(
        (d) => newIds.contains(d.id) && d.data()['senderId'] != uid);
    if (!hasIncoming) return;

    // The open chat screen for this exact ride already played its own
    // sound for this message.
    if (_suppressedRideId != null && _suppressedRideId == _subscribedRideId) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        SoundService.message();
      }
    });
  }

  /// Cancels everything and resets tracked state. Call on logout — a signed
  /// out user's session must not keep listening for someone else's messages
  /// after the next sign-in.
  static void stop() {
    _passengerRideSub?.cancel();
    _driverRideSub?.cancel();
    _messagesSub?.cancel();
    _passengerRideSub = null;
    _driverRideSub = null;
    _messagesSub = null;
    _passengerActiveRideId = null;
    _driverActiveRideId = null;
    _subscribedRideId = null;
    _firstMessageSnapshot = true;
    _seenMessageIds = {};
    _suppressedRideId = null;
  }
}
