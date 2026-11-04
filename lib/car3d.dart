/// Carro 3D estilizado, desenhado peça por peça só com Flutter (sem
/// WebView nem modelos externos): gira, aproxima, destaca a peça sob o
/// cursor, pinta as avarias pela gravidade e diz qual peça foi tocada.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'inspection.dart';

class V3 {
  const V3(this.x, this.y, this.z);
  final double x, y, z;
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  double get length => math.sqrt(dot(this));
  V3 get unit {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }
}

/// Tipo de superfície (muda a cor base).
enum Surface { body, glass, tire, rim, light, tail, dark, mirror }

class Tri {
  const Tri(this.a, this.b, this.c, this.part, this.surface);
  final V3 a, b, c;
  final String part; // '' = não clicável
  final Surface surface;
}

class CarMesh {
  CarMesh(this.body, this.tris, this.anchors);
  final CarBody body;
  final List<Tri> tris;

  /// Ponto de cada peça para o marcador numerado (um pouco para fora).
  final Map<String, V3> anchors;
}

class _Builder {
  final tris = <Tri>[];
  final _sum = <String, V3>{};
  final _n = <String, int>{};

  void tri(V3 a, V3 b, V3 c, String part, [Surface s = Surface.body]) {
    tris.add(Tri(a, b, c, part, s));
    if (part.isNotEmpty) {
      _sum[part] = (_sum[part] ?? const V3(0, 0, 0)) + a + b + c;
      _n[part] = (_n[part] ?? 0) + 3;
    }
  }

  void quad(V3 a, V3 b, V3 c, V3 d, String part, [Surface s = Surface.body]) {
    tri(a, b, c, part, s);
    tri(a, c, d, part, s);
  }

  /// Caixa alinhada aos eixos (sem a face de baixo).
  void box(V3 lo, V3 hi, String part, [Surface s = Surface.body, bool bottom = false]) {
    final x0 = lo.x, y0 = lo.y, z0 = lo.z, x1 = hi.x, y1 = hi.y, z1 = hi.z;
    quad(V3(x0, y1, z0), V3(x1, y1, z0), V3(x1, y1, z1), V3(x0, y1, z1), part, s); // topo
    quad(V3(x1, y0, z0), V3(x1, y1, z0), V3(x1, y1, z1), V3(x1, y0, z1), part, s); // frente
    quad(V3(x0, y0, z0), V3(x0, y1, z0), V3(x0, y1, z1), V3(x0, y0, z1), part, s); // trás
    quad(V3(x0, y0, z1), V3(x1, y0, z1), V3(x1, y1, z1), V3(x0, y1, z1), part, s); // lado +z
    quad(V3(x0, y0, z0), V3(x1, y0, z0), V3(x1, y1, z0), V3(x0, y1, z0), part, s); // lado -z
    if (bottom) {
      quad(V3(x0, y0, z0), V3(x1, y0, z0), V3(x1, y0, z1), V3(x0, y0, z1), part, s);
    }
  }

  /// Roda: pneu (cilindro em polígono) com aro, no lado [side] (+1/-1).
  void wheel(double cx, double r, double zOut, double width, int side) {
    const n = 18;
    final zi = zOut - width * side, zo = zOut;
    V3 p(int i, double z, double rr) {
      final a = 2 * math.pi * i / n;
      return V3(cx + rr * math.cos(a), r + rr * math.sin(a), z);
    }

    for (var i = 0; i < n; i++) {
      quad(p(i, zi, r), p(i + 1, zi, r), p(i + 1, zo, r), p(i, zo, r), '', Surface.tire);
      tri(V3(cx, r, zo), p(i, zo, r), p(i + 1, zo, r), '', Surface.tire);
      tri(V3(cx, r, zo + 0.005 * side), p(i, zo + 0.005 * side, r * 0.62),
          p(i + 1, zo + 0.005 * side, r * 0.62), '', Surface.rim);
    }
  }

  Map<String, V3> anchors() => {
        for (final e in _sum.entries) e.key: e.value * (1 / _n[e.key]!),
      };
}

