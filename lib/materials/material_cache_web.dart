import 'dart:typed_data';
import 'supabase_file_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'material_repository.dart';

class MaterialCache {
  MaterialCache(this.uid);
  final String uid;
  bool get supported => false;
  Future<bool> containsLink(ClassMaterial material) async => false;
  Future<String?> linkFileName(ClassMaterial material) async => null;
  Future<void> saveLink(ClassMaterial material, String name, Uint8List bytes,
      bool Function() active) async => throw UnsupportedError('Device downloads require the native app.');
  Future<void> openLink(ClassMaterial material) async => throw UnsupportedError('No local file.');
  Future<bool> contains(ClassMaterial material) async => false;
  Future<Uint8List?> readBytes(ClassMaterial material) async => null;
  Future<void> download(ClassMaterial material, bool Function() active) async {}
  Future<void> removeClass(String id) async {}
  Future<void> reconcileClass(String id, List<ClassMaterial> items, bool Function() active) async {}
  Future<void> open(ClassMaterial material) async {
    final url = await SupabaseFileStorage().downloadUrl(material.classId, material.id);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw StateError('Could not open this file.');
    }
  }
}
