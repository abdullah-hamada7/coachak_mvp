import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Maps ML Kit pose landmarks from camera image space onto [CameraPreview] canvas.
///
/// Based on the official google_ml_kit_flutter coordinates_translator pattern.
class PoseCoordinateMapper {
  PoseCoordinateMapper._();

  /// Raw camera frame size (from InputImage metadata), not swapped.
  static Size rawImageSize(InputImage input) {
    final meta = input.metadata;
    if (meta == null) return Size.zero;
    return Size(meta.size.width, meta.size.height);
  }

  static Offset landmarkToCanvas({
    required double x,
    required double y,
    required Size canvasSize,
    required Size imageSize,
    required InputImageRotation rotation,
    required CameraLensDirection lens,
  }) {
    return Offset(
      translateX(x, canvasSize, imageSize, rotation, lens),
      translateY(y, canvasSize, imageSize, rotation, lens),
    );
  }

  static double translateX(
    double x,
    Size canvasSize,
    Size imageSize,
    InputImageRotation rotation,
    CameraLensDirection lens,
  ) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return x *
            canvasSize.width /
            (Platform.isIOS ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation270deg:
        return canvasSize.width -
            x *
                canvasSize.width /
                (Platform.isIOS ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        switch (lens) {
          case CameraLensDirection.back:
            return x * canvasSize.width / imageSize.width;
          default:
            return canvasSize.width - x * canvasSize.width / imageSize.width;
        }
    }
  }

  static double translateY(
    double y,
    Size canvasSize,
    Size imageSize,
    InputImageRotation rotation,
    CameraLensDirection lens,
  ) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y *
            canvasSize.height /
            (Platform.isIOS ? imageSize.height : imageSize.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvasSize.height / imageSize.height;
    }
  }

  /// Uniform scale for overlay radii/lines in canvas space.
  static double uniformScale(Size canvasSize, Size imageSize, InputImageRotation rotation) {
    if (imageSize.width == 0 || imageSize.height == 0) return 1;
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        final sx = canvasSize.width / (Platform.isIOS ? imageSize.width : imageSize.height);
        final sy = canvasSize.height / (Platform.isIOS ? imageSize.height : imageSize.width);
        return sx < sy ? sx : sy;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        final sx = canvasSize.width / imageSize.width;
        final sy = canvasSize.height / imageSize.height;
        return sx < sy ? sx : sy;
    }
  }
}
