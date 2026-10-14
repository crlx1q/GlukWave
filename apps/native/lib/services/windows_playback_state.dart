bool nonFatalMpvMessage(String message) =>
    message.contains('Failed to create file cache') ||
    message.contains('property not found') && message.contains('osc');

/// Completion belongs to an actively playing, fully opened source. mpv also
/// emits completion resets during opens/seeks, including prepared paused audio.
bool nativeCompletionIsCurrent({
  required bool completed,
  required bool mediaOpened,
  required bool playing,
  required bool loading,
  required bool seeking,
  required Duration position,
  Duration? duration,
}) =>
    completed &&
    mediaOpened &&
    playing &&
    !loading &&
    !seeking &&
    (duration == null ||
        duration <= Duration.zero ||
        position >= duration - const Duration(milliseconds: 650));