/// Monta o carro da carroceria escolhida. x = frente, y = cima,
/// z positivo = lado esquerdo do motorista.
CarMesh buildCar(CarBody body) {
  final b = _Builder();
  // medidas por carroceria
  final (double front, double rear, double sill, double belt, double roof,
      double cabF, double cabR, double roofF, double roofR) = switch (body) {
    CarBody.sedan => (2.30, -2.30, 0.32, 0.92, 1.42, 0.95, -1.15, 0.30, -0.70),
    CarBody.hatch => (2.05, -1.95, 0.32, 0.94, 1.48, 0.85, -1.70, 0.20, -1.40),
    CarBody.suv => (2.25, -2.20, 0.45, 1.08, 1.72, 1.00, -1.95, 0.40, -1.80),
    CarBody.picape => (2.65, -2.65, 0.48, 1.12, 1.80, 1.05, -0.80, 0.45, -0.70),
  };
  const w = 0.92; // meia largura
  final bumperTop = sill + (belt - sill) * 0.48;
  const bump = 0.18;
  final doorMid = body == CarBody.picape ? 0.12 : (cabF + cabR) / 2 + 0.1;
  final doorRear = body == CarBody.picape ? cabR : cabR + 0.1;
  final fenderEnd = cabF + 0.15;
  final wheelF = front - 0.85, wheelR = rear + (body == CarBody.picape ? 0.95 : 0.8);
  final wr = body == CarBody.picape || body == CarBody.suv ? 0.40 : 0.34;

  // para-choques
  b.box(V3(front - bump, sill - 0.05, -w), V3(front, bumperTop, w), 'parachoque_d', Surface.body, true);
  b.box(V3(rear, sill - 0.05, -w), V3(rear + bump, bumperTop, w), 'parachoque_t', Surface.body, true);

  final xf = front - bump, xr = rear + bump;
  // frente: grade e faróis na face dianteira
  b.quad(V3(xf, bumperTop, -0.45), V3(xf, bumperTop, 0.45), V3(xf, belt, 0.45),
      V3(xf, belt, -0.45), 'grade', Surface.dark);
  b.quad(V3(xf, bumperTop, 0.45), V3(xf, bumperTop, w), V3(xf, belt, w),
      V3(xf, belt, 0.45), 'farol_e', Surface.light);
  b.quad(V3(xf, bumperTop, -w), V3(xf, bumperTop, -0.45), V3(xf, belt, -0.45),
      V3(xf, belt, -w), 'farol_d', Surface.light);
  // capô
  b.quad(V3(cabF, belt, -w), V3(xf, belt, -w), V3(xf, belt, w), V3(cabF, belt, w), 'capo');

  // laterais (lado +z = esquerdo)
  for (final side in [1, -1]) {
    final z = w * side;
    final s = side == 1 ? 'e' : 'd';
    void panel(double x0, double x1, String part) => b.quad(
        V3(x0, sill, z), V3(x1, sill, z), V3(x1, belt, z), V3(x0, belt, z), part);
    panel(fenderEnd, xf, 'paralama_d$s');
    panel(doorMid, fenderEnd, 'porta_d$s');
    panel(doorRear, doorMid, 'porta_t$s');
    if (body != CarBody.picape) panel(xr, doorRear, 'lateral_t$s');
    // retrovisor
    final mx = cabF - 0.12;
    b.box(V3(mx - 0.16, belt + 0.06, side == 1 ? w : -w - 0.16),
        V3(mx, belt + 0.18, side == 1 ? w + 0.16 : -w), 'retrovisor_$s', Surface.mirror);
    // soleira escura
    b.quad(V3(xr, sill - 0.05, z), V3(xf, sill - 0.05, z), V3(xf, sill, z),
        V3(xr, sill, z), '', Surface.dark);
  }

  // cabine (vidros contam como a peça de baixo; teto e para-brisa à parte)
  final wt = w - 0.2, wb = w - 0.04;
  V3 cb(double x, double side) => V3(x, belt, wb * side);
  V3 ct(double x, double side) => V3(x, roof, wt * side);
  b.quad(cb(cabF, -1), cb(cabF, 1), ct(roofF, 1), ct(roofF, -1), 'parabrisa', Surface.glass);
  b.quad(ct(roofR, -1), ct(roofF, -1), ct(roofF, 1), ct(roofR, 1), 'teto');
  final rearGlassPart = body == CarBody.sedan || body == CarBody.picape ? 'vigia' : 'tampa';
  if (body != CarBody.picape) {
    b.quad(cb(cabR, -1), cb(cabR, 1), ct(roofR, 1), ct(roofR, -1), rearGlassPart, Surface.glass);
  }
  for (final side in const [1.0, -1.0]) {
    final s = side == 1 ? 'e' : 'd';
    // vidros laterais divididos na altura da porta
    double topX(double x) {
      final t = ((x - cabR) / (cabF - cabR)).clamp(0.0, 1.0);
      return roofR + (roofF - roofR) * t;
    }

    final mid = doorMid.clamp(cabR, cabF);
    b.quad(cb(mid, side), cb(cabF, side), ct(roofF, side), ct(topX(mid), side),
        'porta_d$s', Surface.glass);
    b.quad(cb(cabR, side), cb(mid, side), ct(topX(mid), side), ct(roofR, side),
        'porta_t$s', Surface.glass);
  }

  // traseira
  if (body == CarBody.picape) {
    // caçamba: assoalho, paredes e tampa
    final floor = sill + 0.2;
    b.quad(V3(xr, floor, -w + 0.06), V3(cabR, floor, -w + 0.06), V3(cabR, floor, w - 0.06),
        V3(xr, floor, w - 0.06), 'cacamba', Surface.dark);
    for (final side in [1, -1]) {
      final s = side == 1 ? 'e' : 'd';
      final z = w * side;
      b.quad(V3(xr, sill, z), V3(cabR, sill, z), V3(cabR, belt, z), V3(xr, belt, z), 'lateral_t$s');
      final zi = (w - 0.06) * side;
      b.quad(V3(xr, floor, zi), V3(cabR, floor, zi), V3(cabR, belt, zi), V3(xr, belt, zi), 'cacamba', Surface.dark);
      b.quad(V3(xr, belt, zi), V3(cabR, belt, zi), V3(cabR, belt, z), V3(xr, belt, z), 'lateral_t$s');
    }
    b.quad(V3(cabR, floor, -w), V3(cabR, floor, w), V3(cabR, belt, w), V3(cabR, belt, -w), 'cacamba', Surface.dark);
    b.quad(V3(xr, bumperTop, -0.55), V3(xr, bumperTop, 0.55), V3(xr, belt, 0.55),
        V3(xr, belt, -0.55), 'tampa');
    // parede de trás da cabine e vigia
    b.quad(cb(cabR, -1), cb(cabR, 1), ct(roofR, 1), ct(roofR, -1), 'vigia', Surface.glass);
  } else {
    // tampa do porta-malas (sedã) ou tampa traseira (hatch/SUV)
    if (body == CarBody.sedan) {
      b.quad(V3(xr, belt, -w), V3(cabR, belt, -w), V3(cabR, belt, w), V3(xr, belt, w), 'tampa');
    } else {
      b.quad(V3(xr, belt, -w), V3(cabR, belt, -w), V3(cabR, belt, w), V3(xr, belt, w), 'tampa');
    }
  }
  b.quad(V3(xr, bumperTop, -0.55), V3(xr, bumperTop, 0.55), V3(xr, belt, 0.55),
      V3(xr, belt, -0.55), 'tampa');
  b.quad(V3(xr, bumperTop, 0.55), V3(xr, bumperTop, w), V3(xr, belt, w),
      V3(xr, belt, 0.55), 'lanterna_e', Surface.tail);
  b.quad(V3(xr, bumperTop, -w), V3(xr, bumperTop, -0.55), V3(xr, belt, -0.55),
      V3(xr, belt, -w), 'lanterna_d', Surface.tail);

  // fundo escuro e rodas
  b.quad(V3(xr, sill, -w), V3(xf, sill, -w), V3(xf, sill, w), V3(xr, sill, w), '', Surface.dark);
  for (final side in [1, -1]) {
    b.wheel(wheelF, wr, (w + 0.03) * side, 0.24, side);
    b.wheel(wheelR, wr, (w + 0.03) * side, 0.24, side);
  }

  // marcador um pouco para fora da peça
  final anchors = b.anchors().map((k, v) {
    final out = V3(v.x * 0.08, 0.12, v.z * 0.15);
    return MapEntry(k, v + out);
  });
  return CarMesh(body, b.tris, anchors);
}

