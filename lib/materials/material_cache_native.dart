import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'supabase_file_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'material_repository.dart';
import 'download_index.dart';

class MaterialCache {
  MaterialCache(this.uid);
  final String uid;
  bool get supported => true;
  static final Map<String, Future<void>> _downloads = {};
  String _safe(String value) => Uri.encodeComponent(value).replaceAll('.', '%2E');
  Future<Directory> _classDirectory(String id) async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/materials/${_safe(uid)}/${_safe(id)}');
  }
  Future<File> _file(ClassMaterial material) async {
    final directory = await _classDirectory(material.classId);
    // Keep only a conservative extension for the platform's document viewer.
    final match = RegExp(r'\.([a-zA-Z0-9]{1,10})$').firstMatch(material.fileName);
    final extension = match == null ? '' : '.${match.group(1)!.toLowerCase()}';
    return File('${directory.path}/${_safe(material.id)}$extension');
  }
  Future<bool> contains(ClassMaterial material) async {
    return DownloadIndex.instance.read(uid, '${material.cacheKey}/file',
      '${material.storagePath}/${material.fileName}/${material.size}', () async {
        final file = await _file(material);
        return await file.exists() && await file.length() == material.size;
      });
  }
  Future<Uint8List?> readBytes(ClassMaterial material) async {
    final file = await _file(material);
    if (!await file.exists() || await file.length() != material.size) return null;
    return file.readAsBytes();
  }
  Future<void> download(ClassMaterial material, bool Function() active) async {
    final key = '$uid/${material.cacheKey}';
    final existing = _downloads[key];
    if (existing != null) {
      await existing;
      if (!active() || await contains(material)) return;
    }
    final task = _download(material, active);
    _downloads[key] = task;
    try { await task; }
    finally { if (identical(_downloads[key], task)) _downloads.remove(key); }
  }
  Future<void> _download(ClassMaterial material, bool Function() active) async {
    if (await contains(material) || !active()) return;
    if (material.size <= 0 || material.size > maxMaterialBytes) {
      throw StateError('Unsupported file size');
    }
    final bytes = await SupabaseFileStorage().download(material.classId, material.id);
    if (!active()) return;
    if (bytes.length != material.size) {
      throw StateError('Incomplete download');
    }
    final file = await _file(material);
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.part');
    await partial.writeAsBytes(bytes, flush: true);
    if (!active()) {
      if (await partial.exists()) await partial.delete();
      return;
    }
    await partial.rename(file.path);
    if (!active() && await file.exists()) await file.delete();
    DownloadIndex.instance.invalidate(uid: uid, classId: material.classId, materialId: material.id);
  }
  Future<void> open(ClassMaterial material) async {
    final file = await _file(material);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw StateError('No app could open this file.');
    }
  }
  Future<Map<String, dynamic>?> _linkRecord(ClassMaterial material) =>
    DownloadIndex.instance.read(uid, '${material.cacheKey}/link', material.url,
      () => _readLinkRecord(material));
  Future<Map<String, dynamic>?> _readLinkRecord(ClassMaterial material) async {
    try {
      final directory = await _classDirectory(material.classId);
      final record = File('${directory.path}/links/${_safe(material.id)}/record.json');
      if (!await record.exists()) return null;
      final data = jsonDecode(await record.readAsString()) as Map<String, dynamic>;
      final name = data['file'] as String;
      if (data['url'] != material.url || !RegExp(r'^content(\.[a-z0-9]{1,10})?$').hasMatch(name)) return null;
      final file = File('${record.parent.path}/$name');
      return await file.exists() && await file.length() == data['size']
        ? {...data, 'path': file.path} : null;
    } catch (_) { return null; }
  }
  Future<bool> containsLink(ClassMaterial material) async => await _linkRecord(material) != null;
  Future<String?> linkFileName(ClassMaterial material) async {
    return (await _linkRecord(material))?['name'] as String?;
  }
  Future<void> saveLink(ClassMaterial material, String name, Uint8List bytes,
      bool Function() active) async {
    if (!active() || bytes.isEmpty) return;
    final directory = await _classDirectory(material.classId);
    final folder = Directory('${directory.path}/links/${_safe(material.id)}');
    await folder.create(recursive: true);
    final extension = RegExp(r'\.([a-zA-Z0-9]{1,10})$').firstMatch(name)?.group(1)?.toLowerCase();
    final fileName = 'content${extension == null ? '' : '.$extension'}';
    final partial = File('${folder.path}/$fileName.part');
    await partial.writeAsBytes(bytes, flush: true);
    if (!active()) { await partial.delete(); return; }
    await partial.rename('${folder.path}/$fileName');
    // Publish the tracking record only after the complete file is on disk.
    final record = File('${folder.path}/record.json.part');
    await record.writeAsString(jsonEncode({'url': material.url, 'file': fileName,
      'name': name, 'size': bytes.length}), flush: true);
    await record.rename('${folder.path}/record.json');
    if (!active() && await folder.exists()) await folder.delete(recursive: true);
    DownloadIndex.instance.invalidate(uid: uid, classId: material.classId, materialId: material.id);
  }
  Future<void> openLink(ClassMaterial material) async {
    // Recheck the actual disk before opening; the index is only a UI optimization.
    final record = await _readLinkRecord(material);
    if (record == null) {
      DownloadIndex.instance.invalidate(uid: uid, classId: material.classId, materialId: material.id);
      throw StateError('File is not downloaded.');
    }
    final file = File(record['path'] as String);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) throw StateError('No app could open this file.');
  }
  Future<void> removeClass(String id) async {
    final directory = await _classDirectory(id);
    if (await directory.exists()) await directory.delete(recursive: true);
    DownloadIndex.instance.invalidate(uid: uid, classId: id);
  }
  // Only call with a complete, server-confirmed list, never a paginated/cache list.
  Future<void> reconcileClass(String id, List<ClassMaterial> items, bool Function() active) async {
    final directory = await _classDirectory(id);
    if (!active() || !await directory.exists()) return;
    final keepFiles = <String>{};
    final keepLinks = <String>{};
    for (final item in items) {
      if (item.hasFile) keepFiles.add((await _file(item)).uri.toString());
      if (item.kind == 'link') keepLinks.add(_safe(item.id));
    }
    var changed = false;
    await for (final entry in directory.list(followLinks: false)) {
      if (!active()) return;
      if (entry is File) {
        if (entry.path.endsWith('.part')) {
          if (DateTime.now().difference(await entry.lastModified()).inHours < 24) continue;
        } else if (keepFiles.contains(entry.uri.toString())) { continue; }
        await entry.delete();
        changed = true;
      } else if (entry is Directory && entry.uri.pathSegments.where((s) => s.isNotEmpty).last == 'links') {
        await for (final folder in entry.list(followLinks: false)) {
          if (!active()) return;
          if (folder is! Directory) continue;
          final normalizedName = folder.path.replaceAll('\\', '/').split('/').last;
          if (!keepLinks.contains(normalizedName)) {
            await folder.delete(recursive: true);
            changed = true;
          }
        }
      }
    }
    if (changed) DownloadIndex.instance.invalidate(uid: uid, classId: id);
  }
}
