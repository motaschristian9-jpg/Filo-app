import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'design.dart';
import 'rive_mascot.dart';

/// Filo's original folded-file mascot. All artwork is resolution-independent.
enum MascotExpression { friendly, excited, curious, proud, wink }

class LearningArt extends StatelessWidget {
  const LearningArt({super.key, this.scene = 0, this.compact = false,
    this.expression, this.useRive = true});
  final int scene;
  final bool compact, useRive;
  final MascotExpression? expression;
  @override
  Widget build(BuildContext context) {
    final pose = expression ?? const [MascotExpression.friendly,
      MascotExpression.excited, MascotExpression.curious][scene % 3];
    final fallback = _PaintedLearningArt(scene: scene, compact: compact, expression: pose);
    if (!useRive || MediaQuery.disableAnimationsOf(context)) return fallback;
    return RiveMascot(expression: pose.index, compact: compact, fallback: fallback);
  }
}

void showMascotSuccess(BuildContext context, String message,
    {MascotExpression expression = MascotExpression.proud}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    duration: const Duration(seconds: 3),
    content: Row(children: [
      SizedBox(width: 56, height: 56,
        child: LearningArt(compact: true, expression: expression)),
      const SizedBox(width: 12),
      Expanded(child: Text(message)),
    ]),
  ));
}

class _PaintedLearningArt extends StatefulWidget {
  const _PaintedLearningArt({this.scene = 0, this.compact = false, this.expression});
  final int scene;
  final bool compact;
  final MascotExpression? expression;
  @override
  State<_PaintedLearningArt> createState() => _LearningArtState();
}

