import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Camera-frame utilities: YUV_420_888 → NV21 (for ML Kit) and mean
/// luminance from the Y plane (for the lighting gate, cheaply).
abstract final class CameraFrameUtils {
  /// Converts an Android YUV_420_888 [CameraImage] to an NV21 byte array,
  /// respecting per-plane row/pixel strides.
  static Uint8List toNV21(CameraImage image) {
    final w = image.width;
    final h = image.height;
    final y = image.planes[0];
    final u = image.planes[1];
    final v = image.planes[2];

    final out = Uint8List(w * h + (w * h) ~/ 2);

    // Y plane (packed).
    if (y.bytesPerRow == w) {
      out.setRange(0, w * h, y.bytes);
    } else {
      var offset = 0;
      for (var row = 0; row < h; row++) {
        final start = row * y.bytesPerRow;
        out.setRange(offset, offset + w, y.bytes, start);
        offset += w;
      }
    }

    // Interleaved V,U (NV21 chroma).
    final chromaW = w ~/ 2;
    final chromaH = h ~/ 2;
    var i = w * h;
    for (var row = 0; row < chromaH; row++) {
      final vBase = row * v.bytesPerRow;
      final uBase = row * u.bytesPerRow;
      final vStep = v.bytesPerPixel ?? 1;
      final uStep = u.bytesPerPixel ?? 1;
      for (var col = 0; col < chromaW; col++) {
        out[i++] = v.bytes[vBase + col * vStep];
        out[i++] = u.bytes[uBase + col * uStep];
      }
    }
    return out;
  }

  /// Mean brightness (0–255) sampled from the Y plane.
  static double meanLuminance(CameraImage image) {
    final y = image.planes[0].bytes;
    var sum = 0;
    var count = 0;
    // Sample every 16th byte — plenty for a lighting gate.
    for (var i = 0; i < y.length; i += 16) {
      sum += y[i];
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }
}
