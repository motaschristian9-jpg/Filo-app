import 'package:flutter/material.dart';

const ink = Color(0xFF183D38);
const teal = Color(0xFF246B58);
const cream = Color(0xFFFAFBF6);
const mint = Color(0xFFE7EFE3);
const lime = Color(0xFFE2F3A6);
const muted = Color(0xFF66756E);
const line = Color(0xFFDCE3D8);

ThemeData filoTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Nunito',
  scaffoldBackgroundColor: cream,
  colorScheme: ColorScheme.fromSeed(
    seedColor: teal,
    primary: teal,
    surface: cream,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 38,
      height: 1.12,
      fontWeight: FontWeight.w900,
      color: ink,
      letterSpacing: -1.3,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      height: 1.18,
      fontWeight: FontWeight.w900,
      color: ink,
      letterSpacing: -0.8,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.55, color: muted),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: muted),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(17),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: teal, width: 2),
    ),
  ),
);

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Transform.rotate(
        angle: -0.12,
        child: Container(
          width: 32,
          height: 34,
          decoration: BoxDecoration(
            color: teal,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.auto_stories_rounded, color: lime, size: 21),
        ),
      ),
      const SizedBox(width: 9),
      const Text(
        'filo',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
          color: ink,
        ),
      ),
    ],
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.icon = Icons.arrow_forward_rounded,
    this.google = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy, google;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      boxShadow: onPressed == null
          ? []
          : [
              BoxShadow(
                color: google ? line : const Color(0xFF174838),
                offset: const Offset(0, 4),
              ),
            ],
    ),
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: google ? Colors.white : teal,
        foregroundColor: google ? ink : Colors.white,
        disabledBackgroundColor: const Color(0xFFE2E7DE),
        disabledForegroundColor: muted,
        minimumSize: const Size(0, 58),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: google ? const BorderSide(color: line) : BorderSide.none,
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (google) ...[const GoogleMark(), const SizedBox(width: 14)],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!google) ...[
                  const SizedBox(width: 12),
                  Icon(icon, size: 20),
                ],
              ],
            ),
    ),
  );
}

class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(22, 22), painter: _GooglePainter());
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(2.5, 2.5, 17, 17);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    for (final segment in [
      (0.0, 1.05, const Color(0xFF4285F4)),
      (1.05, 1.55, const Color(0xFF34A853)),
      (2.60, 1.1, const Color(0xFFFBBC05)),
      (3.70, 1.9, const Color(0xFFEA4335)),
    ]) {
      canvas.drawArc(
        rect,
        segment.$1,
        segment.$2,
        false,
        paint..color = segment.$3,
      );
    }
    canvas.drawLine(
      const Offset(11, 11),
      const Offset(21, 11),
      paint..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 2,
      color: teal,
    ),
  );
}

class SetupProgress extends StatelessWidget {
  const SetupProgress(this.step, {super.key});
  final int step;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      ...List.generate(
        2,
        (i) => Expanded(
          child: Container(
            height: 5,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: i < step ? teal : line,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Text(
        'Step $step of 2',
        style: const TextStyle(
          fontSize: 12,
          color: muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEDE4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF893A21))),
    ),
  );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.avatar,
    this.photoUrl,
    this.size = 70,
  });
  final int avatar;
  final String? photoUrl;
  final double size;
  @override
  Widget build(BuildContext context) {
    const colors = [
      lime,
      Color(0xFFF4D2B8),
      Color(0xFFDCD8F3),
      Color(0xFFCEE8E7),
    ];
    const icons = [
      Icons.spa_rounded,
      Icons.wb_sunny_rounded,
      Icons.auto_awesome_rounded,
      Icons.local_florist_rounded,
    ];
    final index = avatar < 0 ? 0 : avatar % 4;
    final fallback = Icon(icons[index], color: ink, size: size * .48);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors[index],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: avatar == -1 && photoUrl != null
          ? Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => fallback,
            )
          : fallback,
    );
  }
}
