import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'pairing_scanner.dart';
import '../data/agent_api.dart';
import '../data/mobile_session.dart';
import '../widgets/app_theme.dart';
import '../widgets/shared.dart';
import 'memory_screen.dart';
import 'mobile_connectors_screen.dart';

/// Settings for this device's connection, connectors, appearance and collection.
class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({super.key, required this.session});
  final MobileSession session;

  String _themeLabel(ThemeMode mode) => mode == ThemeMode.dark ? '深色' : '浅色';

  String _collectionSummary(MobileSession s) {
    if (s.connection == null) return '连接服务后可配置采集项';
    final active = [
      if (s.collecting) '前台应用活动',
      if (s.locationEnabled) '定时位置',
      if (s.locationEnabled && s.networkEnabled) 'Wi-Fi',
      if (s.screenshots.supported && s.screenshotsEnabled) '截屏',
    ];
    if (active.isEmpty) return '未开启任何采集项';
    return '已开启 · ${active.join(' / ')}';
  }

  Future<void> _push(BuildContext context, Widget page) =>
      Navigator.of(context).push<void>(appleRoute(page));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AtmosphereScaffold(
      title: '设置',
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) {
                if (!session.ready || session.installation == null) {
                  return Center(
                    child: Text(
                      session.error ?? '正在读取设备身份…',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  );
                }
                final conn = session.connection;
                final connected = conn != null;
                final connSubtitle = connected
                    ? '已连接 · ${conn.deviceName}'
                    : '未连接，点击配对设备';

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                  children: [
                    SettingsSection(
                      title: '设备与采集',
                      children: [
                        SettingsTile(
                          leading: _CategoryIcon(
                            icon: Icons.cable_rounded,
                            highlight: connected,
                          ),
                          title: '设备配对',
                          subtitle: connSubtitle,
                          showChevron: true,
                          onTap: () => _push(
                            context,
                            _ConnectionDetailScreen(session: session),
                          ),
                        ),
                        SettingsTile(
                          leading: const _CategoryIcon(
                            icon: Icons.sensors_rounded,
                          ),
                          title: '信息采集',
                          subtitle: _collectionSummary(session),
                          showChevron: true,
                          onTap: () => _push(
                            context,
                            _CollectionSettingsScreen(session: session),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    SettingsSection(
                      title: '能力扩展',
                      children: [
                        SettingsTile(
                          leading: const _CategoryIcon(
                            icon: Icons.extension_outlined,
                          ),
                          title: '连接器',
                          subtitle: session.connectors.platform.catalog.isEmpty
                              ? '查看 Android 与 iOS 连接器'
                              : '管理本机的 ${session.connectors.platform.label} 连接器',
                          showChevron: true,
                          onTap: () => _push(
                            context,
                            MobileConnectorsScreen(session: session),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    SettingsSection(
                      title: '通用',
                      children: [
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable: session.themeMode,
                          builder: (context, mode, _) => SettingsTile(
                            leading: const _CategoryIcon(
                              icon: Icons.settings_outlined,
                            ),
                            title: '应用设置',
                            subtitle: '切换浅色或深色界面主题',
                            trailing: Text(
                              _themeLabel(mode),
                              style: TextStyle(
                                fontSize: 13.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            showChevron: true,
                            onTap: () => _push(
                              context,
                              _AppearanceSettingsScreen(session: session),
                            ),
                          ),
                        ),
                        if (Theme.of(context).platform == TargetPlatform.iOS)
                          SettingsTile(
                            leading: const _CategoryIcon(
                              icon: Icons.bookmarks_outlined,
                            ),
                            title: '记忆',
                            showChevron: true,
                            onTap: () async {
                              session.page('记忆');
                              await _push(context, const MemoryScreen());
                              if (context.mounted &&
                                  ModalRoute.isCurrentOf(context) == true) {
                                session.page('连接与采集');
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.icon, this.highlight = false});
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: highlight
            ? colors.primary.withValues(alpha: 0.14)
            : atmo.inputFill,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        icon,
        size: 18,
        color: highlight ? colors.primary : colors.onSurfaceVariant,
      ),
    );
  }
}

// =============================================================================
// Sub-page 1: 连接 (Connection)
// =============================================================================
class _ConnectionDetailScreen extends StatefulWidget {
  const _ConnectionDetailScreen({required this.session});
  final MobileSession session;

  @override
  State<_ConnectionDetailScreen> createState() =>
      _ConnectionDetailScreenState();
}

class _ConnectionDetailScreenState extends State<_ConnectionDetailScreen> {
  late final _url = TextEditingController(text: widget.session.connection?.url);
  late final _deviceId = TextEditingController(
    text:
        widget.session.connection?.deviceId ??
        'mobile-${widget.session.installation}',
  );
  late final _name = TextEditingController(
    text: widget.session.connection?.deviceName ?? Connection.defaultDeviceName,
  );
  late final _token = TextEditingController(
    text: widget.session.connection?.token,
  );
  final _pairValue = TextEditingController();
  bool _manual = false;
  bool _editing = false;
  bool _obscureToken = true;
  bool _working = false;
  bool _connectionError = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _editing = widget.session.connection == null;
  }

  @override
  void dispose() {
    _url.dispose();
    _deviceId.dispose();
    _name.dispose();
    _token.dispose();
    _pairValue.dispose();
    super.dispose();
  }

  void _startEditing() {
    final conn = widget.session.connection;
    _url.text = conn?.url ?? '';
    _deviceId.text = conn?.deviceId ?? 'mobile-${widget.session.installation}';
    _name.text = conn?.deviceName ?? Connection.defaultDeviceName;
    _token.text = conn?.token ?? '';
    setState(() {
      _feedback = null;
      _connectionError = false;
      _editing = true;
      _manual = conn != null;
      _obscureToken = true;
      _pairValue.clear();
    });
  }

  void _cancelEditing() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editing = false;
      _feedback = null;
      _connectionError = false;
    });
  }

  Future<void> _scan() async {
    final value = await Navigator.of(
      context,
    ).push<String>(appleRoute(const PairingScanner()));
    if (!mounted || value == null) return;
    _pairValue.text = value;
    await _connect();
  }

  Future<void> _connect() async {
    final session = widget.session;
    if (_working || !session.ready) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _working = true;
      _feedback = null;
    });
    try {
      final installation = session.installation;
      if (!_manual && installation == null) {
        throw const FormatException('设备身份尚未就绪，请重新打开应用后重试。');
      }
      final connection = _manual
          ? Connection(
              _url.text,
              _deviceId.text,
              _token.text,
              installation: installation,
              name: _name.text,
              followsSystemName: false,
            )
          : await session.api.pair(
              _pairValue.text,
              installation: installation!,
              followsSystemName: session.connection == null
                  ? true
                  : session.connection!.followsSystemName,
              name:
                  session.connection?.deviceName ??
                  await session.signals.pairingName(),
            );
      final ok = await session.configure(connection);
      if (ok) session.api.finishPairing();
      if (mounted) {
        setState(() {
          _connectionError = !ok;
          _feedback = ok ? '已验证并保存连接' : session.error;
          if (ok) {
            _editing = false;
            _pairValue.clear();
          }
        });
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _connectionError = true;
          _feedback = e.message;
        });
      }
    } on ApiError catch (e) {
      if (!_manual && e.status == 409) session.api.finishPairing();
      if (mounted) {
        setState(() {
          _connectionError = true;
          _feedback = switch (e.status) {
            403 => '配对链接无效、已过期或已使用',
            404 => '后端尚未启用设备配对',
            409 => '设备 ID 冲突，请重新配对',
            429 => '尝试次数过多，请稍后再试',
            _ => '配对失败，请检查服务地址后重试',
          };
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _connectionError = true;
          _feedback = '连接失败，请检查网络和服务地址后重试';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final conn = session.connection;
        final connected = conn != null;
        final showForm = !connected || _editing;
        final platform = DevicePlatform.current?.label ?? '未知';
        final healthy = session.error == null;

        return AtmosphereScaffold(
          title: connected && _editing ? '编辑连接' : '设备配对',
          actions: [
            if (connected && _editing)
              TextButton(
                onPressed: _working ? null : _cancelEditing,
                child: const Text('取消'),
              ),
          ],
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (!showForm) ...[
                      SettingsSection(
                        title: '当前连接',
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color:
                                        (healthy
                                                ? colors.primary
                                                : colors.error)
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    healthy
                                        ? Icons.cloud_done_outlined
                                        : Icons.cloud_off_outlined,
                                    size: 20,
                                    color: healthy
                                        ? colors.primary
                                        : colors.error,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        conn.deviceName,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: colors.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        conn.url,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _ConnectionStatusBadge(healthy: healthy),
                              ],
                            ),
                          ),
                          _FactRow(label: '设备平台', value: platform),
                          _FactRow(label: '设备 ID', value: conn.deviceId),
                          _FactRow(label: '服务地址', value: conn.url),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: _startEditing,
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.primary.withValues(
                              alpha: 0.12,
                            ),
                            foregroundColor: colors.primary,
                          ),
                          child: const Text('编辑连接'),
                        ),
                      ),
                    ] else ...[
                      AppleSegmentedControl<bool>(
                        items: const [(false, '配对链接'), (true, '手动配置')],
                        selected: _manual,
                        enabled: !_working,
                        onChanged: (manual) => setState(() {
                          _manual = manual;
                          _feedback = null;
                        }),
                      ),
                      const SizedBox(height: 18),
                      if (!_manual) ...[
                        SettingsSection(
                          title: '配对设备',
                          footer: '在后端管理面板点击「添加设备」，粘贴一次性配对链接或直接扫码即可自动完成配置。',
                          children: [
                            _InlineField(
                              label: '配对链接',
                              keyboardType: TextInputType.url,
                              controller: _pairValue,
                              hintText: '粘贴 https://... 配对链接',
                              enabled: !_working,
                              onChanged: (value) {
                                if (pairingAddress(value) != null) _connect();
                              },
                              textInputAction: TextInputAction.go,
                              onSubmitted: (_) {
                                if (!_working && session.ready) _connect();
                              },
                            ),
                            SettingsTile(
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(
                                  Icons.qr_code_scanner_rounded,
                                  size: 18,
                                  color: colors.primary,
                                ),
                              ),
                              title: '扫码配对',
                              subtitle: '使用相机扫描管理面板上的二维码',
                              showChevron: true,
                              enabled: !_working && session.ready,
                              onTap: _scan,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _working || !session.ready
                                ? null
                                : _connect,
                            child: _working
                                ? const CupertinoActivityIndicator(radius: 9)
                                : const Text('配对并连接'),
                          ),
                        ),
                      ] else ...[
                        SettingsSection(
                          title: '服务与凭据',
                          footer: '填写后端服务根地址（不含 /v1 或其他路径）、设备标识与访问令牌。',
                          children: [
                            _InlineField(
                              label: '服务地址',
                              controller: _url,
                              hintText: 'https://purin.example',
                              keyboardType: TextInputType.url,
                              enabled: !_working,
                              textInputAction: TextInputAction.next,
                            ),
                            _InlineField(
                              label: '设备名称',
                              controller: _name,
                              hintText: Connection.defaultDeviceName,
                              maxLength: 80,
                              enabled: !_working,
                              textInputAction: TextInputAction.next,
                            ),
                            _InlineField(
                              label: '设备 ID',
                              controller: _deviceId,
                              hintText: 'mobile-device',
                              enabled: !_working,
                              textInputAction: TextInputAction.next,
                            ),
                            _InlineField(
                              label: '设备令牌',
                              controller: _token,
                              hintText: 'Bearer token',
                              obscureText: _obscureToken,
                              enabled: !_working,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) {
                                if (!_working && session.ready) _connect();
                              },
                              trailing: IconButton(
                                tooltip: _obscureToken ? '显示令牌' : '隐藏令牌',
                                visualDensity: VisualDensity.compact,
                                onPressed: _working
                                    ? null
                                    : () => setState(
                                        () => _obscureToken = !_obscureToken,
                                      ),
                                icon: Icon(
                                  _obscureToken
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 19,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            _InlineReadOnlyField(
                              label: '设备平台',
                              value: platform,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _working || !session.ready
                                ? null
                                : _connect,
                            child: _working
                                ? const CupertinoActivityIndicator(radius: 9)
                                : const Text('验证并保存'),
                          ),
                        ),
                      ],
                    ],
                    if (_feedback != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: _connectionError
                                  ? colors.errorContainer
                                  : atmo.cardFill,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _connectionError
                                    ? colors.error.withValues(alpha: 0.25)
                                    : atmo.hairline,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _connectionError
                                      ? Icons.error_outline_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 18,
                                  color: _connectionError
                                      ? colors.error
                                      : colors.primary,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    _feedback!,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: _connectionError
                                          ? colors.onErrorContainer
                                          : colors.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (!showForm) ...[
                      const SizedBox(height: 24),
                      _OnlineDevicesSection(
                        key: ValueKey(conn.scope),
                        session: session,
                        connection: conn,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OnlineDevicesSection extends StatefulWidget {
  const _OnlineDevicesSection({
    super.key,
    required this.session,
    required this.connection,
  });

  final MobileSession session;
  final Connection connection;

  @override
  State<_OnlineDevicesSection> createState() => _OnlineDevicesSectionState();
}

class _OnlineDevicesSectionState extends State<_OnlineDevicesSection> {
  List<OnlineDevice> _devices = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load(initial: true));
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool initial = false, bool manual = false}) async {
    if (_refreshing) return;
    if (manual && mounted) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    } else if (initial) {
      _refreshing = true;
    } else {
      _refreshing = true;
    }
    try {
      final items = await widget.session.api.onlineDevices(widget.connection);
      if (!mounted) return;
      setState(() {
        _devices = items;
        _error = null;
        _loading = false;
        _refreshing = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.status == 404 ? '后端尚未支持在线设备查询' : '读取在线设备信息失败，请稍后重试';
        _loading = false;
        _refreshing = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = '读取在线设备信息失败，请检查网络连接';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  IconData _iconFor(OnlineDevice item) => switch (item.resolvedKind) {
    'mobile' => Icons.smartphone_rounded,
    'esp32' => Icons.memory_rounded,
    'desktop' =>
      item.platform == 'macos'
          ? Icons.laptop_mac_rounded
          : Icons.desktop_windows_rounded,
    _ => Icons.dns_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    final onlineTone = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF45D4A6)
        : const Color(0xFF16855E);
    final title = !_loading && _error == null
        ? '在线设备 · ${_devices.length}'
        : '在线设备';

    Widget content;
    if (_loading) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            const CupertinoActivityIndicator(radius: 8.5),
            const SizedBox(width: 10),
            Text(
              '正在获取在线设备信息…',
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    } else if (_error != null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Text(
          _error!,
          style: TextStyle(fontSize: 14, color: colors.error),
        ),
      );
    } else if (_devices.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Text(
          '当前暂无在线设备',
          style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
        ),
      );
    } else {
      final rows = <Widget>[];
      for (var i = 0; i < _devices.length; i++) {
        final item = _devices[i];
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: item.isCurrent
                        ? colors.primary.withValues(alpha: 0.14)
                        : atmo.inputFill,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    _iconFor(item),
                    size: 18,
                    color: item.isCurrent
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          if (item.isCurrent) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '本机',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${item.platformLabel} · ${item.deviceId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: onlineTone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: onlineTone,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '在线',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: onlineTone,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        if (i < _devices.length - 1) {
          rows.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 0.9, thickness: 0.9, color: atmo.hairline),
            ),
          );
        }
      }
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: atmo.sectionHeader,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              SizedBox(
                width: 30,
                height: 30,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: '刷新在线设备',
                  onPressed: _loading || _refreshing
                      ? null
                      : () => _load(manual: true),
                  icon: _refreshing && !_loading
                      ? const CupertinoActivityIndicator(radius: 7.5)
                      : Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: atmo.sectionHeader,
                        ),
                ),
              ),
            ],
          ),
        ),
        GlassCard(
          radius: 26,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: content,
        ),
      ],
    );
  }
}

