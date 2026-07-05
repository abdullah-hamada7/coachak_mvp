import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'pose_coordinate_mapper.dart';
import 'pose_utils.dart';

/// Builds [InputImage] instances from camera frames with correct rotation and
/// byte layout for ML Kit pose detection on Android and iOS.
class PoseInputImageBuilder {
  PoseInputImageBuilder._();

  static const _orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  static InputImage? fromCameraImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) {
    final rotation = _rotation(camera, deviceOrientation);
    if (rotation == null) return null;

    if (Platform.isAndroid) {
      final nv21 = _yuv420ToNv21(image);
      if (nv21 == null) return null;
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      );
      return InputImage.fromBytes(bytes: nv21, metadata: metadata);
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null || image.planes.isEmpty) return null;

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: image.planes.first.bytes, metadata: metadata);
  }

  /// Display-oriented size for mapping landmarks onto the preview canvas.
  static Size displaySize(InputImage input) {
    return PoseCoordinateMapper.rawImageSize(input);
  }

  static InputImageRotation? _rotation(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    if (Platform.isIOS) {
      final compensation = _orientations[deviceOrientation];
      if (compensation == null) return null;
      return InputImageRotationValue.fromRawValue((360 - compensation) % 360);
    }

    final sensorOrientation = camera.sensorOrientation;
    var compensation = _orientations[deviceOrientation];
    if (compensation == null) return null;

    if (camera.lensDirection == CameraLensDirection.front) {
      compensation = (sensorOrientation + compensation) % 360;
    } else {
      compensation = (sensorOrientation - compensation + 360) % 360;
    }
    return InputImageRotationValue.fromRawValue(compensation);
  }

  static Uint8List? _yuv420ToNv21(CameraImage image) {
    if (image.planes.length < 3) return null;

    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = width * height;
    final nv21 = Uint8List(ySize + (width * height ~/ 2));

    var offset = 0;
    for (var row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      nv21.setRange(offset, offset + width, yPlane.bytes.sublist(rowStart, rowStart + width));
      offset += width;
    }

    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        final uvIndex = row * uvRowStride + col * uvPixelStride;
        if (uvIndex >= vPlane.bytes.length || uvIndex >= uPlane.bytes.length) continue;
        nv21[offset++] = vPlane.bytes[uvIndex];
        nv21[offset++] = uPlane.bytes[uvIndex];
      }
    }

    return nv21;
  }
}

/// Picks the pose with the highest average landmark confidence.
Pose? selectBestPose(List<Pose> poses) {
  if (poses.isEmpty) return null;
  if (poses.length == 1) return poses.first;

  Pose? best;
  var bestScore = -1.0;
  for (final pose in poses) {
    if (pose.landmarks.isEmpty) continue;
    final score = pose.landmarks.values.map((lm) => lm.likelihood).reduce((a, b) => a + b) /
        pose.landmarks.length;
    if (score > bestScore) {
      bestScore = score;
      best = pose;
    }
  }
  return best ?? poses.first;
}

/// Minimum landmarks required before running form analysis.
bool hasMinimumPoseCoverage(Map<int, PosePoint> landmarks) {
  const core = [
    PoseLandmarks.leftShoulder,
    PoseLandmarks.rightShoulder,
    PoseLandmarks.leftHip,
    PoseLandmarks.rightHip,
    PoseLandmarks.leftKnee,
    PoseLandmarks.rightKnee,
  ];
  var visible = 0;
  for (final index in core) {
    final point = landmarks[index];
    if (point != null && point.likelihood >= 0.35) visible++;
  }
  return visible >= 4;
}
