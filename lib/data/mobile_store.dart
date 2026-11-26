import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'agent_api.dart';
import '../l10n/app_language.dart';

abstract interface class MobileStore {
  Future<String> installationId();
  Future<AppLanguage> readLanguage();
  Future<void> saveLanguage(AppLanguage language);
  Future<ThemeMode> readTheme();
  Future<void> saveTheme(ThemeMode mode);
  Future<Connection?> connection();
  Future<void> saveConnection(Connection value);
  Future<Json> history(String scope);
  Future<void> saveHistory(String scope, Json value);
}

class DeviceStore implements MobileStore {
  final _secrets = const FlutterSecureStorage();

  @override
  Future<String> installationId() async {
    final existing = await _secrets.read(key: 'device.installation');
    if (existing != null) return existing;
    final id = newEventId();
    await _secrets.write(key: 'device.installation', value: id);
    return id;
  }

  Future<File> _preferenceFile(String name) async =>
      File('${(await getApplicationSupportDirectory()).path}/$name');

  Future<String?> _readPreference(String name) async {
    final file = await _preferenceFile(name);
    return await file.exists() ? (await file.readAsString()).trim() : null;
  }

  Future<void> _savePreference(String name, String value) async {
    final file = await _preferenceFile(name);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(value, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<ThemeMode> readTheme() async =>
      await _readPreference('appearance') == ThemeMode.dark.name
      ? ThemeMode.dark
      : ThemeMode.light;

  @override
  Future<void> saveTheme(ThemeMode mode) =>
      _savePreference('appearance', mode.name);

  @override
  Future<AppLanguage> readLanguage() async =>
      AppLanguage.fromTag(await _readPreference('language'));

  @override
  Future<void> saveLanguage(AppLanguage language) =>
      _savePreference('language', language.locale.toLanguageTag());

  @override
  Future<Connection?> connection() async {
    final raw = await _secrets.read(key: 'agent.connection');
    if (raw == null) return null;
    final data = jsonDecode(raw) as Json;
    final connection = Connection.fromJson(data);
    if (data.containsKey('terminal')) await saveConnection(connection);
    return connection;
  }

  @override
  Future<void> saveConnection(Connection value) => _secrets.write(
    key: 'agent.connection',
    value: jsonEncode(value.toJson()),
  );

  Future<File> get _file async => File(
    '${(await getApplicationSupportDirectory()).path}/agent-history.json',
  );

  Future<Json> _scopes(File file) async =>
      await file.exists() ? jsonDecode(await file.readAsString()) as Json : {};

  @override
  Future<Json> history(String scope) async =>
      (await _scopes(await _file))[scope] ?? {};

  @override
  Future<void> saveHistory(String scope, Json value) async {
    final file = await _file;
    final scopes = await _scopes(file);
    scopes[scope] = value;
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(scopes), flush: true);
    await temp.rename(file.path);
  }
}
