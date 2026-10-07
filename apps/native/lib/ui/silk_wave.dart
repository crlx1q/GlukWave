import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class _Point3 {
  final double x, y, z;
  const _Point3(this.x, this.y, this.z);
  _Point3 minus(_Point3 b) => _Point3(x - b.x, y - b.y, z - b.z);
  _Point3 cross(_Point3 b) =>
      _Point3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
  _Point3 normalized() {
    final length = math.sqrt(x * x + y * y + z * z);
    return length < .000001
        ? const _Point3(0, 0, 1)
        : _Point3(x / length, y / length, z / length);
  }

  double dot(_Point3 b) => x * b.x + y * b.y + z * b.z;
}

/// CPU mesh port of the final HTML/WebGL twisted silk shape and lighting.
/// Flutter batches its depth-sorted triangles into a single native draw call.
void drawSilkWave(
  Canvas canvas,
  Size size,
  double phase,
  double energy,
  Color accent,
  Offset pointer,
  double pointerActive,
) {
  const columns = 72, bands = 16;
  _Point3 shape(double u, double v) {
    final bulge = 1 + .10 * math.cos(u * 3 + phase * .36),
        twist = u * 1.5 + .5 * math.sin(phase * .22),
        span = v * .49;
    var x = (1.25 + span * math.cos(twist)) * math.cos(u) * bulge,
        y = (1.25 + span * math.cos(twist)) * math.sin(u) * .80,
        z = span * math.sin(twist) + .29 * math.sin(u * 2 + phase * .32);
    final ry =
            .2 +
            math.sin(phase * .14) * .16 +
            (pointer.dx - .5) * pointerActive * .12,
        rx = .43 + (pointer.dy - .5) * pointerActive * .14,
        rz = -.30 + math.sin(phase * .12) * .08;
    var next = x * math.cos(ry) + z * math.sin(ry);
    z = -x * math.sin(ry) + z * math.cos(ry);
    x = next;
    next = y * math.cos(rx) - z * math.sin(rx);
    z = y * math.sin(rx) + z * math.cos(rx);
    y = next;
    next = x * math.cos(rz) + y * math.sin(rz);
    y = -x * math.sin(rz) + y * math.cos(rz);
    x = next;
    return _Point3(x, y, z);
  }

  final points = <_Point3>[], colors = <int>[], positions = <Offset>[];
  final light = const _Point3(-.6, -.8, 1.4).normalized(),
      half = const _Point3(
        -.6,
        -.8,
        1.4,
      ).normalized().minus(const _Point3(0, 0, -1)).normalized(),
      scale =
          math.min(size.width * .34, size.height * .34) * (1 + energy * .12);
  for (var i = 0; i <= columns; i++) {
    final u = i / columns * math.pi * 2;
    for (var j = 0; j <= bands; j++) {
      final v = j / bands * 2 - 1,
          point = shape(u, v),
          du = shape(u + .001, v).minus(shape(u - .001, v)),
          dv = shape(u, v + .001).minus(shape(u, v - .001)),
          normal = du.cross(dv).normalized();
      points.add(point);
      positions.add(
        Offset(
          size.width * .565 + point.x * (1 + point.z * .07) * scale,
          size.height * .51 + point.y * (1 + point.z * .07) * scale,
        ),
      );
      final diffuse = normal.dot(light).abs(),
          specular = math.pow(normal.dot(half).abs(), 32).toDouble(),
          fresnel = math.pow(1 - normal.z.abs(), 2).toDouble(),
          tone = .5 + .5 * math.sin(u * 1.6 + v * .8),
          pearlMix = .5 + .5 * math.sin(u * 1.2 + 1.3);
      final peach = const [.75, .53, .40],
          sage = const [.53, .64, .53],
          pearl = const [.83, .77, .84],
          highlight = const [1.0, .92, .81],
          tint = [accent.r, accent.g, accent.b];
      final rgb = List<double>.generate(3, (k) {
        final base =
            (peach[k] * (1 - tone) + sage[k] * tone) * (1 - pearlMix) +
            pearl[k] * pearlMix;
        final mixed = base * .72 + tint[k] * .28;
        return math
            .pow(
              (mixed * (.47 + diffuse * .84) +
                      highlight[k] * specular * .38 +
                      pearl[k] * fresnel * .17 +
                      .004 * math.sin(v * 700))
                  .clamp(0, 1),
              .85,
            )
            .toDouble();
      });
      colors.add(
        Color.from(
          alpha: 1,
          red: rgb[0],
          green: rgb[1],
          blue: rgb[2],
        ).toARGB32(),
      );
    }
  }
  final triangles = <(int, int, int, double)>[];
  for (var i = 0; i < columns; i++) {
    for (var j = 0; j < bands; j++) {
      final a = i * (bands + 1) + j,
          b = (i + 1) * (bands + 1) + j,
          c = b + 1,
          d = a + 1;
      triangles.add((a, b, c, (points[a].z + points[b].z + points[c].z) / 3));
      triangles.add((a, c, d, (points[a].z + points[c].z + points[d].z) / 3));
    }
  }
  triangles.sort((a, b) => a.$4.compareTo(b.$4));
  final rawPositions = Float32List(triangles.length * 6),
      rawColors = Int32List(triangles.length * 3);
  var at = 0;
  for (final triangle in triangles) {
    for (final id in [triangle.$1, triangle.$2, triangle.$3]) {
      rawPositions[at * 2] = positions[id].dx;
      rawPositions[at * 2 + 1] = positions[id].dy;
      rawColors[at] = colors[id];
      at++;
    }
  }
  final mesh = ui.Vertices.raw(
    ui.VertexMode.triangles,
    rawPositions,
    colors: rawColors,
  );
  canvas.drawVertices(mesh, BlendMode.srcOver, Paint());
  mesh.dispose();
}
