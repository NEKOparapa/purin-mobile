import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../data/agent_api.dart';
import '../data/mobile_terminal_tools.dart';
import '../data/mobile_session.dart';
import '../widgets/app_theme.dart';
import '../widgets/shared.dart';

class _ApiKeyItem {
  const _ApiKeyItem({
    required this.id,
    required this.usages,
    required this.configured,
    required this.masked,
  });

  final String id;
  final List<String> usages;
  final bool configured;
  final String? masked;

  String get title => usages.isNotEmpty ? usages.join('、') : id;
}

class ApiKeySettingsScreen extends StatefulWidget {
  const ApiKeySettingsScreen({super.key, required this.session});
  final MobileSession session;

  @override
  State<ApiKeySettingsScreen> createState() => _ApiKeySettingsScreenState();
}

class _ApiKeySettingsScreenState extends State<ApiKeySettingsScreen> {
  late final Connection? _connection = widget.session.connection;
  List<_ApiKeyItem>? _items;
  String? _editingId;
  final _draft = TextEditingController();
  bool _visible = false;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _feedback;

  static final _validKey = RegExp(r'^[!-~]{1,4096}$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  String _friendlyError(Object e) {
    if (e is ApiError) {
      if (e.code == 'secure_transport_required') {
        return '管理接口密钥需要 HTTPS 或本机连接';
      }
      if (e.status == 401) return '设备令牌无效，请重新连接';
      if (e.status == 403) return '此设备没有管理接口密钥的权限';
      if (e.status == 404 && e.code == 'unknown_key_id') {
        return '密钥配置项已变更，请刷新';
      }
      if (e.status == 404 || e.status == 405) {
        return '当前后端不支持接口密钥管理，请更新后端';
      }
      if (e.status == 400) return '请输入有效的接口密钥';
      if (e.status == 503) return '后端暂时无法读写接口密钥';
    }
    if (e is FormatException) return '后端返回的密钥设置格式无效';
    return '无法连接后端，请检查连接后重试';
  }

  List<_ApiKeyItem> _parseItems(Json page) {
    final raw = page['items'];
    if (raw is! List) throw const FormatException('invalid items');
    final result = <_ApiKeyItem>[];
    for (final row in raw) {
      if (row is! Map) throw const FormatException('invalid item');
      final id = row['id'];
      final usages = row['usages'];
      final configured = row['configured'];
      final masked = row['masked'];
      if (id is! String ||
          id.isEmpty ||
          usages is! List ||
          usages.any((u) => u is! String) ||
          configured is! bool ||
          (configured && masked != null && masked is! String)) {
        throw const FormatException('invalid item fields');
      }
      result.add(
        _ApiKeyItem(
          id: id,
          usages: usages.cast<String>(),
          configured: configured,
          masked: masked is String ? masked : null,
        ),
      );
    }
    return result;
  }

  Future<void> _load() async {
    final conn = _connection;
    if (conn == null) return;
    if (!secureToolConnection(conn)) {
      setState(() {
        _error = '管理接口密钥需要 HTTPS 或本机连接';
        _items = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _editingId = null;
      _draft.clear();
      _visible = false;
    });
    try {
      final page = await widget.session.api.request(conn, 'settings/api-keys');
      if (!mounted) return;
      if (conn != widget.session.connection) {
        setState(() => _error = '连接已更改，请重新打开接口密钥');
        return;
      }
      setState(() => _items = _parseItems(page));
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startEdit(String? id) {
    setState(() {
      _editingId = id;
      _draft.clear();
      _visible = false;
      _feedback = null;
    });
  }

  Future<void> _save(_ApiKeyItem item) async {
    final conn = _connection;
    final candidate = _draft.text.trim();
    if (conn == null || !_validKey.hasMatch(candidate) || _saving) return;
    if (conn != widget.session.connection) {
      setState(() => _error = '连接已更改，请重新打开接口密钥');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _visible = false;
      _error = null;
      _feedback = null;
    });
    try {
      final page = await widget.session.api.request(
        conn,
        'settings/api-keys',
        body: {'id': item.id, 'api_key': candidate},
      );
      if (!mounted) return;
      setState(() {
        _items = _parseItems(page);
        _editingId = null;
        _draft.clear();
        _feedback = '${item.title}的密钥已保存。';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _editingId = null;
          _draft.clear();
          _error = _friendlyError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    final conn = _connection;

    return AtmosphereScaffold(
      title: '接口密钥',
      actions: [
        if (conn != null)
          IconButton(
            tooltip: '刷新',
            onPressed: (_loading || _saving) ? null : _load,
            icon: const Icon(Icons.refresh_rounded, size: 21),
          ),
      ],
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (conn == null)
                  GlassCard(
                    radius: 26,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 38,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.key_rounded,
                          size: 28,
                          color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '请先在「连接」中连接后端，再管理接口密钥。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(
                      '已保存的密钥只显示掩码。更换后，同组列出的用途会一起使用新密钥。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: atmo.sectionHeader,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    GlassCard(
                      radius: 22,
                      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: colors.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: colors.error,
                              ),
                            ),
                          ),
                          TextButton(onPressed: _load, child: const Text('重试')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_loading && _items == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: CupertinoActivityIndicator(radius: 12),
                      ),
                    )
                  else if (_items != null && _items!.isEmpty)
                    GlassCard(
                      radius: 24,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 36,
                      ),
                      child: Text(
                        '后端没有可管理的接口密钥。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  else if (_items != null)
                    SettingsSection(
                      title: '后端接口密钥',
                      dividers: true,
                      children: [
                        for (final item in _items!) _buildKeyRow(context, item),
                      ],
                    ),
                  if (_feedback != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _feedback!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeyRow(BuildContext context, _ApiKeyItem item) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    final editing = _editingId == item.id;
    final subtitle = item.configured
        ? (item.masked != null ? '已配置  ${item.masked}' : '已配置')
        : '未配置';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!editing)
                TextButton(
                  onPressed: (_editingId != null || _saving)
                      ? null
                      : () => _startEdit(item.id),
                  child: Text(item.configured ? '更换' : '设置'),
                ),
            ],
          ),
          if (editing) ...[
            const SizedBox(height: 12),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _draft,
              builder: (context, value, _) {
                final candidate = value.text.trim();
                final valid = _validKey.hasMatch(candidate);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: atmo.inputFill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _draft,
                              autofocus: true,
                              enabled: !_saving,
                              obscureText: !_visible,
                              autocorrect: false,
                              enableSuggestions: false,
                              style: TextStyle(
                                fontSize: 14.5,
                                color: colors.onSurface,
                              ),
                              decoration: const InputDecoration(
                                filled: false,
                                isDense: true,
                                hintText: '输入新密钥',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onSubmitted: (_) {
                                if (valid) _save(item);
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: _visible ? '隐藏新密钥' : '显示新密钥',
                            visualDensity: VisualDensity.compact,
                            onPressed: _saving
                                ? null
                                : () => setState(() => _visible = !_visible),
                            icon: Icon(
                              _visible
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 19,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (candidate.isNotEmpty && !valid)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(
                          '请输入不含空格的接口密钥，最多 4096 个 ASCII 字符。',
                          style: TextStyle(fontSize: 12, color: colors.error),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: (_saving || !valid)
                                ? null
                                : () => _save(item),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 42),
                            ),
                            child: _saving
                                ? const CupertinoActivityIndicator(radius: 8)
                                : const Text('保存密钥'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _saving ? null : () => _startEdit(null),
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
