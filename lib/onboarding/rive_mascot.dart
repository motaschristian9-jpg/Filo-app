import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:rive/rive.dart' as rive;

// Share the decoded asset while any mascot is mounted. Each widget owns its
// artboard/controller and data model; the last widget releases the shared file.
class _MascotAsset {
  static rive.File? _file;
  static Future<rive.File?>? _loading;
  static int _users = 0;
  static Future<rive.File?> acquire() {
    _users++;
    if (_file != null) return Future.value(_file);
    return _loading ??= _load();
  }
  static Future<rive.File?> _load() async {
    try {
      final file = await rive.File.asset('assets/animations/filo_mascot.riv',
        riveFactory: rive.Factory.flutter);
      if (_users == 0) { file?.dispose(); return null; }
      return _file = file;
    } catch (_) {
      return null;
    } finally { _loading = null; }
  }
  static void release() {
    _users--;
    if (_users == 0) { _file?.dispose(); _file = null; }
  }
}

class RiveMascot extends StatefulWidget {
  const RiveMascot({super.key, required this.expression, required this.compact,
    required this.fallback});
  final int expression;
  final bool compact;
  final Widget fallback;
  @override
  State<RiveMascot> createState() => _RiveMascotState();
}

class _RiveMascotState extends State<RiveMascot> with WidgetsBindingObserver {
  rive.RiveWidgetController? _controller;
  rive.ViewModelInstance? _data;
  rive.ViewModelInstanceNumber? _expression;
  rive.ViewModelInstanceBoolean? _motion;
  rive.ViewModelInstanceNumber? _leftEye, _rightEye;
  final _random = math.Random();
  Timer? _eyeTimer, _eyeReset;
  bool _foreground = true, _visible = true;
  Timer? _reactionTimer;
  int? _tapPose;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _load();
  }

  Future<void> _load() async {
    final file = await _MascotAsset.acquire();
    if (!mounted || file == null) return;
    rive.RiveWidgetController? controller;
    rive.ViewModelInstance? data;
    try {
      controller = rive.RiveWidgetController(file,
        artboardSelector: rive.ArtboardSelector.byName('FiloMascot'),
        stateMachineSelector: rive.StateMachineSelector.byName('Mascot'));
      data = controller.dataBind(rive.DataBind.auto());
      final expression = data.number('expression');
      final motion = data.boolean('motionEnabled');
      if (expression == null || motion == null) throw StateError('Missing mascot data');
      _controller = controller;
      _data = data;
      _expression = expression;
      _motion = motion;
      _leftEye = data.number('leftEyeOpen');
      _rightEye = data.number('rightEyeOpen');
      _update();
      setState(() {});
    } catch (_) {
      controller?.dispose(); data?.dispose();
      _controller = null; _data = null; _expression = null; _motion = null;
      // The existing painter remains visible; animation must not block the UI.
    }
  }

  void _update() {
    _expression?.value = (_tapPose ?? widget.expression).toDouble();
    _motion?.value = _foreground && _visible;
    if (_controller != null) _controller!.active = _foreground && _visible;
    if (_foreground && _visible && _controller != null) {
      _scheduleEyes();
    } else {
      _eyeTimer?.cancel(); _eyeTimer = null;
      _eyeReset?.cancel(); _eyeReset = null;
      _leftEye?.value = 1; _rightEye?.value = 1;
    }
  }

  void _scheduleEyes() {
    if (_eyeTimer != null || _eyeReset != null || _leftEye == null || _rightEye == null) return;
    _eyeTimer = Timer(Duration(milliseconds: 2800 + _random.nextInt(4200)), () {
      _eyeTimer = null;
      if (!mounted || !_foreground || !_visible) return;
      final wink = _random.nextInt(4) == 0;
      final closeLeft = !wink || _random.nextBool();
      _leftEye?.value = closeLeft ? .08 : 1;
      _rightEye?.value = !wink || !closeLeft ? .08 : 1;
      _eyeReset = Timer(Duration(milliseconds: wink ? 220 : 130), () {
        _eyeReset = null;
        if (!mounted) return;
        _leftEye?.value = 1; _rightEye?.value = 1;
        _scheduleEyes();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.of(context) && (ModalRoute.isCurrentOf(context) ?? true);
    _update();
  }
  @override
  void didUpdateWidget(covariant RiveMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expression != widget.expression) {
      _reactionTimer?.cancel(); _tapPose = null; _update();
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _update();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reactionTimer?.cancel();
    _eyeTimer?.cancel(); _eyeReset?.cancel();
    _controller?.dispose();
    _data?.dispose();
    _MascotAsset.release();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.fallback;
    return ExcludeSemantics(child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!_foreground || !_visible) return;
        _reactionTimer?.cancel();
        _tapPose = widget.expression == 4 ? 1 : 4;
        _update();
        _reactionTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          _tapPose = null; _update();
        });
      }, child: IgnorePointer(child: SizedBox(
      width: double.infinity, height: widget.compact ? 180 : 350,
      child: rive.RiveWidget(controller: controller, fit: rive.Fit.contain),
    ))));
  }
}
