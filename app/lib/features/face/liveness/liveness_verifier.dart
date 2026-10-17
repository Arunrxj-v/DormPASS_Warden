import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Result of one liveness evaluation on a captured face crop.
class LivenessResult {
  const LivenessResult({
    required this.passed,
    required this.score,
    required this.method,
  });

  final bool passed;
  final double score;
  final String method;
}

/// Liveness / presentation-attack-detection abstraction.
///
/// v1 ships a *real* passive texture-based anti-spoof model (see
/// docs/MODEL_PROVENANCE.md). It is not a hardcoded success and not a blink
/// heuristic. Extension point: an active challenge-response verifier can be
/// added behind this same interface once validated — deliberately not shipped
/// as an unvalidated heuristic.
abstract class LivenessVerifier {
  /// Machine method id sent to the server (`liveness.method`).
  String get method;

  /// Evaluate a *tight* face crop. Passing [faceRgb] with background strongly
  /// skews the model — callers must pass bounding-box crops only.
  LivenessResult verify(img.Image faceRgb);
}

/// Passive PAD via the bundled "Deep-Tree" anti-spoof TFLite model (MIT).
///
/// Model: `assets/models/FaceAntiSpoofing.tflite`
///   input  [1,256,256,3] float32 RGB in [0,1]
///   heads  `Identity` (8 class predictions), `Identity_1` (one-hot leaf mask)
///   rule   spoof_score = Σ |predᵢ|·maskᵢ ;  ≤ 0.2 ⇒ live, > 0.2 ⇒ attack
/// (published decision rule from the upstream reference implementation.)
///
/// Honest limitation: true detection error rates are unknown until calibrated
/// on real attack samples; see docs/MODEL_PROVENANCE.md.
class PassiveAntiSpoofVerifier implements LivenessVerifier {
  PassiveAntiSpoofVerifier._(this._interpreter);

  static const modelAsset = 'assets/models/FaceAntiSpoofing.tflite';
  static const double spoofThreshold = 0.2;
  static const int inputSize = 256;

  @override
  String get method => 'antispoof_model_v1';

  final Interpreter _interpreter;
  static PassiveAntiSpoofVerifier? _instance;

  static Future<PassiveAntiSpoofVerifier> load() async => _instance ??=
      PassiveAntiSpoofVerifier._(await Interpreter.fromAsset(modelAsset));

  late final _preds = Float32List(8);
  late final _mask = Float32List(8);

  // Raw little-endian float32 byte buffers for the two output heads.
  //
  // tflite_flutter's run() computes the shape of a flat Float32List input as
  // [input.length] and RESIZES the model input to that 1-D shape; the first
  // op (Conv2D) requires 4-D input, so AllocateTensors fails with
  // `Bad state: failed precondition`. Uint8List inputs skip that shape path
  // (no resize) and are copied in verbatim; Uint8List outputs are copied back
  // verbatim. Same root cause + fix as face_embedder.dart.
  late final _predsBytes = Uint8List(8 * 4);
  late final _maskBytes = Uint8List(8 * 4);

  @override
  LivenessResult verify(img.Image faceRgb) {
    final resized = img.copyResize(
      faceRgb,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );
    final input = Float32List(1 * inputSize * inputSize * 3);
    var i = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final p = resized.getPixel(x, y);
        input[i++] = p.r.toDouble() / 255.0;
        input[i++] = p.g.toDouble() / 255.0;
        input[i++] = p.b.toDouble() / 255.0;
      }
    }
    _interpreter.runForMultipleInputs(
      [input.buffer.asUint8List()],
      {0: _predsBytes, 1: _maskBytes},
    );
    _decodeF32(_predsBytes, _preds);
    _decodeF32(_maskBytes, _mask);
    var score = 0.0;
    for (var k = 0; k < 8; k++) {
      score += _preds[k].abs() * _mask[k];
    }
    score = double.parse(score.toStringAsFixed(4));
    return LivenessResult(
      passed: score <= spoofThreshold,
      score: score,
      method: method,
    );
  }

  /// Copies a little-endian float32 byte buffer into [dst].
  static void _decodeF32(Uint8List bytes, Float32List dst) {
    final bd =
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    for (var i = 0; i < dst.length; i++) {
      dst[i] = bd.getFloat32(i * 4, Endian.little);
    }
  }

  void dispose() => _interpreter.close();

  /// Sanity helper reused by unit tests: computes the published rule from raw
  /// head outputs without a model round-trip.
  static double scoreFromHeads(List<double> preds, List<double> mask) {
    var s = 0.0;
    for (var i = 0; i < preds.length && i < mask.length; i++) {
      s += preds[i].abs() * mask[i];
    }
    return math.max(0, s);
  }
}
