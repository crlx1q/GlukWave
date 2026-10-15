import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Flutter's Stack is a 2D painter; it does not perform CSS preserve-3d depth
/// testing. Project each physical plane, then remove only the overlapping
/// portion of genuinely nearer opaque planes. This also handles the open lid
/// crossing the case silhouette without sorting whole planes by their centre.
class CoverPlane {
  final Widget child;
  final Matrix4 transform;
  final double width, height;
  final bool twoSided, circle;
  const CoverPlane(
    this.child,
    this.transform,
    this.width,
    this.height, {
    this.twoSided = false,
    this.circle = false,
  });
}

class ProjectedCoverPlane {
  final CoverPlane plane;
  final Matrix4 matrix;
  final List<Offset> polygon;
  final List<double> inverseW;
  final bool visible;
  late final depth = _depthEquation(polygon, inverseW);
  ProjectedCoverPlane(this.plane, this.matrix)
    : visible = plane.twoSided || _facing(matrix, plane),
      polygon = _points(plane).map((p) => _project(matrix, p)).toList(),
      inverseW = _points(plane).map((p) => 1 / _w(matrix, p)).toList();
  Path get path => Path()..addPolygon(polygon, true);
  double at(Offset p) => depth[0] * p.dx + depth[1] * p.dy + depth[2];
}

bool _facing(Matrix4 matrix, CoverPlane plane) {
  final p = _points(plane).map((p) => _project(matrix, p)).toList();
  var area = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  return area > .00001;
}

List<Offset> _points(CoverPlane p) => p.circle
    ? [
        for (var i = 0; i < 48; i++)
          Offset(
            p.width * (.5 + .5 * math.cos(i * math.pi / 24)),
            p.height * (.5 + .5 * math.sin(i * math.pi / 24)),
          ),
      ]
    : [
        Offset.zero,
        Offset(p.width, 0),
        Offset(p.width, p.height),
        Offset(0, p.height),
      ];
double _w(Matrix4 m, Offset p) =>
    m.storage[3] * p.dx + m.storage[7] * p.dy + m.storage[15];
Offset _project(Matrix4 m, Offset p) => Offset(
  (m.storage[0] * p.dx + m.storage[4] * p.dy + m.storage[12]) / _w(m, p),
  (m.storage[1] * p.dx + m.storage[5] * p.dy + m.storage[13]) / _w(m, p),
);
List<double> _depthEquation(List<Offset> points, List<double> z) {
  // Use well-separated points even for a densely sampled circular surface.
  final a = points[0],
      bIndex = points.length ~/ 3,
      cIndex = points.length * 2 ~/ 3,
      b = points[bIndex],
      c = points[cIndex];
  final determinant =
      (b.dx - a.dx) * (c.dy - a.dy) - (c.dx - a.dx) * (b.dy - a.dy);
  if (determinant.abs() < .000001) return [0, 0, z[0]];
  final x =
      ((z[bIndex] - z[0]) * (c.dy - a.dy) -
          (z[cIndex] - z[0]) * (b.dy - a.dy)) /
      determinant;
  final y =
      ((b.dx - a.dx) * (z[cIndex] - z[0]) -
          (c.dx - a.dx) * (z[bIndex] - z[0])) /
      determinant;
  return [x, y, z[0] - x * a.dx - y * a.dy];
}

List<Offset> _nearPart(ProjectedCoverPlane other, ProjectedCoverPlane face) {
  final output = <Offset>[];
  var a = other.polygon.last, da = other.at(a) - face.at(a) - 1e-8;
  for (final b in other.polygon) {
    final db = other.at(b) - face.at(b) - 1e-8;
    if ((da > 0) != (db > 0)) {
      final fraction = da / (da - db);
      output.add(Offset.lerp(a, b, fraction)!);
    }
    if (db > 0) output.add(b);
    a = b;
    da = db;
  }
  return output;
}

Path visibleCoverPath(
  ProjectedCoverPlane face,
  List<ProjectedCoverPlane> scene,
) {
  if (!face.visible) return Path();
  var result = face.path;
  for (final other in scene) {
    if (identical(face, other) || !other.visible) continue;
    final polygon = _nearPart(other, face);
    if (polygon.length < 3) continue;
    result = Path.combine(
      PathOperation.difference,
      result,
      Path()..addPolygon(polygon, true),
    );
  }
  return result;
}

class _SurfaceClip extends CustomClipper<Path> {
  final Path path;
  const _SurfaceClip(this.path);
  @override
  Path getClip(Size size) => path;
  @override
  bool shouldReclip(_SurfaceClip old) => old.path != path;
}

class AlbumPlaneScene extends StatelessWidget {
  final Matrix4 camera;
  final double size;
  final List<CoverPlane> planes;
  const AlbumPlaneScene({
    super.key,
    required this.camera,
    required this.size,
    required this.planes,
  });
  List<ProjectedCoverPlane> get projected {
    final world = Matrix4.identity()
      ..translateByDouble(size / 2, size / 2, 0, 1)
      ..multiply(camera)
      ..translateByDouble(-size / 2, -size / 2, 0, 1);
    return planes
        .map(
          (p) => ProjectedCoverPlane(p, world.clone()..multiply(p.transform)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = projected;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final surface in surfaces)
            Positioned.fill(
              child: ClipPath(
                clipper: _SurfaceClip(visibleCoverPath(surface, surfaces)),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Transform(
                        transform: surface.matrix,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: surface.plane.width,
                          height: surface.plane.height,
                          child: surface.plane.child,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
