import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'media.dart';

MediaStorage createPlatformMediaStorage() => FileMediaStorage();

class FileMediaStorage implements MediaStorage {
  Future<Directory>? _dir;

  Future<Directory> _directory() => _dir ??= () async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/coachplan_media').create(recursive: true);
  }();

  Future<File> _file(String id) async =>
      File('${(await _directory()).path}/$id.img');

  @override
  Future<void> write(String id, Uint8List bytes) async {
    await (await _file(id)).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List?> read(String id) async {
    final f = await _file(id);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> delete(String id) async {
    final f = await _file(id);
    if (await f.exists()) await f.delete();
  }
}
