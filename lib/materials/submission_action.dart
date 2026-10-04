import 'package:flutter/foundation.dart';

class SubmissionAction {
  const SubmissionAction(this.label, this.onPressed);
  final String label;
  final VoidCallback? onPressed;
}

class SubmissionActionController extends ValueNotifier<SubmissionAction?> {
  SubmissionActionController() : super(null);
  bool _disposed = false;
  void show(SubmissionAction? next) {
    if (_disposed || (value?.label == next?.label &&
        (value?.onPressed == null) == (next?.onPressed == null))) return;
    value = next;
  }
  @override
  void dispose() { _disposed = true; super.dispose(); }
}
