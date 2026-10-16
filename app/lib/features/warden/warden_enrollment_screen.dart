import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../face/camera_frame_utils.dart';
import '../face/face_diagnostics.dart';
import '../face/face_detector_service.dart';
import '../face/face_embedder.dart';
import '../face/face_providers.dart';
import 'warden_models.dart';
import 'warden_providers.dart';

/// Warden-initiated face enrollment for ONE named student.
///
/// Reuses the proven camera + ML Kit + MobileFaceNet pipeline from the
/// student self-enrollment screen; the differences are the persistent
/// identity banner (so the warden never enrolls the wrong person) and the
/// upload target (`WardenRepository.enrollFace`).
class WardenEnrollmentScreen extends ConsumerStatefulWidget {
  const WardenEnrollmentScreen({super.key, required this.studentRef});

  final String studentRef;

  @override
  ConsumerState<WardenEnrollmentScreen> createState() =>
      _WardenEnrollmentScreenState();
}

enum _Stage { initial, capturing, uploading, done, failed }

class _WardenEnrollmentScreenState
    extends ConsumerState<WardenEnrollmentScreen> {
  CameraController? _controller;
  final _detector = FaceDetectorService();

  _Stage _stage = _Stage.initial;
  int _samples = 0;
  String? _hint;
  AppException? _error;
  bool _streamBusy = false;
  double _luminance = 128;
  String? _cameraError;
  DateTime _lastDetect = DateTime.fromMillisecondsSinceEpoch(0);
  int _framesSeen = 0;
  String _lensDesc = 'unknown';
  final _sampleEmbeddings = <List<double>>[];

  static const _targetSamples = 3;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    setState(() {
      _stage = _Stage.initial;
      _hint = null;
      _error = null;
      _samples = 0;
      _cameraError = null;
      _sampleEmbeddings.clear();
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera is available on this device.');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      FaceDiagnostics.log(
        'camera ready: lens=${front.lensDirection} '
        'sensor=${front.sensorOrientation} '
        'preview=${controller.value.previewSize} '
        'detectorInitialized=true',
      );
      _lensDesc = front.lensDirection.name;
      await controller.startImageStream((image) {
        _framesSeen++;
        _luminance = CameraFrameUtils.meanLuminance(image);
        _gateHint(image);
      });
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _stage = _Stage.capturing;
      });
    } on CameraException catch (e) {
      final denied =
          e.code == 'PermissionDenied' ||
          e.code == 'PermissionDeniedByUser' ||
          e.code == 'PermissionDeniedBySystem';
      FaceDiagnostics.log('camera init failed: ${e.code}: ${e.description}');
      setState(() {
        _cameraError = denied
            ? 'Camera permission was denied. Face enrollment needs the '
                  'camera — enable camera access for HostelPass in system '
                  'settings, then retry. No face data was captured or '
                  'uploaded.'
            : 'Camera could not be started (${e.code}: ${e.description}). '
                  'No face data was captured. Retry, or close and reopen '
                  'this screen.';
        _stage = _Stage.failed;
      });
    } catch (_) {
      setState(() {
        _cameraError =
            'Camera could not be started. No face data was captured. '
            'Retry, or close and reopen this screen.';
        _stage = _Stage.failed;
      });
    }
  }

  void _gateHint(CameraImage image) {
    if (_streamBusy || _stage != _Stage.capturing) return;
    // Throttle detection to ~5 Hz (same as the proven student-app screen):
    // full-rate ML Kit on every high-res frame starves the UI thread.
    final now = DateTime.now();
    if (now.difference(_lastDetect).inMilliseconds < 200) return;
    _streamBusy = true;
    _lastDetect = now;
    final controller = _controller;
    if (controller == null) {
      _streamBusy = false;
      return;
    }
    final sensor = controller.description.sensorOrientation;
    final rotation = switch (sensor) {
      0 => InputImageRotation.rotation0deg,
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      _ => InputImageRotation.rotation270deg,
    };

    // D1 fix: toNV21 runs SYNCHRONOUSLY as an argument here. On some devices
    // its plane strides can throw (RangeError on short buffers) — before this
    // try/catch that exception escaped into the camera plugin's stream
    // callback, leaving _streamBusy stuck true and killing detection for the
    // rest of the session. The busy flag is now always released.
    try {
      final nv21 = CameraFrameUtils.toNV21(image);
      if (_framesSeen == 1 || _framesSeen % 60 == 0) {
        FaceDiagnostics.log(
          'frame #$_framesSeen: ${FaceDiagnostics.describeImage(image)} '
          'rot=$rotation lum=${_luminance.toStringAsFixed(0)} '
          'lens=$_lensDesc detectorInitialized=true',
        );
      }
      final future = _detector.detectInNV21(
        bytes: nv21,
        width: image.width,
        height: image.height,
        rotation: rotation,
      );
      future.then((result) {
        _streamBusy = false;
        if (!mounted) return;
        _applyHint(result);
      }).catchError((Object e, StackTrace st) {
        // D3 fix: detector failures are no longer silent.
        FaceDiagnostics.logError('FACE_DETECTOR_ERROR', e, st);
        _streamBusy = false;
      });
      return; // futures own the busy-flag release from here on.
    } catch (e, st) {
      // Synchronous failure (frame conversion, detector construction, ...).
      FaceDiagnostics.logError('FACE_DETECTOR_ERROR', e, st);
      _streamBusy = false;
      return;
    }
  }

  void _applyHint(List<DetectedFace> faces) {
    String hint;
    if (faces.isEmpty) {
      hint = 'Position the student’s face inside the frame';
    } else if (faces.length > 1) {
      hint = 'More than one face — only the student may be in frame';
    } else if (!faces.first.eyesOpen) {
      hint = 'Ask the student to keep their eyes open';
    } else if (_luminance < 60) {
      hint = 'Too dark — face a light source';
    } else if (_luminance > 220) {
      hint = 'Too bright — move away from direct light';
    } else {
      hint = 'Ready — hold still';
    }
    if (hint != _hint) {
      FaceDiagnostics.log(
        'hint: "$hint" (faces=${faces.length} '
        'box=${faces.isEmpty ? "none" : faces.first.box})',
      );
    }
    setState(() => _hint = hint);
  }

  Future<void> _captureSample() async {
    final controller = _controller;
    if (controller == null || _stage != _Stage.capturing) return;
    // Hard gate: never capture without a single, well-lit, eyes-open face.
    if (_hint == null || !_hint!.startsWith('Ready')) {
      setState(
        () => _hint = _hint ?? 'Position the student’s face in the frame',
      );
      return;
    }
    // D2 fix: each failure now reports honestly. "No face detected" is only
    // shown when the detector truly found no face in the still — a camera or
    // engine failure no longer masquerades as a framing problem.
    XFile shot;
    try {
      shot = await controller.takePicture();
    } on CameraException catch (e) {
      FaceDiagnostics.log('takePicture failed: ${e.code}: ${e.description}');
      setState(() => _error = const AppException('local_capture_failed'));
      return;
    }
    final file = File(shot.path);
    List<DetectedFace> faces;
    FaceDiagnostics.log(
      'still detect exec: detectorInitialized=true rotation=exif(file)',
    );
    try {
      faces = await _detector.detectInFile(file);
    } catch (e, st) {
      FaceDiagnostics.logError('FACE_DETECTOR_ERROR', e, st);
      setState(() => _error = const AppException('local_detector_failed'));
      return;
    }
    FaceDiagnostics.log('still: faces=${faces.length}');
    if (faces.isEmpty) {
      setState(() => _error = const AppException('local_no_face'));
      return;
    }
    if (faces.length > 1) {
      setState(() => _error = const AppException('local_multiple_faces'));
      return;
    }
    try {
      final embedder = await ref.read(faceEmbedderProvider.future);
      FaceDiagnostics.log('stage: embedder ready');
      final upright = FaceEmbedder.decodeUprightJpeg(file);
      if (upright == null) {
        FaceDiagnostics.log('still JPEG could not be decoded');
        setState(() => _error = const AppException('local_capture_failed'));
        return;
      }
      final embed = embedder.embedFromCrop(upright, faces.first.box);
      FaceDiagnostics.log('stage: embed ok (len=${embed.length})');
      _sampleEmbeddings.add(embed);
      setState(() {
        _error = null;
        _samples += 1;
      });
      if (_samples >= _targetSamples) {
        await _enroll();
      } else {
        setState(
          () => _hint =
              'Sample $_samples/$_targetSamples captured — adjust slightly '
              'and hold',
        );
      }
    } catch (e, st) {
      // Embedder load / crop / inference failure — NOT a face problem.
      FaceDiagnostics.logError('FACE_EMBEDDER_ERROR', e, st);
      setState(() => _error = const AppException('local_detector_failed'));
    }
  }

  /// Same averaging + normalization math as the student self-enrollment
  /// screen (copied verbatim so both paths produce identical templates).
  List<double> _average(List<List<double>> vectors) {
    if (vectors.length == 1) return vectors.first;
    final dim = vectors.first.length;
    final out = List<double>.filled(dim, 0);
    for (final v in vectors) {
      for (var i = 0; i < dim; i++) {
        out[i] += v[i];
      }
    }
    var norm = 0.0;
    for (var i = 0; i < dim; i++) {
      out[i] /= vectors.length;
      norm += out[i] * out[i];
    }
    norm = norm == 0 ? 1 : norm;
    for (var i = 0; i < dim; i++) {
      out[i] /= norm;
    }
    return out;
  }

  Future<void> _enroll() async {
    setState(() => _stage = _Stage.uploading);
    try {
      final averaged = _average(_sampleEmbeddings);
      await ref
          .read(wardenRepositoryProvider)
          .enrollFace(
            ref: widget.studentRef,
            embedding: averaged,
            modelVersion: FaceEmbedder.modelVersion,
          );
      if (!mounted) return;
      setState(() => _stage = _Stage.done);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = e;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = const AppException(
          'local_server_unreachable',
          message:
              'The template was NOT saved. Nothing is enrolled until '
              'the server confirms it.',
        );
      });
    }
  }

  void _finish() {
    ref.read(studentDetailRefreshProvider.notifier).state++;
    ref.invalidate(wardenStudentsProvider);
    ref.invalidate(wardenDashboardProvider);
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _controller
        ?.stopImageStream()
        .then((_) => _controller?.dispose())
        .catchError((_) {});
    _detector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(studentDetailProvider(widget.studentRef));
    final student = detail.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Enroll Student Face')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Identity banner (always visible) ----
              _IdentityBanner(
                studentRef: widget.studentRef,
                student: student,
                loading: detail.isLoading,
                error: detail.error,
              ),
              const SizedBox(height: 12),

              if (_stage == _Stage.done) ...[
                _buildDone(student?.name),
              ] else if (_stage == _Stage.failed && _cameraError != null) ...[
                ErrorBar(message: _cameraError!, onRetry: _initCamera),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Cancel and go back'),
                ),
              ] else if (_stage == _Stage.failed) ...[
                ErrorBar(
                  message:
                      _error?.displayMessage ??
                      'Enrollment failed. Nothing was saved.',
                  onRetry: _initCamera,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Cancel'),
                ),
              ] else ...[
                // Camera viewport
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 360,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _preview(),
                        CustomPaint(painter: _OvalPainter()),
                        if (_hint != null)
                          Positioned(
                            left: 24,
                            right: 24,
                            bottom: 20,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xB3111827),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _hint!,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.labelLg.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Sample progress
                Row(
                  children: List.generate(_targetSamples, (i) {
                    final done = i < _samples;
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                          right: i == _targetSamples - 1 ? 0 : 8,
                        ),
                        height: 6,
                        decoration: BoxDecoration(
                          color: done
                              ? AppColors.primary
                              : AppColors.cardHighest,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _stage == _Stage.uploading
                        ? 'Encrypting and uploading the template…'
                        : 'Sample $_samples of $_targetSamples',
                    style: AppTextStyles.labelLg.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                if (_error != null) ...[
                  ErrorBar(
                    message: _error!.displayMessage,
                    onRetry: () => setState(() => _error = null),
                  ),
                  const SizedBox(height: 12),
                ],

                FilledButton(
                  onPressed:
                      _stage == _Stage.capturing &&
                          _hint == 'Ready — hold still'
                      ? _captureSample
                      : null,
                  child: _stage == _Stage.uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_camera_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Capture Sample'),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _hint == 'Ready — hold still'
                        ? 'The student is positioned correctly.'
                        : 'Capture unlocks when the quality gate passes.',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.textDisabled,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDone(String? name) {
    return SectionCard(
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check,
              color: AppColors.successText,
              size: 30,
            ),
          ),
          const SizedBox(height: 10),
          Text('Face Enrolled', style: AppTextStyles.headlineSm),
          const SizedBox(height: 4),
          Text(
            name == null
                ? 'The face template was accepted by the server.'
                : 'The face template for $name was accepted and stored by '
                      'the server. Only now is the student considered '
                      'enrolled.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: _finish, child: const Text('Done')),
        ],
      ),
    );
  }

  Widget _preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: const Color(0xFF20242A),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(-1, 1, 1),
      child: CameraPreview(controller),
    );
  }
}

