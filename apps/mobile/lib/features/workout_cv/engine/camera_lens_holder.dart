import 'package:camera/camera.dart';

/// Optional active camera passed from [WorkoutCvScreen] into rule engines.
mixin CameraLensHolder {
  CameraLensDirection? activeCameraLens;
}
