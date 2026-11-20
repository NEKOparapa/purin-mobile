import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'agent_api.dart';

abstract interface class MobileStore {
  Future<String> installationId();
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

  Future<File> get _themeFile async =>
      File('${(await getApplicationSupportDirectory()).path}/appearance');

  @override
  Future<ThemeMode> readTheme() async {
    final file = await _themeFile;
    if (!await file.exists()) return ThemeMode.system;
    final name = await file.readAsString();
    return ThemeMode.values.byName(name);
  }

  @override
  Future<void> saveTheme(ThemeMode mode) async {
    final file = await _themeFile;
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(mode.name, flush: true);
    await temp.rename(file.path);
  }

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
