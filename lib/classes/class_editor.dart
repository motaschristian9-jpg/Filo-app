import 'package:flutter/material.dart';
import '../onboarding/design.dart';
import 'class_repository.dart';

const classColors = [mint, Color(0xFFE4DFF5), Color(0xFFF6DDC8), Color(0xFFD7ECEB)];
const classIcons = [Icons.auto_stories_rounded, Icons.lightbulb_outline_rounded,
  Icons.wb_sunny_outlined, Icons.explore_outlined];
Color classColor(int index) => classColors[index.clamp(0, classColors.length - 1).toInt()];
IconData classIcon(int index) => classIcons[index.clamp(0, classIcons.length - 1).toInt()];

class ClassEditor extends StatefulWidget {
  const ClassEditor({super.key, required this.repository, this.existing});
  final ClassRepository repository;
  final FiloClass? existing;
  @override
  State<ClassEditor> createState() => _ClassEditorState();
}
class _ClassEditorState extends State<ClassEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _subject, _section, _description;
  late final String _id;
  late int _color;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _id = existing?.id ?? widget.repository.newClassId();
    _name = TextEditingController(text: existing?.name ?? '');
    _subject = TextEditingController(text: existing?.subject ?? '');
    _section = TextEditingController(text: existing?.section ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _color = (existing?.color ?? 0).clamp(0, classColors.length - 1).toInt();
  }
  @override
  void dispose() {
    _name.dispose(); _subject.dispose(); _section.dispose(); _description.dispose();
    super.dispose();
  }
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _saving = true; _error = null; });
    final draft = ClassDraft(name: _name.text, subject: _subject.text,
      section: _section.text, description: _description.text, color: _color);
    try {
      if (widget.existing == null) { await widget.repository.create(_id, draft); }
      else { await widget.repository.update(_id, draft); }
      if (mounted) Navigator.pop(context, _id);
    } catch (error) {
      if (mounted) setState(() { _saving = false; _error = classError(error); });
    }
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New class' : 'Edit class'),
        leading: IconButton(onPressed: _saving ? null : () => Navigator.pop(context),
          tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded))),
      body: SafeArea(top: false, child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(children: [
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
            child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(duration: Duration(milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 200),
                height: 120, width: double.infinity,
                decoration: BoxDecoration(color: classColor(_color), borderRadius: BorderRadius.circular(24)),
                child: Icon(classIcon(_color), size: 48, color: teal)),
              const SizedBox(height: 18),
              Wrap(spacing: 12, children: List.generate(classColors.length, (index) => Semantics(
                label: ['Sage', 'Lilac', 'Peach', 'Aqua'][index], selected: _color == index, button: true,
                child: InkWell(borderRadius: BorderRadius.circular(26),
                  onTap: _saving ? null : () => setState(() => _color = index),
                  child: Container(width: 48, height: 48, decoration: BoxDecoration(
                    color: classColors[index], shape: BoxShape.circle,
                    border: Border.all(color: _color == index ? teal : Colors.transparent, width: 2)),
                    child: _color == index ? const Icon(Icons.check_rounded, color: teal) : null)),
              ))),
              const SizedBox(height: 28),
              _label('Class name'),
              TextFormField(controller: _name, enabled: !_saving, maxLength: 80,
                textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'e.g. Creative Science', counterText: ''),
                validator: (text) => text == null || text.trim().isEmpty ? 'Give your class a name.' : null),
              const SizedBox(height: 20), _label('Subject', optional: true),
              TextFormField(controller: _subject, enabled: !_saving, maxLength: 80,
                textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'e.g. Science', counterText: '')),
              const SizedBox(height: 20), _label('Section', optional: true),
              TextFormField(controller: _section, enabled: !_saving, maxLength: 60,
                textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'e.g. Grade 10 - A', counterText: '')),
              const SizedBox(height: 20), _label('Description', optional: true),
              TextFormField(controller: _description, enabled: !_saving, maxLength: 400,
                minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'What will you explore?')),
            ])))),
          Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              if (_error != null) ErrorNotice(_error!),
              PrimaryButton(label: widget.existing == null ? 'Create class' : 'Save changes',
                icon: Icons.check_rounded, busy: _saving, onPressed: _save),
            ])),
        ]),
      ))),
    ),
  );
  Widget _label(String label, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(optional ? '$label (optional)' : label,
      style: const TextStyle(fontWeight: FontWeight.w800, color: ink)),
  );
}
