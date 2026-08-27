import 'package:flutter/material.dart';
import '../../core/constants/profile_avatars.dart';

/// Resolves and renders a user's avatar: their uploaded photo when
/// [avatarUrl] is set, otherwise the preset emoji at [avatarIndex]. The
/// single place this resolution lives — every screen that shows an avatar
/// uses this instead of repeating the "avatarUrl, else avatarAt" check.
///
/// Sizing only. The caller keeps its own container — background, border,
/// shape — exactly as it already is; this widget only supplies what renders
/// inside it, at [size].
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final int? avatarIndex;
  final double size;

  /// Font size for the emoji fallback. Defaults to roughly half [size],
  /// which reads about right at every scale this app uses — pass an
  /// explicit value to match an existing call site exactly.
  final double? emojiSize;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    required this.avatarIndex,
    required this.size,
    this.emojiSize,
  });

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    if (url == null || url.isEmpty) return _emoji();

    // ClipOval, not CircleAvatar: CircleAvatar's backgroundImage has no
    // loadingBuilder/errorBuilder equivalent, and a broken or slow-loading
    // photo must fall back to the preset emoji rather than a broken-image
    // icon or a blank circle.
    return ClipOval(
      child: Image.network(
        _thumbnailUrl(url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _emoji(),
        errorBuilder: (context, error, stackTrace) => _emoji(),
      ),
    );
  }

  Widget _emoji() => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(avatarAt(avatarIndex),
              style: TextStyle(fontSize: emojiSize ?? size * 0.45)),
        ),
      );
}

/// Requests a face-cropped thumbnail instead of the full upload — the one
/// place this transform is applied, so every UserAvatar gets it for free.
/// w_200 comfortably covers every size this app displays an avatar at (the
/// largest is 64px, doubled for retina); c_fill,g_face crops to the face
/// rather than the geometric centre, since a photo can arrive at any aspect
/// ratio into a circular frame; q_auto/f_auto pick quality and format
/// automatically.
String _thumbnailUrl(String url) => url.replaceFirst(
    '/upload/', '/upload/w_200,c_fill,g_face,q_auto,f_auto/');