// ------------------------------------------------------------------ câmera

class Camera3D {
  const Camera3D({this.yaw = -0.75, this.pitch = 0.32, this.zoom = 1.0});

  /// Giro em volta do carro (radianos) e inclinação para cima.
  final double yaw, pitch, zoom;

  Camera3D copyWith({double? yaw, double? pitch, double? zoom}) => Camera3D(
        yaw: yaw ?? this.yaw,
        pitch: (pitch ?? this.pitch).clamp(-0.05, 1.45),
        zoom: (zoom ?? this.zoom).clamp(0.6, 2.6),
      );

  static const front = Camera3D(yaw: math.pi / 2, pitch: 0.18);
  static const back = Camera3D(yaw: -math.pi / 2, pitch: 0.18);
  static const left = Camera3D(yaw: 0, pitch: 0.12);
  static const right = Camera3D(yaw: math.pi, pitch: 0.12);
  static const top = Camera3D(yaw: 0, pitch: 1.45);
  static const frontLeft = Camera3D(yaw: 0.75, pitch: 0.32);
  static const rearRight = Camera3D(yaw: math.pi + 0.75, pitch: 0.32);

  /// Ponto do mundo → coordenadas da câmera (x direita, y cima, z para o olho).
  V3 view(V3 p) {
    final cy = math.cos(yaw), sy = math.sin(yaw);
    // gira em y: lado esquerdo (+z) aparece de frente com yaw = 0
    final x1 = p.x * cy - p.z * sy;
    final z1 = p.x * sy + p.z * cy;
    final y0 = p.y - 0.75;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final y2 = y0 * cp - z1 * sp;
    final z2 = y0 * sp + z1 * cp;
    return V3(x1, y2, z2);
  }
}

