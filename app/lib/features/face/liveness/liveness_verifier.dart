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
  late final _output = [_preds, _mask];

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
    _interpreter.run(input, _output);
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
