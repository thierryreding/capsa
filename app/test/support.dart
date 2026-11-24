// Test helpers: load profiles and vectors from the repository. Only used by tests.
import 'dart:convert';
import 'dart:io';

import 'package:capsa/learning/profile.dart';
import 'package:yaml/yaml.dart';

/// The repository root; `flutter test` runs in app/.
final repo = Directory.current.parent.path;

Object? loadJson(String path) => jsonDecode(File('$repo/$path').readAsStringSync());

/// A YAML profile as the plain JSON the API would serve.
Map<String, Object?> loadProfileJson(String path) {
  final file = path.startsWith('/') ? File(path) : File('$repo/$path');
  return (jsonDecode(jsonEncode(loadYaml(file.readAsStringSync()))) as Map).cast();
}

ProfileDocument loadProfile(String path) => ProfileDocument.fromJson(loadProfileJson(path));

const demoProfile = 'profiles/demo/demo-latin.yaml';

/// Private profiles on this machine, if any. Tests over them assert invariants and never
/// copy their content anywhere.
List<String> privateProfilePaths() {
  final dir = Directory('$repo/profiles/private');
  if (!dir.existsSync()) return [];
  return [
    for (final f in dir.listSync())
      if (f.path.endsWith('.yaml')) f.path,
  ]..sort();
}
