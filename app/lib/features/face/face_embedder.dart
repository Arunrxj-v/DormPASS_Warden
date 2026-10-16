import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'face_diagnostics.dart';

/// MobileFaceNet on-device embedding engine (bundled TFLite, no download).
///
/// Model: `assets/models/mobilefacenet.tflite`
///   input  [1,112,112,3] float32 RGB, (x − 127.5) / 128.0
///   output [1,128] → L2-normalized → cosine similarity on the server.
/// See docs/MODEL_PROVENANCE.md (Apache-2.0 upstream).
class FaceEmbedder {
  FaceEmbedder._(this._interpreter);

  static const modelAsset = 'assets/models/mobilefacenet.tflite';
  static const modelVersion = 'mobilefacenet_tflite_128_v1';
  static const inputSize = 112;

  final Interpreter _interpreter;
  static FaceEmbedder? _instance;

  /// Process-wide singleton — interpreter allocation is not cheap.
  static Future<FaceEmbedder> load() async {
    if (_instance != null) return _instance!;
    try {
      final interpreter = await Interpreter.fromAsset(modelAsset);
      _instance = FaceEmbedder._(interpreter);
      FaceDiagnostics.log(
        'model loaded: in=${interpreter.getInputTensor(0).shape} '
        'out=${interpreter.getOutputTensors().first.shape}',
      );
      return _instance!;
    } catch (e) {
      FaceDiagnostics.log('model load failed: $e');
      rethrow;
    }
  }

  /// Aligns/crops the ML Kit face box (with margin) from an upright bitmap and
  /// returns an L2-normalized 128-d embedding.
  List<double> embedFromCrop(img.Image upright, Rect faceBox) {
    final crop = _cropWithMargin(upside: upright, box: faceBox);
    return embed(crop);
  }

  /// Direct embedding of a face crop (already tight).
  List<double> embed(img.Image face) {
    final resized = img.copyResize(
      face,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );
    final input = Float32List(1 * inputSize * inputSize * 3);
    var i = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final p = resized.getPixel(x, y);
        input[i++] = (p.r.toDouble() - 127.5) / 128.0;
        input[i++] = (p.g.toDouble() - 127.5) / 128.0;
        input[i++] = (p.b.toDouble() - 127.5) / 128.0;
      }
    }
    try {
      FaceDiagnostics.log(
        'embed exec: input=${input.length}px(112x112x3 f32) '
        'tensorShape=${_interpreter.getInputTensor(0).shape}',
      );
      // Root-cause fix: Interpreter.run calls
      // Tensor.getInputShapeIfDifferent(input), which computes the shape of a
      // FLAT Float32List as [input.length] — i.e. [37632] — finds it different
      // from the model's [1,112,112,3], and resizes the input tensor to that
      // 1-D shape. The resize itself succeeds, but the graph then fails to
      // prepare (first op is Conv2D, which requires 4-D input), and TFLite's
      // AllocateTensors/Invoke return an error status that tflite_flutter
      // surfaces as the opaque `StateError: Bad state: failed precondition`.
      // Passing the raw little-endian bytes (Uint8List) takes the library's
      // documented fast path: getInputShapeIfDifferent returns null for
      // Uint8List (no resize), and setTo copies the buffer straight into the
      // unchanged [1,112,112,3] float32 tensor — the byte layout is identical
      // (row-major RGB).
      _interpreter.run(input.buffer.asUint8List(), _output);
    } catch (e, st) {
      final inShape = _interpreter.getInputTensor(0).shape;
      FaceDiagnostics.log('interpreter.run failed; inShape=$inShape '
          'inputLen=${input.length}');
      FaceDiagnostics.logError('FACE_EMBEDDER_ERROR', e, st);
      rethrow;
    }
    final raw = _output[0];
    return _l2Normalize(raw);
  }

  // Output buffer, allocated once.
  //
  // Second half of the root-cause fix: Tensor.copyTo reshapes the result
  // bytes to the output tensor's shape [1,128] as a plain nested
  // List<List<double>> and then assigns it element-by-element into this
  // buffer. A [Float32List(128)] buffer would throw
  // `TypeError: type 'List<double>' is not a subtype of type 'Float32List'`
  // at that assignment (shapes match, element types don't). A nested plain
  // list matches the library's reshape output, and read-back below still
  // yields List<double>.
  late final _output = [List<double>.filled(128, 0.0)];

  /// Crops the face box expanded by [margin] (fraction of box size per side),
  /// clamped to image bounds — tight crops matter for both models.
  static img.Image _cropWithMargin({
    required img.Image upside,
    required Rect box,
    double margin = 0.22,
  }) {
    final expandX = box.width * margin;
    final expandY = box.height * margin;
    final left = math.max(0, (box.left - expandX)).round();
    final top = math.max(0, (box.top - expandY)).round();
    final right = math.min(upside.width, (box.right + expandX).round());
    final bottom = math.min(upside.height, (box.bottom + expandY).round());
    final w = math.max(1, right - left);
    final h = math.max(1, bottom - top);
    return img.copyCrop(upside, x: left, y: top, width: w, height: h);
  }

  static List<double> _l2Normalize(List<double> v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final norm = math.sqrt(sum);
    if (norm == 0) return v;
    return v.map((x) => x / norm).toList();
  }

  void dispose() => _interpreter.close();

  /// Decodes a JPEG file and bakes EXIF orientation, yielding the same upright
  /// frame ML Kit reports bounding boxes in.
  static img.Image? decodeUprightJpeg(File file) {
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return img.bakeOrientation(decoded);
  }
}