/// Persistent, prominent identity banner — the warden must always be able to
/// see whose face is being enrolled.
class _IdentityBanner extends StatelessWidget {
  const _IdentityBanner({
    required this.studentRef,
    required this.student,
    required this.loading,
    required this.error,
  });

  final String studentRef;
  final EnrollmentStatus? student;
  final bool loading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final name = student?.name;
    final roll = student?.roll;
    final email = student?.email;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_pin_outlined,
                size: 18,
                color: AppColors.primaryTintText,
              ),
              const SizedBox(width: 6),
              Text(
                'ENROLLING',
                style: AppTextStyles.microLabel(
                  color: AppColors.primaryTintText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (loading)
            Text(
              'Loading student identity…',
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.primaryTintText,
              ),
            )
          else if (error != null || name == null)
            Text(
              'Could not load the identity for “$studentRef”. Enrolling '
              'without a confirmed identity is not allowed — go back and '
              'retry.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.dangerText,
                height: 16 / 12,
              ),
            )
          else ...[
            Text(
              name,
              style: AppTextStyles.headlineSm.copyWith(
                color: AppColors.primaryTintText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (roll != null) 'Roll $roll',
                if (email != null) email,
              ].join(' • '),
              style: AppTextStyles.tabularSm.copyWith(
                color: AppColors.primaryTintText,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text(
              'Confirm the student in front of the camera matches this name. '
              'You are enrolling THEM, not yourself.',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.dangerText,
                fontWeight: FontWeight.w600,
                height: 16 / 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OvalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: size.width * 0.6,
      height: size.height * 0.62,
    );
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addOval(oval);
    canvas.drawPath(path, Paint()..color = const Color(0x66000000));
    canvas.drawOval(
      oval,
      Paint()
        ..color = Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_OvalPainter old) => false;
}