class _LearningArtState extends State<_PaintedLearningArt> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this, duration: const Duration(seconds: 4),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      _motion.value = 0;
    } else if (!_motion.isAnimating) {
      // Preserve the phase when inherited layout/theme data changes.
      _motion.repeat();
    }
  }
  @override
  void dispose() { _motion.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final expression = widget.expression ?? const [
      MascotExpression.friendly, MascotExpression.excited, MascotExpression.curious,
    ][widget.scene % 3];
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(child: SizedBox(
      width: double.infinity,
      height: widget.compact ? 180 : 350,
      child: FittedBox(fit: BoxFit.contain, alignment: Alignment.center, child: SizedBox(
        width: 380, height: 350,
        child: AnimatedBuilder(animation: _motion, builder: (context, _) {
          final wave = reduce ? 0.0 : math.sin(_motion.value * math.pi * 2);
          return Stack(children: [
            Positioned(left: 48, top: 32, child: Container(
              width: 284, height: 284,
              decoration: const BoxDecoration(color: Color(0xFFDCE9D6), shape: BoxShape.circle),
            )),
            Positioned(left: 66, top: 50, child: Container(
              width: 248, height: 248,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFEDF4E7), width: 2)),
            )),
            Positioned(left: 133 + wave * 2, top: 282, child: Container(
              width: 114 - wave * 4, height: 15,
              decoration: BoxDecoration(color: ink.withValues(alpha: .08), borderRadius: BorderRadius.circular(100)),
            )),
            Positioned(left: 80, top: 43 + wave * 3, child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: expression == MascotExpression.curious ? -.08 : 0),
              duration: Duration(milliseconds: reduce ? 0 : 280),
              curve: Curves.easeInOutCubic,
              builder: (context, tilt, child) => Transform.rotate(
                angle: tilt + wave * .015,
                child: child,
              ),
              child: RepaintBoundary(child: AnimatedSwitcher(
                duration: Duration(milliseconds: reduce ? 0 : 280),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                child: CustomPaint(
                  key: ValueKey(expression),
                  size: const Size(220, 253),
                  painter: _MascotPainter(expression, wave),
                ),
              )),
            )),
          ]);
        }),
      )),
    ));
  }
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter(this.expression, this.wave);
  final MascotExpression expression;
  final double wave;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 230);
    final fill = Paint();
    final stroke = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    void line(Offset from, Offset to, Color color, double width) {
      canvas.drawLine(from, to, stroke..color = color..strokeWidth = width);
    }
    void curve(Path path, Color color, double width) {
      canvas.drawPath(path, stroke..color = color..strokeWidth = width);
    }
    final excited = expression == MascotExpression.excited;
    final curious = expression == MascotExpression.curious;
    final proud = expression == MascotExpression.proud;
    final wink = expression == MascotExpression.wink;

    // Little boots and flexible arms keep the file silhouette readable.
    line(const Offset(72, 177), const Offset(68, 201), teal, 11);
    line(const Offset(130, 177), const Offset(136, 201), teal, 11);
    line(const Offset(59, 204), const Offset(74, 204), teal, 10);
    line(const Offset(131, 204), const Offset(146, 204), teal, 10);
    curve(Path()..moveTo(46, 110)..quadraticBezierTo(23, excited ? 90 : 125, 19, excited ? 68 - wave * 5 : 139), teal, 8);
    if (curious) {
      curve(Path()..moveTo(153, 112)..quadraticBezierTo(178, 130, 135, 132), teal, 8);
    } else {
      curve(Path()..moveTo(153, 111)..quadraticBezierTo(179, 102, 178,  (excited ? 62 : wink ? 72 : 82) + wave * 7), teal, 8);
    }

    // Offset back page, rounded main page, and a folded corner.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(46, 27, 119, 160), const Radius.circular(26)), fill..color = const Color(0xFFB9CE7C));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(36, 32, 122, 154), const Radius.circular(25)), fill..color = lime);
    curve(Path()..moveTo(48, 57)..quadraticBezierTo(49, 43, 64, 43)..lineTo(119, 43), const Color(0xFFF2F9D4), 4);
    canvas.drawPath(Path()..moveTo(126, 32)..lineTo(158, 64)..lineTo(138, 64)..quadraticBezierTo(126, 64, 126, 52)..close(), fill..color = const Color(0xFFBFD487));

    // Face: friendly, excited, curious, proud, or a playful wink.
    void eye(double x, {bool closed = false, double offset = 0}) {
      if (closed) {
        curve(Path()..moveTo(x - 5, 96 + offset)..quadraticBezierTo(x, 88 + offset, x + 5, 96 + offset), ink, 4);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 4, 87 + offset, 8, 13), const Radius.circular(4)), fill..color = ink);
        canvas.drawCircle(Offset(x + 1, 90 + offset), 1.4, fill..color = Colors.white);
      }
    }
    eye(72, closed: excited || proud, offset: curious ? 2 : 0);
    eye(122, closed: excited || proud || wink, offset: curious ? -2 : 0);
    canvas.drawOval(const Rect.fromLTWH(55, 106, 16, 8), fill..color = const Color(0xFFE8BCA4));
    canvas.drawOval(const Rect.fromLTWH(126, 106, 16, 8), fill);
    if (curious) {
      curve(Path()..moveTo(114, 78)..quadraticBezierTo(120, 73, 127, 77), ink, 3);
      canvas.drawOval(const Rect.fromLTWH(94, 109, 10, 13), fill..color = ink);
    } else if (excited) {
      final mouth = Path()..moveTo(85, 109)..lineTo(111, 109)..quadraticBezierTo(110, 132, 98, 131)..quadraticBezierTo(86, 131, 85, 109)..close();
      canvas.drawPath(mouth, fill..color = ink);
      canvas.save();
      canvas.clipPath(mouth);
      canvas.drawOval(const Rect.fromLTWH(88, 120, 24, 16), fill..color = const Color(0xFFF1B59C));
      canvas.restore();
    } else {
      curve(Path()..moveTo(86, 111)..quadraticBezierTo(98, proud ? 130 : 124, 110, 111), ink, 3.5);
    }

    // Two document lines and a tiny bookmark are the mascot's signatures.
    line(const Offset(66, 150), const Offset(122, 150), const Color(0xFFBED18A), 5);
    line(const Offset(66, 162), const Offset(105, 162), const Color(0xFFBED18A), 5);
    canvas.drawPath(Path()..moveTo(131, 149)..lineTo(143, 149)..lineTo(143, 176)..lineTo(137, 171)..lineTo(131, 176)..close(), fill..color = teal);
    if (excited || proud) {
      for (final point in [const Offset(28, 42), const Offset(179, 32)]) {
        line(point.translate(-4, 0), point.translate(4, 0), teal, 2.5);
        line(point.translate(0, -5), point.translate(0, 5), teal, 2.5);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MascotPainter oldDelegate) => oldDelegate.expression != expression || oldDelegate.wave != wave;
}

class FiloFrame extends StatelessWidget {
  const FiloFrame({
    super.key,
    required this.child,
    this.art,
    this.action,
    this.back,
    this.footer,
  });
  final Widget child;
  final Widget? art, action, footer;
  final VoidCallback? back;

  Widget _content(bool wide) {
    final scroll = SingleChildScrollView(
      child: Padding(
        padding: wide
            ? const EdgeInsets.symmetric(vertical: 20)
            : const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: child,
      ),
    );
    if (footer == null) return wide ? Center(child: scroll) : scroll;
    return Column(children: [
      Expanded(child: wide ? Center(child: scroll) : scroll),
      Padding(
        padding: wide
            ? const EdgeInsets.only(top: 16, bottom: 6)
            : const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: footer!,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        return Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(wide ? 42 : 24, 20, wide ? 42 : 16, 16),
              child: Row(children: [
                if (back != null) ...[
                  IconButton(onPressed: back, tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded)),
                  const SizedBox(width: 4),
                ] else const Brand(),
                const Spacer(),
                ?action,
              ]),
            ),
            Expanded(child: wide
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(42, 18, 42, 42),
                    child: Row(children: [
                      Expanded(child: Container(
                        decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(36)),
                        child: Center(child: art ?? const LearningArt()),
                      )),
                      const SizedBox(width: 64),
                      Expanded(child: _content(true)),
                    ]),
                  )
                : _content(false)),
          ]),
        ));
      }),
    ),
  );
}
