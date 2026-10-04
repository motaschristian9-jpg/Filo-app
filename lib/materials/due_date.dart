import 'package:flutter/material.dart';

String formatDueDate(BuildContext context, DateTime date) {
  final local = date.toLocal();
  return '${MaterialLocalizations.of(context).formatMediumDate(local)} · ${TimeOfDay.fromDateTime(local).format(context)}';
}
