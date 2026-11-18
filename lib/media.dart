import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'util.dart';

/// Ablage für Bilddateien. Auf Mobilgeräten Dateien im App-Verzeichnis,
/// im Browser der lokale Speicher (begrenzt, nur für wenige Bilder gedacht).
abstract class MediaStorage {
  Future<void> write(String id, Uint8List bytes);
  Future<Uint8List?> read(String id);
  Future<void> delete(String id);
}

class MemoryMediaStorage implements MediaStorage {
  final Map<String, Uint8List> files = {};

  @override
  Future<void> write(String id, Uint8List bytes) async => files[id] = bytes;

  @override
  Future<Uint8List?> read(String id) async => files[id];

  @override
  Future<void> delete(String id) async => files.remove(id);
}

class PrefsMediaStorage implements MediaStorage {
  static String _key(String id) => 'coachplan_media_$id';

  @override
  Future<void> write(String id, Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(_key(id), base64Encode(bytes));
    if (!ok) throw StateError('Bild konnte nicht gespeichert werden');
  }

  @override
  Future<Uint8List?> read(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(id));
    return raw == null ? null : base64Decode(raw);
  }

  @override
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(id));
  }
}

/// Zugriff auf gespeicherte Bilder mit Zwischenspeicher, damit Listen beim
/// Neuaufbau nicht jedes Mal von der Platte lesen.
class MediaLibrary {
  MediaLibrary(this._storage);

  final MediaStorage _storage;
  final Map<String, Future<Uint8List?>> _cache = {};

  /// Meldet ein neu aufgenommenes Bild (für den Upload zum Server).
  void Function(String id)? onAdded;

  /// Holt ein lokal fehlendes Bild vom Server; `null` ohne Verbindung.
  Future<Uint8List?> Function(String id)? remoteFetch;

  Future<String> add(Uint8List bytes) async {
    final id = newId();
    await _storage.write(id, bytes);
    _cache[id] = Future.value(bytes);
    onAdded?.call(id);
    return id;
  }

  /// Nur das, was auf diesem Gerät liegt.
  Future<Uint8List?> loadLocal(String id) async {
    try {
      return await _storage.read(id);
    } catch (_) {
      return null;
    }
  }

  /// Lokal, sonst vom Server (und dann lokal ablegen).
  Future<Uint8List?> load(String id) => _cache[id] ??= _load(id);

  Future<Uint8List?> _load(String id) async {
    final local = await loadLocal(id);
    if (local != null) return local;
    final fetch = remoteFetch;
    if (fetch == null) {
      _cache.remove(id); // später erneut versuchen
      return null;
    }
    try {
      final bytes = await fetch(id);
      if (bytes != null) {
        try {
          await _storage.write(id, bytes);
        } catch (_) {
          // Lokaler Speicher voll (v. a. im Browser): trotzdem anzeigen.
        }
        return bytes;
      }
    } catch (_) {
      // offline oder (noch) nicht hochgeladen
    }
    _cache.remove(id);
    return null;
  }

  Future<void> remove(String id) async {
    _cache.remove(id);
    try {
      await _storage.delete(id);
    } catch (_) {
      // Eine verwaiste Datei ist unkritisch.
    }
  }
}