class _ConnectionStatusBadge extends StatelessWidget {
  const _ConnectionStatusBadge({required this.healthy});
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = healthy ? const Color(0xFF16855E) : colors.error;
    final darkFg = healthy ? const Color(0xFF45D4A6) : colors.error;
    final tone = Theme.of(context).brightness == Brightness.dark ? darkFg : fg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6.5,
            height: 6.5,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            healthy ? '已连接' : '连接异常',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineReadOnlyField extends StatelessWidget {
  const _InlineReadOnlyField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 15, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Sub-page 5: 外观 (Appearance)
// =============================================================================
class _AppearanceSettingsScreen extends StatefulWidget {
  const _AppearanceSettingsScreen({required this.session});
  final MobileSession session;

  @override
  State<_AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<_AppearanceSettingsScreen> {
  static const _options = [
    (
      mode: ThemeMode.light,
      label: '浅色',
      icon: Icons.light_mode_rounded,
      description: '始终使用明亮通透的云雾浅色背景与毛玻璃卡片表面。',
    ),
    (
      mode: ThemeMode.dark,
      label: '深色',
      icon: Icons.dark_mode_rounded,
      description: '始终使用柔和低眩光的夜空深色背景与深色卡片表面。',
    ),
  ];

  bool _saving = false;
  String? _error;

  Future<void> _setTheme(ThemeMode mode) async {
    if (_saving || widget.session.themeMode.value == mode) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.setTheme(mode);
    } catch (_) {
      if (mounted) setState(() => _error = '外观设置保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return AtmosphereScaffold(
      title: '应用设置',
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: widget.session.themeMode,
              builder: (context, selected, _) {
                final active = _options.firstWhere(
                  (item) => item.mode == selected,
                  orElse: () => _options.first,
                );
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                  children: [
                    SettingsSection(
                      title: '界面主题',
                      footer: '外观偏好仅保存在当前设备上，切换后立即生效。',
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: LayoutBuilder(
                            builder: (context, bounds) {
                              final compact =
                                  bounds.maxWidth < 280 || textScale > 1.45;
                              if (compact) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < _options.length;
                                      i++
                                    ) ...[
                                      if (i > 0) const SizedBox(height: 10),
                                      _ThemeOptionCard(
                                        mode: _options[i].mode,
                                        label: _options[i].label,
                                        icon: _options[i].icon,
                                        selected: selected == _options[i].mode,
                                        enabled: !_saving,
                                        horizontal: true,
                                        onTap: () =>
                                            _setTheme(_options[i].mode),
                                      ),
                                    ],
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < _options.length; i++) ...[
                                    if (i > 0) const SizedBox(width: 10),
                                    Expanded(
                                      child: _ThemeOptionCard(
                                        mode: _options[i].mode,
                                        label: _options[i].label,
                                        icon: _options[i].icon,
                                        selected: selected == _options[i].mode,
                                        enabled: !_saving,
                                        onTap: () =>
                                            _setTheme(_options[i].mode),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 13, 20, 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1.5),
                                child: Icon(
                                  active.icon,
                                  size: 17,
                                  color: colors.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  active.description,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(fontSize: 13, color: colors.error),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.horizontal = false,
  });

  final ThemeMode mode;
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    final borderColor = selected ? colors.primary : atmo.hairline;
    final cardFill = selected
        ? colors.primary.withValues(alpha: 0.08)
        : atmo.inputFill.withValues(alpha: 0.65);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Material(
        color: cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: borderColor, width: selected ? 1.6 : 0.9),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: horizontal
                ? Row(
                    children: [
                      SizedBox(
                        width: 76,
                        height: 52,
                        child: _ThemePreviewGraphic(mode: mode),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        icon,
                        size: 16,
                        color: selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      _ThemeCheckIndicator(selected: selected),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 68,
                        child: _ThemePreviewGraphic(mode: mode),
                      ),
                      const SizedBox(height: 9),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: selected
                                      ? colors.primary
                                      : colors.onSurface,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            _ThemeCheckIndicator(selected: selected),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ThemeCheckIndicator extends StatelessWidget {
  const _ThemeCheckIndicator({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (selected) {
      return Icon(Icons.check_circle_rounded, size: 16, color: colors.primary);
    }
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.outline, width: 1.2),
      ),
    );
  }
}

class _ThemePreviewGraphic extends StatelessWidget {
  const _ThemePreviewGraphic({required this.mode});
  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    final atmo = AppAtmosphere.of(context);
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: atmo.hairline, width: 0.8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11.2),
          child: _MockChatCanvas(dark: mode == ThemeMode.dark),
        ),
      ),
    );
  }
}

class _MockChatCanvas extends StatelessWidget {
  const _MockChatCanvas({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final bg = dark
        ? const [Color(0xFF141B26), Color(0xFF172334)]
        : const [Color(0xFFF7F6F2), Color(0xFFE9F2FC)];
    final pill = dark ? const Color(0xE0223042) : const Color(0xEBFFFFFF);
    final assistant = dark ? const Color(0xE6202D3E) : const Color(0xF5FFFFFF);
    final user = dark ? const Color(0xFF233E5E) : const Color(0xFFD8EAFC);
    final accent = dark ? const Color(0xFF6BB0FF) : const Color(0xFF3983DF);
    final border = dark ? const Color(0x24C8DEF8) : const Color(0xFFDCE6F2);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: bg,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 22,
                height: 5,
                decoration: BoxDecoration(
                  color: pill,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: border, width: 0.6),
                ),
              ),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.62,
                child: Container(
                  height: 9,
                  decoration: BoxDecoration(
                    color: assistant,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: border, width: 0.6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.52,
                child: Container(
                  height: 9,
                  decoration: BoxDecoration(
                    color: user,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Container(
              height: 10,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: pill,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: border, width: 0.6),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Sub-page 6: 信息采集 (Collection)
// =============================================================================
class _CollectionSettingsScreen extends StatefulWidget {
  const _CollectionSettingsScreen({required this.session});
  final MobileSession session;

  @override
  State<_CollectionSettingsScreen> createState() =>
      _CollectionSettingsScreenState();
}

class _CollectionSettingsScreenState extends State<_CollectionSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);

    return AtmosphereScaffold(
      title: '信息采集',
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) {
                final connected = session.connection != null;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                  children: [
                    if (!connected) ...[
                      GlassCard(
                        radius: 22,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Text(
                          '请先在「设备配对」中配置并验证后端服务，再开启设备信息采集。',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    SettingsSection(
                      title: session.screenshots.supported ? '应用与截图' : '应用活动',
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SignalControl(
                              title: '记录前台应用活动',
                              description:
                                  session.screenshots.platform != 'android'
                                  ? '记录 Purin 的页面和前后台切换。'
                                  : session.usageEnabled &&
                                        session.usageAccess == 'granted' &&
                                        !session.backgroundUsage
                                  ? '记录 Purin 活动，其他应用时段会在返回时补传。'
                                  : '记录 Purin 活动，切走其他应用时同步名称、起止时间和停留时长。',
                              source: 'usage',
                              enabled: session.collecting,
                              access: session.usageAccess,
                              lastObservation: session.lastUsageLabel,
                              session: session,
                            ),
                            if (session.pendingCollectionCount > 0 ||
                                session.collectionError != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  14,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (session.pendingCollectionCount > 0)
                                      Text(
                                        '待上传 ${session.pendingCollectionCount} 条',
                                        style: TextStyle(
                                          color: colors.onSurfaceVariant,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    if (session.collectionError != null) ...[
                                      if (session.pendingCollectionCount > 0)
                                        const SizedBox(height: 4),
                                      Text(
                                        '采集上传失败 · ${session.collectionError}',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: colors.error,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      _SubtleActionButton(
                                        label: '重试上传',
                                        onTap: session.sync,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (session.screenshots.supported)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SettingsSwitchTile(
                                title: session.screenshots.platform == 'android'
                                    ? '采集前台应用截图'
                                    : '定时截屏',
                                subtitle:
                                    session.screenshotAccess == 'unsupported'
                                    ? '当前安装包不支持系统屏幕共享。'
                                    : session.screenshotAccess ==
                                          'usageRequired'
                                    ? '先开启「记录前台应用活动」并授予使用情况访问权。'
                                    : session.screenshots.platform == 'ios'
                                    ? '系统共享屏幕后，在使用其他应用时采集画面并上传。iOS 不提供可靠的应用名称。'
                                    : '屏幕共享期间，同一应用连续在前台满 10 分钟截一次，切走后随该次活动上传。',
                                value: session.screenshotsEnabled,
                                onChanged:
                                    !connected ||
                                        (!session.screenshotsEnabled &&
                                            [
                                              'usageRequired',
                                              'unsupported',
                                              'unavailable',
                                            ].contains(
                                              session.screenshotAccess,
                                            ))
                                    ? null
                                    : session.setScreenshots,
                              ),
                              if (session.screenshotsEnabled)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    16,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (session.screenshots.platform !=
                                          'android') ...[
                                        Text(
                                          '截图间隔',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: atmo.sectionHeader,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        AppleSegmentedControl<int>(
                                          items: const [
                                            (60, '1 分钟'),
                                            (300, '5 分钟'),
                                            (900, '15 分钟'),
                                          ],
                                          selected: session.screenshotInterval,
                                          onChanged:
                                              session.setScreenshotInterval,
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      Row(
                                        children: [
                                          if (session.screenshotAccess ==
                                              'active')
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 7,
                                                  height: 7,
                                                  decoration: BoxDecoration(
                                                    color: colors.primary,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '屏幕共享中',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            )
                                          else if ([
                                            'ready',
                                            'denied',
                                          ].contains(session.screenshotAccess))
                                            _SubtleActionButton(
                                              label: '开始系统屏幕共享',
                                              onTap: session
                                                  .startScreenshotCapture,
                                            ),
                                          if (session.pendingScreenshots >
                                              0) ...[
                                            const SizedBox(width: 12),
                                            Text(
                                              '待上传截图 ${session.pendingScreenshots} 张',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              if (session.screenshotError != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    14,
                                  ),
                                  child: Text(
                                    session.screenshotError!,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colors.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SettingsSection(
                      title: '位置与网络',
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SignalControl(
                              title: '定时采集位置',
                              description: '每 20 分钟采集位置和定位误差，由后端筛选并解析地点。',
                              source: 'location',
                              enabled: session.locationEnabled,
                              access: session.locationAccess,
                              lastObservation: session.lastLocationLabel,
                              session: session,
                            ),
                            if (session.locationEnabled &&
                                session.locationAccess == 'granted')
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  14,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      session.backgroundLocation
                                          ? '后台定位已授权'
                                          : '当前为使用期间定位',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                    if (!session.backgroundLocation)
                                      _SubtleActionButton(
                                        label: '允许后台定位',
                                        onTap: () =>
                                            session.requestSignalAccess(
                                              'backgroundLocation',
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        SettingsSwitchTile(
                          title: '定时采集网络',
                          subtitle: '随位置记录 Wi-Fi 连接状态和名称。',
                          value:
                              session.locationEnabled && session.networkEnabled,
                          onChanged: connected && session.locationEnabled
                              ? session.setNetworkEnabled
                              : null,
                        ),
                      ],
                    ),
                    if (session.signalError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            session.signalError!,
                            style: TextStyle(fontSize: 13, color: colors.error),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineField extends StatelessWidget {
  const _InlineField({
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.maxLength,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 14, 6),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: colors.onSurface,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              obscureText: obscureText,
              autocorrect: false,
              enableSuggestions: !obscureText,
              maxLength: maxLength,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              enabled: enabled,
              style: TextStyle(fontSize: 15, color: colors.onSurface),
              decoration: InputDecoration(
                filled: false,
                counterText: '',
                isDense: true,
                hintText: hintText,
                hintStyle: TextStyle(
                  fontSize: 14.5,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SubtleActionButton extends StatelessWidget {
  const _SubtleActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Material(
      color: colors.primary.withValues(alpha: enabled ? 0.12 : 0.05),
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled
                  ? colors.primary
                  : colors.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalControl extends StatelessWidget {
  const _SignalControl({
    required this.title,
    required this.description,
    required this.source,
    required this.enabled,
    required this.access,
    required this.lastObservation,
    required this.session,
  });

  final String title, description, source, access;
  final bool enabled;
  final String? lastObservation;
  final MobileSession session;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unsupported = access == 'unsupported';
    final needsAccess = enabled && access != 'granted' && !unsupported;
    final systemSettings = access == 'blocked' || access == 'disabled';
    final subtitle = switch (access) {
      'unsupported' when source == 'usage' => description,
      'unsupported' => '当前设备不支持地点采集。',
      'disabled' when enabled && source == 'location' => '系统定位服务已关闭。',
      'blocked' when enabled => '需要在系统设置中允许访问。',
      _ when needsAccess =>
        source == 'usage'
            ? '正在记录 Purin 活动。授权使用情况访问权后，会同时记录其他应用的使用时段。'
            : '等待系统授予定位权限。',
      _ => description,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSwitchTile(
          title: title,
          subtitle: subtitle,
          value: enabled,
          onChanged:
              session.connection == null ||
                  (unsupported && source != 'usage' && !enabled)
              ? null
              : (value) => session.setSignalEnabled(source, value),
        ),
        if (needsAccess ||
            (enabled && access == 'granted' && lastObservation != null))
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (needsAccess)
                  _SubtleActionButton(
                    label: systemSettings ? '打开系统设置' : '前往授权',
                    onTap: () => systemSettings
                        ? session.openSignalSettings(source)
                        : session.requestSignalAccess(source),
                  ),
                if (enabled && access == 'granted' && lastObservation != null)
                  Text(
                    '最近记录 · $lastObservation',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
