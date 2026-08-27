import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/message_alert_service.dart';
import '../../core/services/ride_service.dart';
import '../../core/services/sound_service.dart';
import 'red_header.dart';
import 'user_avatar.dart';

/// One conversation per ride, at rides/{rideId}/messages. Read-only once the
/// ride reaches completed or cancelled — [ChatService.isChatOpen] follows the
/// ride's live status, so this screen never needs a separate read-only flag.
class ChatScreen extends StatefulWidget {
  final String rideId;
  final String otherUid;
  final String otherName;
  final String otherRole; // 'driver' or 'passenger'

  const ChatScreen({
    super.key,
    required this.rideId,
    required this.otherUid,
    required this.otherName,
    required this.otherRole,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  bool _sending = false;
  int _otherAvatarIndex = 0;
  String? _otherAvatarUrl;
  String? _otherPlate;

  // Sound-on-new-message bookkeeping. `_firstSnapshot` skips the listener's
  // initial delivery (opening a 20-message thread must not play 20 sounds);
  // `_seenMessageIds` then finds genuinely new docs on every later delivery,
  // which also makes this immune to snapshots that only exist because
  // markRead touched an existing message's `readBy` field — that doc's id
  // was already seen, so it's never mistaken for a new message.
  bool _firstSnapshot = true;
  Set<String> _seenMessageIds = {};

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    MessageAlertService.suppress(widget.rideId);
    ChatService.markRead(widget.rideId, _uid);
    _loadOtherParty();
  }

  @override
  void dispose() {
    MessageAlertService.unsuppress(widget.rideId);
    _controller.dispose();
    super.dispose();
  }

  /// Avatar always comes from users/{uid}; the plate only matters when the
  /// other party is a driver, so it's fetched from drivers/{uid} for that
  /// case only — mirroring how ride_status_screen loads driver details.
  Future<void> _loadOtherParty() async {
    final user = await RideService.userInfo(widget.otherUid);
    String? plate;
    if (widget.otherRole == 'driver') {
      final driver = await RideService.driverInfo(widget.otherUid);
      plate = driver?['plateNo'] as String?;
    }
    if (!mounted) return;
    setState(() {
      _otherAvatarIndex = (user?['avatarIndex'] ?? 0) as int;
      _otherAvatarUrl = user?['avatarUrl'] as String?;
      _otherPlate = plate;
    });
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ChatService.send(widget.rideId, text);
      _controller.clear();
    } on ChatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e.message, style: const TextStyle(fontFamily: 'DM Sans')),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Plays [SoundService.message] for a newly-arrived message from the
  /// other party. Never for the current user's own outgoing message — that
  /// message's senderId is _uid, so it's filtered out below.
  void _handleNewMessages(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final currentIds = docs.map((d) => d.id).toSet();
    final isFirst = _firstSnapshot;
    _firstSnapshot = false;

    if (isFirst) {
      _seenMessageIds = currentIds;
      return;
    }

    final newIds = currentIds.difference(_seenMessageIds);
    _seenMessageIds = currentIds;
    if (newIds.isEmpty) return;

    final hasIncoming = docs.any(
        (d) => newIds.contains(d.id) && d.data()['senderId'] != _uid);
    if (!hasIncoming) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        SoundService.message();
      }
    });
  }

  String get _subtitle {
    final roleLabel = widget.otherRole == 'driver' ? 'Driver' : 'Passenger';
    final plate = _otherPlate;
    if (widget.otherRole == 'driver' && plate != null && plate.isNotEmpty) {
      return '$roleLabel · $plate';
    }
    return roleLabel;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        RedHeader(title: widget.otherName, subtitle: _subtitle),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ChatService.messages(widget.rideId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary));
              }

              final docs = snapshot.data!.docs;
              _handleNewMessages(docs);
              if (docs.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) ChatService.markRead(widget.rideId, _uid);
                });
              }

              if (docs.isEmpty) {
                return _EmptyChatState(otherRole: widget.otherRole);
              }

              return _buildMessageList(docs);
            },
          ),
        ),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: RideService.watchRide(widget.rideId),
          builder: (context, snapshot) {
            final status = snapshot.data?.data()?['status'] as String?;
            if (!ChatService.isChatOpen(status)) {
              return const _ClosedPill();
            }
            return _Composer(
              controller: _controller,
              sending: _sending,
              onSend: _send,
            );
          },
        ),
      ]),
    );
  }

  Widget _buildMessageList(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // Built in chronological order, then reversed so `reverse: true` on the
    // ListView both puts newest at the bottom and starts scrolled there.
    final items = <Widget>[];
    DateTime? prevDate;
    String? prevSenderId;

    for (final doc in docs) {
      final data = doc.data();
      final senderId = data['senderId'] as String? ?? '';
      final isOwn = senderId == _uid;
      final sentAt = data['sentAt'];
      final time = sentAt is Timestamp ? sentAt.toDate() : DateTime.now();

      final isNewDay = prevDate == null || !_isSameDay(prevDate, time);
      if (isNewDay) items.add(_DateSeparator(date: time));

      final isRunStart = prevSenderId != senderId;
      items.add(_MessageBubble(
        isOwn: isOwn,
        showAvatar: !isOwn && isRunStart,
        avatarUrl: _otherAvatarUrl,
        avatarIndex: _otherAvatarIndex,
        text: data['text'] as String? ?? '',
        time: time,
      ));

      prevDate = time;
      prevSenderId = senderId;
    }

    return ListView(
      reverse: true,
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 12 + MediaQuery.of(context).padding.bottom),
      children: items.reversed.toList(),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

String _formatTime(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:${d.minute.toString().padLeft(2, '0')} $period';
}

String _formatDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(50)),
          child: Text(_formatDate(date),
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isOwn;
  final bool showAvatar;
  final String? avatarUrl;
  final int avatarIndex;
  final String text;
  final DateTime time;

  const _MessageBubble({
    required this.isOwn,
    required this.showAvatar,
    required this.avatarUrl,
    required this.avatarIndex,
    required this.text,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.75;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isOwn ? AppColors.primary : AppColors.surfaceAlt,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isOwn ? 16 : 4),
          bottomRight: Radius.circular(isOwn ? 4 : 16),
        ),
      ),
      child: Text(text, style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
          color: isOwn ? Colors.white : AppColors.textPrimary)),
    );

    final column = Column(
      crossAxisAlignment: isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        const SizedBox(height: 3),
        Text(_formatTime(time),
            style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
      ],
    );

    if (isOwn) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(alignment: Alignment.centerRight, child: column),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 26,
          height: 26,
          child: showAvatar
              ? Container(
                  decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: AppColors.primary.withOpacity(0.3))),
                  child: UserAvatar(avatarUrl: avatarUrl,
                      avatarIndex: avatarIndex, size: 26, emojiSize: 13))
              : null,
        ),
        const SizedBox(width: 8),
        Flexible(child: column),
      ]),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  final String otherRole;
  const _EmptyChatState({required this.otherRole});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('💬', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 10),
        Text(
          otherRole == 'driver' ? 'Say hello to your driver' : 'Say hello to your passenger',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      ]),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final canSend = !sending && value.text.trim().isNotEmpty;
          return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                      color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Type a message…',
                    hintStyle: TextStyle(fontFamily: 'DM Sans', color: AppColors.textTertiary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: canSend ? onSend : null,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: canSend ? AppColors.primary : AppColors.surfaceStrong,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.send_rounded,
                    color: canSend ? Colors.white : AppColors.textTertiary, size: 18),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _ClosedPill extends StatelessWidget {
  const _ClosedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(
          15, 12, 15, 12 + MediaQuery.of(context).padding.bottom),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(50)),
          child: const Text('This chat is closed. The trip has ended.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ),
    );
  }
}
