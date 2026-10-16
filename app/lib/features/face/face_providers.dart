import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'face_embedder.dart';

/// Process-wide MobileFaceNet engine (see [FaceEmbedder.load]).
///
/// Lives in the face feature (not the deleted student attendance flow) so the
/// warden enrollment screen shares the exact same embedding pipeline as every
/// other capture path.
final faceEmbedderProvider = FutureProvider<FaceEmbedder>(
  (ref) => FaceEmbedder.load(),
);
