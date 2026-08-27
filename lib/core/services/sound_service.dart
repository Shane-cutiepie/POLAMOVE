import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Short audio cues for events the user isn't looking at.
///
/// Deliberately fire-and-forget: a sound failing to play must never interrupt
/// booking, accepting, or messaging. Every call is wrapped and swallowed.
class SoundService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _enabled = true;

  /// AudioContextConfig(respectSilence: true) is the only combination this
  /// package's simplified builder allows that reaches a non-media Android
  /// usage type — it resolves to AndroidUsageType.notificationRingtone (the
  /// closest of the three reachable values to an alert chime) with
  /// AndroidAudioFocus.gain, and AVAudioSessionCategory.ambient on iOS
  /// (silenced by the ring/silent switch and screen lock, same as a system
  /// notification sound). `respectSilence: true` forbids pairing with
  /// `focus: duckOthers` or `mixWithOthers` (an assertion in the package
  /// enforces this), so this is as close as AudioContextConfig gets to
  /// "notification, not media" without dropping to the raw AudioContext /
  /// AudioContextAndroid classes.
  static final AudioContext _context = AudioContextConfig(
    respectSilence: true,
    stayAwake: false,
  ).build();

  static Future<void> rideAlert() => _play('sounds/ride_alert.mp3');
  static Future<void> message() => _play('sounds/message.mp3');

  static void setEnabled(bool value) => _enabled = value;
  static bool get isEnabled => _enabled;

  /// Reads users/{uid}.notificationPrefs.sound once — called from each home
  /// screen's initState rather than before every sound, so a muted user
  /// never pays for a Firestore read on every ride event or chat message.
  static Future<void> loadPreference() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final prefs = doc.data()?['notificationPrefs'] as Map<String, dynamic>?;
      _enabled = prefs?['sound'] as bool? ?? true;
    } catch (_) {
      // Leave the in-memory default — a failed read shouldn't mute sounds
      // the user never asked to turn off.
    }
  }

  /// One shared player, not one per call — a player per sound would leak
  /// native resources. ReleaseMode.stop keeps this instance's resources
  /// ready between calls, and calling play() again on the same instance
  /// replaces whatever it's currently playing rather than layering a second
  /// sound on top.
  static Future<void> _play(String asset) async {
    if (!_enabled) return;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(AssetSource(asset), ctx: _context);
    } catch (e) {
      assert(() {
        // ignore: avoid_print
        print('SoundService: $asset failed — $e');
        return true;
      }());
    }
  }
}
