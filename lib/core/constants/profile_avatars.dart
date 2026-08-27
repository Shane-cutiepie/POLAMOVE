/// Preset profile avatars. Photo upload would require Cloud Storage, which
/// needs a billing-enabled Firebase plan; presets give users personalisation
/// at no cost and no upload latency.
const List<String> kProfileAvatars = [
  '🧍', '🧑', '👩', '👨', '🧔', '👵', '👴', '🧑‍🎓',
  '👷', '🧑‍🌾', '🛺', '🌻', '⚽', '🎸', '🐈', '🐕',
];

/// Index into kProfileAvatars. Falls back to the first entry.
String avatarAt(int? index) =>
    (index != null && index >= 0 && index < kProfileAvatars.length)
        ? kProfileAvatars[index]
        : kProfileAvatars.first;
