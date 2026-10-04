import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../materials/supabase_file_storage.dart';
import '../onboarding/design.dart';
import '../onboarding/illustrations.dart';

class JoinClassScreen extends StatefulWidget {
  const JoinClassScreen({super.key, required this.uid});
  final String uid;
  @override
  State<JoinClassScreen> createState() => _JoinClassScreenState();
}

class _JoinClassScreenState extends State<JoinClassScreen> {
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _code.dispose(); super.dispose(); }

  Future<void> _join() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    final client = http.Client();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != widget.uid) throw const _JoinError('Sign in again to join.');
      final token = await user.getIdToken();
      final response = await client.post(Uri.parse('$supabaseUrl/functions/v1/class-join'),
        headers: {'apikey': supabasePublishableKey, 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'},
        body: jsonEncode({'code': _code.text.trim().toUpperCase()}),
      ).timeout(const Duration(seconds: 45));
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != widget.uid) return;
      if (response.statusCode != 200) throw _JoinError(switch (response.statusCode) {
        400 || 404 => 'Check the code and try again.',
        401 => 'Your session expired. Sign in again.',
        403 => 'Use a student account to join a class.',
        409 => 'This class is archived.',
        429 => 'Too many attempts. Try again in a minute.',
        _ => 'Could not join. Please try again.',
      });
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final id = data['classId'];
      if (id is! String || id.isEmpty) throw const _JoinError('Could not join. Please try again.');
      Navigator.pop(context, id);
    } on _JoinError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on TimeoutException {
      if (mounted) setState(() => _error = 'Joining timed out. Retry with the same code.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Check your connection and try again.');
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: Scaffold(
    appBar: AppBar(title: const Text('Join class')),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(children: [
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
          child: Form(key: _form, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Center(child: SizedBox(width: 180, height: 180,
                child: LearningArt(compact: true, expression: MascotExpression.curious))),
              const SizedBox(height: 24),
              Text('Class code', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8), const Text('Enter the code from your instructor.'),
              const SizedBox(height: 24),
              TextFormField(controller: _code, enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false, enableSuggestions: false,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  LengthLimitingTextInputFormatter(6)],
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                  color: ink, letterSpacing: 5),
                decoration: const InputDecoration(hintText: 'ABC234',
                  hintStyle: TextStyle(color: Color(0xFFA3ADA7),
                    fontWeight: FontWeight.w400)),
                onFieldSubmitted: (_) => _join(),
                validator: (value) => RegExp(r'^[A-HJ-KM-NP-Z2-9]{6}$')
                  .hasMatch((value ?? '').toUpperCase()) ? null : 'Enter a valid 6-character code.',
              ),
              if (_error != null) ...[const SizedBox(height: 16), ErrorNotice(_error!)],
            ])))),
        Padding(padding: const EdgeInsets.all(24), child: PrimaryButton(
          label: 'Join class', busy: _busy, icon: Icons.add_rounded,
          onPressed: _busy ? null : _join)),
      ]),
    ))),
  ));
}

class _JoinError implements Exception {
  const _JoinError(this.message);
  final String message;
}
