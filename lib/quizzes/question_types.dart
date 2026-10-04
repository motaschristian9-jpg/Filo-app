import 'package:flutter/material.dart';

const questionTypes = {
  'multiple_choice': 'Multiple choice', 'true_false': 'True or false',
  'identification': 'Identification', 'enumeration': 'Enumeration', 'essay': 'Essay',
};

class QuestionDraft {
  QuestionDraft([Map<String, dynamic>? data]) {
    type = data?['type'] as String? ?? 'multiple_choice';
    prompt.text = data?['prompt'] as String? ?? '';
    points.text = '${data?['points'] ?? 1}';
    final values = data?['options'] as List? ?? [];
    for (var i = 0; i < 4; i++) { options[i].text = i < values.length ? values[i] as String : ''; }
    answer = data?['answer'] is int ? data!['answer'] as int : 0;
    accepted.text = (data?['acceptedAnswers'] as List? ?? []).join('\n');
    expected.text = (data?['expectedAnswers'] as List? ?? []).join('\n');
    ordered = data?['ordered'] == true;
    rubric.text = data?['rubric'] as String? ?? '';
  }
  late String type;
  final prompt = TextEditingController(), points = TextEditingController();
  final options = List.generate(4, (_) => TextEditingController());
  final accepted = TextEditingController(), expected = TextEditingController(), rubric = TextEditingController();
  int answer = 0;
  bool ordered = false;
  List<String> lines(String value) => value.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  Map<String, dynamic> toMap() => {
    'type': type, 'prompt': prompt.text.trim(), 'points': int.parse(points.text),
    if (type == 'multiple_choice' || type == 'true_false') ...{
      'options': type == 'true_false' ? ['True', 'False'] : options.map((c) => c.text.trim()).toList(),
      'answer': answer,
    },
    if (type == 'identification') 'acceptedAnswers': lines(accepted.text),
    if (type == 'enumeration') ...{'expectedAnswers': lines(expected.text), 'ordered': ordered},
    if (type == 'essay') 'rubric': rubric.text.trim(),
  };
  void dispose() {
    for (final c in [prompt, points, accepted, expected, rubric, ...options]) { c.dispose(); }
  }
}