class ProjTri {
  ProjTri(this.a, this.b, this.c, this.depth, this.tri, this.shade);
  final Offset a, b, c;
  final double depth;
  final Tri tri;
  final double shade;

  bool contains(Offset p) {
    double s(Offset p1, Offset p2, Offset p3) =>
        (p1.dx - p3.dx) * (p2.dy - p3.dy) - (p2.dx - p3.dx) * (p1.dy - p3.dy);
    final d1 = s(p, a, b), d2 = s(p, b, c), d3 = s(p, c, a);
    final neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
    return !(neg && pos);
  }
}

const _dist = 9.0;

Offset _project(V3 v, Size size, double zoom) {
  final f = size.shortestSide * 1.55 * zoom;
  final k = f / (_dist - v.z);
  return Offset(size.width / 2 + v.x * k, size.height * 0.56 - v.y * k);
}

Offset projectPoint(V3 p, Camera3D cam, Size size) => _project(cam.view(p), size, cam.zoom);

/// Projeta e ordena do mais longe para o mais perto (pintor).
List<ProjTri> projectMesh(CarMesh mesh, Camera3D cam, Size size) {
  const light = V3(0.35, 0.85, 0.4);
  final l = light.unit;
  final out = <ProjTri>[];
  for (final t in mesh.tris) {
    final a = cam.view(t.a), b = cam.view(t.b), c = cam.view(t.c);
    final n = (t.b - t.a).cross(t.c - t.a).unit;
    final shade = 0.55 + 0.45 * n.dot(l).abs();
    out.add(ProjTri(_project(a, size, cam.zoom), _project(b, size, cam.zoom),
        _project(c, size, cam.zoom), (a.z + b.z + c.z) / 3, t, shade));
  }
  out.sort((x, y) => x.depth.compareTo(y.depth));
  return out;
}

/// Peça no ponto da tela (a mais próxima), ou null.
String? hitPart(List<ProjTri> projected, Offset p) {
  for (var i = projected.length - 1; i >= 0; i--) {
    final t = projected[i];
    if (t.contains(p)) return t.tri.part.isEmpty ? null : t.tri.part;
  }
  return null;
}

// ------------------------------------------------------------------ pintura

const severityColors = {
  1: Color(0xFFF2C230), // leve
  2: Color(0xFFF07F22), // moderada
  3: Color(0xFFE0393E), // grave
};

const _hoverColor = Color(0xFF8CC8FF);
const _selectColor = Color(0xFF3D8BFF);

