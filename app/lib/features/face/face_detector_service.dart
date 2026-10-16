import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Detected face in upright-image coordinates.
class DetectedFace {
  const DetectedFace({required this.box, this.leftEyeOpen, this.rightEyeOpen});

  final Rect box;
  final double? leftEyeOpen;
  final double? rightEyeOpen;

  bool get eyesOpen =>
      (leftEyeOpen == null || leftEyeOpen! > 0.25) &&
      (rightEyeOpen == null || rightEyeOpen! > 0.25);
}

/// Thin wrapper over ML Kit face detection (on-device, bundled model).
/// Detection only — it does NOT identify anyone (see FaceEmbedder).
class FaceDetectorService {
  FaceDetectorService({FaceDetectorOptions? options})
    : _detector = FaceDetector(
        options:
            options ??
            FaceDetectorOptions(
              enableLandmarks: true,
              enableClassification:
                  true, // eye-open probabilities for the quality gate
              enableTracking: false,
              minFaceSize: 0.15,
              performanceMode: FaceDetectorMode.accurate,
            ),
      );

  final FaceDetector _detector;

  Future<List<DetectedFace>> detectInFile(File file) async {
    final faces = await _detector.processImage(InputImage.fromFile(file));
    return faces.map(_map).toList();
  }

  /// Live-stream detection from NV21 bytes captured by the camera plugin.
  Future<List<DetectedFace>> detectInNV21({
    required Uint8List bytes,
    required int width,
    required int height,
    required InputImageRotation rotation,
  }) async {
    final input = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: width,
      ),
    );
    final faces = await _detector.processImage(input);
    return faces.map(_map).toList();
  }

  DetectedFace _map(Face f) => DetectedFace(
    box: f.boundingBox,
    leftEyeOpen: f.leftEyeOpenProbability,
    rightEyeOpen: f.rightEyeOpenProbability,
  );

  Future<void> dispose() => _detector.close();
}
