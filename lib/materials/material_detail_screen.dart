import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../onboarding/design.dart';
import 'material_preview.dart';
import 'material_cache.dart';
import 'material_repository.dart';
import 'material_sync.dart';
import 'drive_link.dart';
import 'link_preview.dart';
import 'link_download.dart';
import 'author_cache.dart';
import 'download_index.dart';
import 'post_submissions.dart';
import 'submission_action.dart';

class MaterialDetailScreen extends StatefulWidget {
  const MaterialDetailScreen({super.key, required this.material,
    required this.className, required this.uid, this.sync});
  final ClassMaterial material;
  final String className, uid;
  final MaterialSync? sync;
  @override
  State<MaterialDetailScreen> createState() => _MaterialDetailScreenState();
}

class _MaterialDetailScreenState extends State<MaterialDetailScreen> with WidgetsBindingObserver {
  bool _opening = false, _savingOffline = false, _checkingOffline = true;
  bool? _savedOffline;
  String? _downloadedName;
  late final MaterialCache _cache = MaterialCache(widget.uid);
  int _offlineRequest = 0;
  final _submissionAction = SubmissionActionController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DownloadIndex.instance.revision.addListener(_downloadsChanged);
    _refreshOffline();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshOffline();
  }

  @override
  void dispose() {
    _submissionAction.dispose();
    WidgetsBinding.instance.removeObserver(this);
    DownloadIndex.instance.revision.removeListener(_downloadsChanged);
    super.dispose();
  }
  void _downloadsChanged() {
    if (mounted) { setState(() {}); _refreshOffline(); }
  }

  Future<void> _refreshOffline() async {
    if (widget.material.kind == 'link' && _cache.supported) {
      final request = ++_offlineRequest;
      final saved = await _cache.containsLink(widget.material);
      final name = saved ? await _cache.linkFileName(widget.material) : null;
      if (mounted && _available && request == _offlineRequest) {
        setState(() { _savedOffline = saved; _downloadedName = name; _checkingOffline = false; });
      }
      return;
    }
    if (widget.sync != null || !widget.material.hasFile || !_cache.supported) return;
    final request = ++_offlineRequest;
    try {
      final saved = await _cache.contains(widget.material);
      if (mounted && _available && request == _offlineRequest) {
        setState(() { _savedOffline = saved; _checkingOffline = false; });
      }
    } catch (_) {
      if (mounted && request == _offlineRequest) {
        setState(() { _savedOffline = null; _checkingOffline = false; });
      }
    }
  }

  Future<void> _saveOffline() async {
    if (_savingOffline || _opening || !_available || !_cache.supported) return;
    setState(() => _savingOffline = true);
    try {
      await _cache.download(widget.material, () => mounted && _available);
      await _refreshOffline();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save file. Check your connection and retry.')));
    } finally { if (mounted) setState(() => _savingOffline = false); }
  }
  late final _author = AuthorCache.instance.watch(widget.uid, widget.material.data['authorId'] as String?);
  late final Stream<List<ClassMaterial>> _attachments = MaterialRepository().watch(widget.material.classId);


  bool get _available => FirebaseAuth.instance.currentUser?.uid == widget.uid &&
    (widget.sync == null || widget.sync!.hasClass(widget.material.classId));

  Future<void> _openAttachment() async {
    if (_opening || _savingOffline || !_available) return;
    setState(() => _opening = true);
    try {
      final item = widget.material;
      if (item.hasFile) {
        await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) =>
          MaterialPreview(material: item, uid: widget.uid, sync: widget.sync)));
        if (mounted) await _refreshOffline();
      } else if (item.kind == 'link') {
        if (_cache.supported && await _cache.containsLink(item)) {
          if (!mounted || !_available) return;
          await _cache.openLink(item);
          return;
        }
        final preview = LinkPreview.parse(item.url);
        final uri = preview?.uri ?? Uri.tryParse(item.url);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
            !await launchUrl(uri, mode: preview == null
              ? LaunchMode.externalApplication : LaunchMode.inAppBrowserView)) {
          throw StateError('Could not open link');
        }
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.material.kind == 'link'
          ? 'This link could not be opened. Check the link and your connection, then try again.'
          : 'Could not open this attachment.')));
    } finally { if (mounted) setState(() => _opening = false); }
  }

  Future<void> _downloadDrive(DriveLink drive) async {
    if (_opening || !_available) return;
    setState(() => _opening = true);
    try {
      final saved = await downloadDriveToDevice(drive, widget.material, _cache,
        () => mounted && _available);
      if (mounted) await _refreshOffline();
      if (saved && mounted && _available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved in Filo downloads.')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is StateError ? error.message.toString()
          : 'Could not download. Check your connection or open the file in Drive.')));
    } finally { if (mounted) setState(() => _opening = false); }
  }

  Widget _details() {
    if (!_available) return const Center(child: Text('This material is no longer available.'));
    final item = widget.material;
    final file = item.hasFile;
    final attachment = file || item.kind == 'link';
    final drive = item.kind == 'link' ? DriveLink.parse(item.url) : null;
    final preview = item.kind == 'link' ? LinkPreview.parse(item.url) : null;
    final state = widget.sync?.states[item.cacheKey];
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800),
      child: Column(children: [
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ValueListenableBuilder<AuthorProfileState>(valueListenable: _author, builder: (context, profile, _) {
              if (profile.loading) {
                return const FiloSkeleton(layout: SkeletonLayout.author,
                  scrollable: false, padding: EdgeInsets.zero);
              }
              final author = profile.data;
              final name = author?['name'] as String? ?? author?['displayName'] as String? ?? 'Instructor';
              final avatar = (author?['avatar'] as num?)?.toInt() ?? 0;
              return Row(children: [
                ProfileAvatar(avatar: avatar, photoUrl: author?['photoUrl'] as String?, size: 44),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: Theme.of(context).textTheme.titleMedium),
                  if (item.createdAt != null) Text(
                    MaterialLocalizations.of(context).formatMediumDate(item.createdAt!.toLocal()),
                    style: Theme.of(context).textTheme.bodySmall),
                ])),
              ]);
            }),
            const SizedBox(height: 24),
            SelectableText(item.title, style: Theme.of(context).textTheme.headlineMedium),
            if (item.body.isNotEmpty) ...[
              const SizedBox(height: 16), SelectableText(item.body),
            ],
            if (item.requiresSubmission) ...[
              const SizedBox(height: 24),
              PostSubmissions(post: item, uid: widget.uid, actionController: _submissionAction),
            ],
            if (item.attachmentIds.isNotEmpty) ...[
              const SizedBox(height: 24),
              StreamBuilder<List<ClassMaterial>>(stream: _attachments, builder: (context, snapshot) {
                if (snapshot.hasError) return const ErrorNotice('Could not load attachments.');
                if (!snapshot.hasData) return const FiloSkeleton(scrollable: false);
                final children = snapshot.data!.where((a) => a.parentId == item.id && item.attachmentIds.contains(a.id)).toList();
                return Column(children: [for (final child in children) Card(child: ListTile(
                  leading: Icon(child.hasFile ? Icons.description_outlined
                    : LinkPreview.parse(child.url)?.label == 'YouTube' ? Icons.play_circle_outline_rounded
                    : Icons.link_rounded, color: teal),
                  title: child.hasFile ? Text(child.fileName, maxLines: 2, overflow: TextOverflow.ellipsis)
                    : FutureBuilder<String?>(future: _cache.linkFileName(child), builder: (_, saved) =>
                        Text(saved.data ?? (DriveLink.parse(child.url) != null ? child.title : child.url),
                          maxLines: 2, overflow: TextOverflow.ellipsis)),
                  subtitle: FutureBuilder<bool>(future: child.hasFile
                    ? _cache.contains(child) : _cache.containsLink(child), builder: (_, saved) =>
                      Text(saved.data == true ? 'Downloaded · Available offline'
                        : child.hasFile ? 'Tap to open' : LinkPreview.parse(child.url)?.action ?? 'Tap to open')),
                  trailing: const Icon(Icons.chevron_right_rounded, color: teal),
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) =>
                    child.hasFile ? MaterialPreview(material: child, uid: widget.uid, sync: widget.sync)
                      : MaterialDetailScreen(material: child, className: widget.className, uid: widget.uid, sync: widget.sync))),
                ))]);
              }),
            ],
            if (attachment) ...[
              const SizedBox(height: 24),
              Material(color: mint, borderRadius: BorderRadius.circular(20),
                child: InkWell(onTap: _opening || _savingOffline ? null : _openAttachment,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(padding: const EdgeInsets.all(20),
                    child: Row(children: [
                      Icon(file ? Icons.description_outlined : preview?.label == 'YouTube'
                        ? Icons.play_circle_outline_rounded : Icons.link_rounded,
                        size: 36, color: teal),
                      const SizedBox(width: 16),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(file ? item.fileName : _downloadedName ??
                          (drive != null ? item.title : preview?.label ?? Uri.tryParse(item.url)?.host ?? item.url),
                          style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(file ? '${(item.size / (1024 * 1024)).toStringAsFixed(1)} MB'
                          : _savedOffline == true ? 'Tap to open downloaded file' : preview?.action ?? 'Tap to open',
                          style: Theme.of(context).textTheme.bodySmall),
                      ])),
                      const SizedBox(width: 12),
                      const Icon(Icons.chevron_right_rounded, color: teal),
                    ])),
                )),
              if (!file && preview == null) Padding(padding: const EdgeInsets.only(top: 12),
                child: SelectableText(item.url)),
              if (drive != null) ...[
                const SizedBox(height: 12),
                Text(_savedOffline == true ? 'Saved in Filo downloads' : 'Stored in Google Drive · Internet required',
                  style: Theme.of(context).textTheme.bodySmall),
                if (_savedOffline == true) const Row(children: [
                  Icon(Icons.offline_pin_rounded, size: 20, color: teal),
                  SizedBox(width: 8), Text('Downloaded · Available offline'),
                ]),
                if (_cache.supported && _savedOffline != true) TextButton.icon(
                  onPressed: _opening || _checkingOffline ? null
                    : () => _downloadDrive(drive),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(_opening ? 'Please wait...' : 'Download to device')),
                if (drive.documentType != null && _savedOffline != true) Text('Downloads as PDF · Up to 25 MB',
                  style: Theme.of(context).textTheme.bodySmall),
              ],
              if (file && widget.sync == null && _cache.supported) ...[
                const SizedBox(height: 12),
                if (_savingOffline || _checkingOffline) Row(children: [
                  const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Flexible(child: Text(_savingOffline ? 'Saving offline...' : 'Checking saved file...')),
                ])
                else if (_savedOffline == true) const Row(children: [
                  Icon(Icons.offline_pin_rounded, size: 20, color: teal),
                  SizedBox(width: 8), Flexible(child: Text('Saved on this device')),
                ])
                else if (_savedOffline == null) TextButton.icon(
                  onPressed: _refreshOffline, icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check saved file'))
                else TextButton.icon(onPressed: _opening ? null : _saveOffline,
                  icon: const Icon(Icons.download_rounded), label: const Text('Save offline')),
              ],
              if (file && widget.sync != null && widget.sync!.cache.supported) ...[
                const SizedBox(height: 12),
                Text(switch (state) {
                  FileSyncState.ready => 'Available offline',
                  FileSyncState.downloading => 'Downloading...',
                  FileSyncState.failed => 'Download paused',
                  _ => 'Waiting to download',
                }, style: Theme.of(context).textTheme.bodySmall),
                if (state == FileSyncState.downloading)
                  const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                if (state == FileSyncState.failed)
                  TextButton(onPressed: widget.sync!.retry, child: const Text('Retry download')),
              ],
            ],
          ]))),
        if (item.requiresSubmission && item.data['authorId'] != widget.uid)
          ValueListenableBuilder<SubmissionAction?>(valueListenable: _submissionAction,
            builder: (_, action, _) => action == null ? const SizedBox.shrink()
              : Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
                    child: PrimaryButton(label: action.label, icon: Icons.upload_rounded,
                      onPressed: action.onPressed)))),
        if (item.kind == 'link' && preview == null) Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
            child: PrimaryButton(label: 'Open link',
              icon: Icons.open_in_new_rounded,
              busy: _opening, onPressed: _opening ? null : _openAttachment))),
      ])));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.className)),
    body: SafeArea(child: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, _) => widget.sync == null ? _details() :
        ListenableBuilder(listenable: widget.sync!, builder: (context, _) => _details()),
    )),
  );
}