Color _base(Surface s, Color body) => switch (s) {
      Surface.body => body,
      Surface.glass => const Color(0xFF1F2B38),
      Surface.tire => const Color(0xFF141619),
      Surface.rim => const Color(0xFF9AA3AD),
      Surface.light => const Color(0xFFDDE8F2),
      Surface.tail => const Color(0xFFB3262B),
      Surface.dark => const Color(0xFF2A2D33),
      Surface.mirror => body,
    };

class Car3DPainter extends CustomPainter {
  Car3DPainter({
    required this.mesh,
    required this.camera,
    this.bodyColor = const Color(0xFFE9EAEE),
    this.partColors = const {},
    this.pins = const {},
    this.hover,
    this.selected,
    this.floor = true,
  });

  final CarMesh mesh;
  final Camera3D camera;
  final Color bodyColor;

  /// Peças com avaria → cor da gravidade.
  final Map<String, Color> partColors;

  /// Peça → número do marcador.
  final Map<String, int> pins;
  final String? hover, selected;
  final bool floor;

  @override
  void paint(Canvas canvas, Size size) {
    if (floor) _floor(canvas, size);
    final proj = projectMesh(mesh, camera, size);
    final positions = Float32List(proj.length * 6);
    final colors = Int32List(proj.length * 3);
    var i = 0, k = 0;
    for (final t in proj) {
      final part = t.tri.part;
      var c = _base(t.tri.surface, bodyColor);
      if (part.isNotEmpty) {
        if (part == selected) {
          c = Color.lerp(c, _selectColor, t.tri.surface == Surface.glass ? 0.55 : 0.75)!;
        } else if (part == hover) {
          c = Color.lerp(c, _hoverColor, t.tri.surface == Surface.glass ? 0.45 : 0.7)!;
        } else if (partColors[part] != null) {
          c = Color.lerp(c, partColors[part]!, t.tri.surface == Surface.glass ? 0.45 : 0.85)!;
        }
      }
      final shaded = Color.fromARGB(
        255,
        (c.r * 255 * t.shade).round().clamp(0, 255),
        (c.g * 255 * t.shade).round().clamp(0, 255),
        (c.b * 255 * t.shade).round().clamp(0, 255),
      );
      for (final p in [t.a, t.b, t.c]) {
        positions[i++] = p.dx;
        positions[i++] = p.dy;
        colors[k++] = shaded.toARGB32();
      }
    }
    final verts = ui.Vertices.raw(ui.VertexMode.triangles, positions, colors: colors);
    canvas.drawVertices(verts, BlendMode.dst, Paint());
    _pins(canvas, size);
  }

  void _floor(Canvas canvas, Size size) {
    Path ring(double r) {
      final p = Path();
      for (var i = 0; i <= 64; i++) {
        final a = 2 * math.pi * i / 64;
        final o = projectPoint(V3(r * math.cos(a), 0, r * math.sin(a)), camera, size);
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      return p..close();
    }

    canvas.drawPath(ring(3.3), Paint()..color = const Color(0xFF101A2B));
    canvas.drawPath(
        ring(3.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF2EC6F5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3));
    canvas.drawPath(
        ring(2.7),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x553D8BFF));
  }

