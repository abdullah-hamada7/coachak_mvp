import 'dart:math' show pi;
import 'dart:ui' as ui show ParagraphBuilder, ParagraphConstraints, ParagraphStyle, TextStyle;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../engine/pose_coordinate_mapper.dart';
import '../engine/pose_utils.dart';

/// Renders OpenCV-style angle arcs and guide lines from form analysis engines.
class FormOverlayPainter extends CustomPainter {
  FormOverlayPainter({
    required this.hints,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final List<FormOverlayHint> hints;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;

  @override
  void paint(Canvas canvas, Size size) {
    for (final hint in hints) {
      switch (hint.kind) {
        case FormOverlayKind.arc:
          _paintArc(canvas, size, hint);
        case FormOverlayKind.guideLine:
          _paintGuideLine(canvas, size, hint);
        case FormOverlayKind.label:
          _paintLabel(canvas, size, hint);
      }
    }
  }

  void _paintArc(Canvas canvas, Size size, FormOverlayHint hint) {
    final center = hint.center;
    final radius = hint.radius;
    final start = hint.startAngleDeg;
    final sweep = hint.sweepAngleDeg;
    if (center == null || radius == null || start == null || sweep == null) return;

    final mapped = _mapPoint(center, size);
    final scale = PoseCoordinateMapper.uniformScale(size, imageSize, rotation);
    final paint = Paint()
      ..color = Color(hint.colorArgb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawArc(
      Rect.fromCircle(center: mapped, radius: radius * scale),
      start * pi / 180,
      sweep * pi / 180,
      false,
      paint,
    );

    if (hint.label != null) {
      _drawText(canvas, mapped + Offset(radius * scale + 4, -8), hint.label!, hint.colorArgb);
    }
  }

  void _paintGuideLine(Canvas canvas, Size size, FormOverlayHint hint) {
    final from = hint.from;
    final to = hint.to;
    if (from == null || to == null) return;

    final paint = Paint()
      ..color = Color(hint.colorArgb)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(_mapPoint(from, size), _mapPoint(to, size), paint);
  }

  void _paintLabel(Canvas canvas, Size size, FormOverlayHint hint) {
    final center = hint.center;
    if (center == null || hint.label == null) return;
    _drawText(canvas, _mapPoint(center, size), hint.label!, hint.colorArgb);
  }

  void _drawText(Canvas canvas, Offset at, String text, int colorArgb) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: 14,
        textAlign: TextAlign.left,
      ),
    )
      ..pushStyle(ui.TextStyle(color: Color(colorArgb), fontWeight: FontWeight.bold))
      ..addText(text);

    final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 80));
    canvas.drawParagraph(paragraph, at);
  }

  Offset _mapPoint(PosePoint point, Size canvasSize) {
    return PoseCoordinateMapper.landmarkToCanvas(
      x: point.x,
      y: point.y,
      canvasSize: canvasSize,
      imageSize: imageSize,
      rotation: rotation,
      lens: lensDirection,
    );
  }

  @override
  bool shouldRepaint(FormOverlayPainter oldDelegate) =>
      oldDelegate.hints != hints ||
      oldDelegate.imageSize != imageSize ||
      oldDelegate.rotation != rotation ||
      oldDelegate.lensDirection != lensDirection;
}
