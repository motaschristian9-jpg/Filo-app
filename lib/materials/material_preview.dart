import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../onboarding/design.dart';
import 'material_cache.dart';
import 'material_repository.dart';
import 'material_sync.dart';
import 'supabase_file_storage.dart';

class MaterialPreview extends StatefulWidget {
  const MaterialPreview({super.key, required this.material, required this.uid, this.sync});
  final ClassMaterial material;
  final String uid;
  final MaterialSync? sync;
  @override
  State<MaterialPreview> createState() => _MaterialPreviewState();
}

class _MaterialPreviewState extends State<MaterialPreview> {
  late final MaterialCache _cache = widget.sync?.cache ?? MaterialCache(widget.uid);
  Uint8List? _bytes;
  String? _error;
  bool _loading = true, _opening = false, _revoked = false;
  StreamSubscription<User?>? _auth;
  int _request = 0;
  String get _extension => widget.material.fileName.split('.').last.toLowerCase();
  bool get _image => const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(_extension);
  bool get _text => const ['txt', 'md', 'csv', 'json', 'log', 'xml'].contains(_extension);
  bool get _supported => _image || _text || _extension == 'pdf';
  bool get _allowed => !_revoked && FirebaseAuth.instance.currentUser?.uid == widget.uid &&
      (widget.sync == null || widget.sync!.hasClass(widget.material.classId));

  @override
  void initState() {
    super.initState();
    widget.sync?.addListener(_accessChanged);
    _auth = FirebaseAuth.instance.authStateChanges().listen((_) => _accessChanged());
    _load();
  }

  void _accessChanged() {
    if (!mounted || _allowed || _revoked) return;
    _request++;
    setState(() { _revoked = true; _bytes = null; _loading = false; });
  }

  Future<void> _load() async {
    final request = ++_request;
    if (!_allowed) { _accessChanged(); return; }
    if (!_supported) { setState(() => _loading = false); return; }
    setState(() { _loading = true; _error = null; _bytes = null; });
    try {
      // A preview can use the offline copy, but never waits for the download
      // queue or writes a second partial file alongside it.
      if (widget.material.size <= 0 || widget.material.size > maxMaterialBytes) {
        throw StateError('Unsupported file size');
      }
      final bytes = await _cache.readBytes(widget.material) ??
          await SupabaseFileStorage().download(widget.material.classId, widget.material.id);
      if (!mounted || request != _request || !_allowed) return;
      if (bytes.length != widget.material.size) throw StateError('Incomplete file');
      setState(() { _bytes = bytes; _loading = false; });
    } catch (_) {
      if (mounted && request == _request && _allowed) {
        setState(() { _loading = false; _error = 'Could not load preview. Check your connection and retry.'; });
      }
    }
  }

  Future<void> _external() async {
    if (_opening || !_allowed) return;
    setState(() => _opening = true);
    try {
      if (_cache.supported && !await _cache.contains(widget.material)) {
        // Let the student's single download queue own the cache file.
        if (widget.sync != null) {
          widget.sync!.retry();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saving file. Open it when the download finishes.')));
          return;
        }
        await _cache.download(widget.material, () => mounted && _allowed);
      }
      if (mounted && _allowed) await _cache.open(widget.material);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open file. Check your connection or file viewer.')));
    } finally { if (mounted) setState(() => _opening = false); }
  }

  @override
  void dispose() {
    _request++;
    widget.sync?.removeListener(_accessChanged);
    _auth?.cancel();
    _bytes = null;
    super.dispose();
  }

  Widget _notice(String text, {bool retry = false}) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.description_outlined, size: 48, color: teal),
      const SizedBox(height: 16),
      Text(text, textAlign: TextAlign.center),
      if (retry) TextButton(onPressed: _load, child: const Text('Retry')),
    ]),
  ));

  Widget _content() {
    if (_revoked) return _notice('This file is no longer available.');
    if (_loading) return const FiloSkeleton(layout: SkeletonLayout.preview);
    if (_error != null) return _notice(_error!, retry: true);
    if (!_supported) return _notice('Preview is not available for this file type.');
    final bytes = _bytes!;
    if (_image) return InteractiveViewer(minScale: 0.5, maxScale: 6,
      child: Center(child: Image.memory(bytes, fit: BoxFit.contain,
        cacheWidth: 2400,
        semanticLabel: widget.material.title,
        errorBuilder: (_, _, _) => _notice('This image could not be previewed.'))));
    if (_extension == 'pdf') return PdfViewer.data(bytes,
      sourceName: '${widget.uid}/${widget.material.cacheKey}',
      params: PdfViewerParams(
        backgroundColor: const Color(0xFFF1F3ED),
        errorBannerBuilder: (_, _, _, _) => _notice('This PDF could not be previewed.'),
      ));
    const limit = 200000;
    final length = bytes.length > limit ? limit : bytes.length;
    final text = utf8.decode(Uint8List.sublistView(bytes, 0, length), allowMalformed: true);
    return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(text),
        if (bytes.length > limit) const Padding(padding: EdgeInsets.only(top: 16),
          child: Text('Showing the beginning of this file.')),
      ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.material.fileName, maxLines: 1,
      overflow: TextOverflow.ellipsis)),
    body: SafeArea(child: Column(children: [
      Expanded(child: SizedBox(width: double.infinity, child: _content())),
      if (!_revoked) Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
          child: PrimaryButton(label: 'Open in another app',
            icon: Icons.open_in_new_rounded, busy: _opening,
            onPressed: _opening ? null : _external))),
    ])),
  );
}