  void _pins(Canvas canvas, Size size) {
    for (final e in pins.entries) {
      final at = mesh.anchors[e.key];
      if (at == null) continue;
      final o = projectPoint(at, camera, size);
      final c = partColors[e.key] ?? severityColors[2]!;
      canvas.drawCircle(o, 12, Paint()..color = Colors.black.withValues(alpha: 0.35));
      canvas.drawCircle(o, 10.5, Paint()..color = c);
      canvas.drawCircle(
          o,
          10.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
      final tp = TextPainter(
        text: TextSpan(
            text: '${e.value}',
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant Car3DPainter old) =>
      old.camera != camera ||
      old.mesh != mesh ||
      old.hover != hover ||
      old.selected != selected ||
      old.partColors != partColors ||
      old.pins != pins ||
      old.bodyColor != bodyColor;
}

/// Imagem PNG do carro numa vista (para o PDF).
Future<Uint8List> renderCarPng(CarMesh mesh, Camera3D cam,
    {Map<String, Color> partColors = const {},
    Map<String, int> pins = const {},
    int width = 640,
    int height = 420,
    Color background = const Color(0xFF0B1322)}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final size = Size(width.toDouble(), height.toDouble());
  canvas.drawRect(Offset.zero & size, Paint()..color = background);
  Car3DPainter(mesh: mesh, camera: cam, partColors: partColors, pins: pins)
      .paint(canvas, size);
  final img = await rec.endRecording().toImage(width, height);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// ------------------------------------------------------------------ widget

/// Visualizador interativo: arrastar gira, rolar/pinça aproxima, clique
/// seleciona a peça.
class Car3DView extends StatefulWidget {
  const Car3DView({
    super.key,
    required this.body,
    this.partColors = const {},
    this.pins = const {},
    this.selected,
    this.onPart,
    this.bodyColor = const Color(0xFFE9EAEE),
  });

  final CarBody body;
  final Map<String, Color> partColors;
  final Map<String, int> pins;
  final String? selected;
  final ValueChanged<String>? onPart;
  final Color bodyColor;

  @override
  State<Car3DView> createState() => Car3DViewState();
}

class Car3DViewState extends State<Car3DView> {
  late CarMesh _mesh = buildCar(widget.body);
  Camera3D cam = const Camera3D();
  Camera3D _start = const Camera3D();
  String? _hover;
  Offset? _hoverAt;
  Size _size = Size.zero;

  CarMesh get mesh => _mesh;

  @override
  void didUpdateWidget(covariant Car3DView old) {
    super.didUpdateWidget(old);
    if (old.body != widget.body) _mesh = buildCar(widget.body);
  }

  void setView(Camera3D c) => setState(() => cam = c.copyWith(zoom: cam.zoom));

  String? partAt(Offset p) => hitPart(projectMesh(_mesh, cam, _size), p);

  /// Ponto da tela onde a peça aparece (usado nos testes).
  Offset? screenPointOf(String part) {
    final proj = projectMesh(_mesh, cam, _size);
    for (var i = proj.length - 1; i >= 0; i--) {
      final t = proj[i];
      if (t.tri.part != part) continue;
      final c = Offset((t.a.dx + t.b.dx + t.c.dx) / 3, (t.a.dy + t.b.dy + t.c.dy) / 3);
      if (hitPart(proj, c) == part) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final names = {for (final p in partsFor(widget.body)) p.id: p.label};
    return LayoutBuilder(builder: (context, box) {
      _size = Size(box.maxWidth, box.maxHeight);
      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            setState(() => cam = cam.copyWith(zoom: cam.zoom * (e.scrollDelta.dy > 0 ? 0.92 : 1.08)));
          }
        },
        child: MouseRegion(
          cursor: _hover == null ? SystemMouseCursors.grab : SystemMouseCursors.click,
          onHover: (e) {
            final h = partAt(e.localPosition);
            if (h != _hover || h != null) {
              setState(() {
                _hover = h;
                _hoverAt = e.localPosition;
              });
            }
          },
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final p = partAt(d.localPosition);
              if (p != null) widget.onPart?.call(p);
            },
            onScaleStart: (d) {
              _start = cam;
              _from = d.focalPoint;
            },
            onScaleUpdate: (d) => setState(() {
              final delta = d.pointerCount > 1 ? Offset.zero : d.focalPoint - _from;
              cam = _start.copyWith(
                yaw: _start.yaw + delta.dx * 0.01,
                pitch: _start.pitch + delta.dy * 0.008,
                zoom: _start.zoom * d.scale,
              );
            }),
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: Car3DPainter(
                    mesh: _mesh,
                    camera: cam,
                    partColors: widget.partColors,
                    pins: widget.pins,
                    hover: _hover,
                    selected: widget.selected,
                    bodyColor: widget.bodyColor,
                  ),
                ),
              ),
              if (_hover != null && _hoverAt != null)
                Positioned(
                  left: (_hoverAt!.dx + 14).clamp(0, math.max(0, _size.width - 190)),
                  top: (_hoverAt!.dy - 46).clamp(0, math.max(0, _size.height - 50)),
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xEE0E1726),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x553D8BFF)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(names[_hover] ?? _hover!,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                          const Text('Clique para inspecionar',
                              style: TextStyle(color: Color(0xFF9FB3C8), fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
    });
  }

  Offset _from = Offset.zero;
}
