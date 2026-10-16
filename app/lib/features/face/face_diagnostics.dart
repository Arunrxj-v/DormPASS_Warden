import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Debug-only diagnostics for the on-device face pipeline.
///
/// Used to trace camera → conversion → detection failures on real hardware.
/// NEVER logs biometric content: no image bytes, no face embeddings, no
/// passwords, no tokens. Frame geometry (format, size, strides), rotation
/// metadata, face counts, and bounding boxes are not biometric data and are
/// safe to print in debug builds (release builds are silent — [enabled] is
/// `kDebugMode`).
abstract final class FaceDiagnostics {
  static const bool enabled = kDebugMode;

  static void log(String message) {
    if (enabled) debugPrint('[FaceDiag] $message');
  }

  /// Structured, debug-only error report with the full stack trace.
  /// Never logs images, embeddings, passwords, tokens or keys — the
  /// exception type/message/stack of camera/ML Kit/TFLite failures are
  /// not biometric data.
  static void logError(String tag, Object error, StackTrace stack) {
    if (!enabled) return;
    debugPrint(
      '[FaceDiag] $tag\n'
      'type: ${error.runtimeType}\n'
      'message: $error\n'
      'stack: $stack',
    );
  }

  /// One-line, non-sensitive description of a camera frame's plane layout —
  /// the exact data needed to catch device-specific format mismatches.
  static String describeImage(CameraImage image) {
    final planes = image.planes
        .asMap()
        .entries
        .map(
          (e) =>
              'plane${e.key}(row=${e.value.bytesPerRow}/'
              'px=${e.value.bytesPerPixel})',
        )
        .join(' ');
    return 'fmt=${image.format.raw} ${image.width}x${image.height} '
        'planes=${image.planes.length} [$planes]';
  }
}
