import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../data/agent_api.dart';
import '../data/mobile_session.dart';
import '../widgets/app_theme.dart';
import '../widgets/shared.dart';
import 'api_key_settings_screen.dart';
import 'mobile_connectors_screen.dart';
import 'memory_schedule_screen.dart';

/// Paginated Apple-style Settings Hub mirroring Wintermute Desktop's 6 categories:
/// 连接 / 连接器 / 接口密钥 / 记忆整理 / 外观 / 信息采集.
class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({super.key, required this.session});
  final MobileSession session;

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };

  String _collectionSummary(MobileSession s) {
    if (s.connection == null) return '连接服务后可配置采集项';
    final active = [
      if (s.collecting) '应用活动',
      if (s.locationEnabled) '地点',
      if (s.usageEnabled) '应用时段',
      if (s.screenshots.supported && s.screenshotsEnabled) '截屏',
    ];
    if (active.isEmpty) return '未开启任何采集项';
    return '已开启 · ${active.join(' / ')}';
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(appleRoute(page));
  }

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
                    : '未连接，点击配置服务地址与令牌';

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                  children: [
                    // Group 1: 连接与能力 (mirrors Desktop: 连接 / 连接器 / 接口密钥)
                    SettingsSection(
                      title: '能力与连接',
                      children: [
                        SettingsTile(
                          leading: _CategoryIcon(
                            icon: Icons.cable_rounded,
                            highlight: connected,
                          ),
                          title: '连接',
                          subtitle: connSubtitle,
                          showChevron: true,
                          onTap: () => _push(
                            context,
                            _ConnectionDetailScreen(session: session),
                          ),
                        ),
                        SettingsTile(
                          leading: const _CategoryIcon(
                            icon: Icons.extension_outlined,
                          ),
                          title: '连接器',
                          subtitle: session.connectors.platform.catalog.isEmpty
                              ? '当前平台没有移动连接器'
                              : '管理本机的 ${session.connectors.platform.label} 连接器',
                          showChevron: true,
                          onTap: () => _push(
                            context,
                            MobileConnectorsScreen(session: session),
                          ),
                        ),
                        SettingsTile(
                          leading: const _CategoryIcon(icon: Icons.key_rounded),
                          title: '接口密钥',
                          subtitle: connected ? '管理后端服务接口密钥' : '连接服务后可管理接口密钥',
                          showChevron: true,
                          onTap: () => _push(
                            context,
                            ApiKeySettingsScreen(session: session),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Group 2: 通用 (mirrors Desktop: 记忆整理 / 外观)
                    SettingsSection(
                      title: '通用',
                      children: [
                        SettingsTile(
                          leading: const _CategoryIcon(
                            icon: Icons.event_repeat_rounded,
                          ),
                          title: '记忆整理',
                          subtitle: connected
                              ? '配置跨设备记忆整理周期与时间'
                              : '连接服务后可配置整理计划',
                          showChevron: true,
                          enabled: connected,
                          onTap: () => _push(
                            context,
                            MemoryScheduleScreen(session: session),
                          ),
                        ),
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable: session.themeMode,
                          builder: (context, mode, _) => SettingsTile(
                            leading: const _CategoryIcon(
                              icon: Icons.palette_outlined,
                            ),
                            title: '外观',
                            subtitle: '当前：${_themeLabel(mode)}',
                            showChevron: true,
                            onTap: () => _push(
                              context,
                              _AppearanceSettingsScreen(session: session),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Group 3: 信息采集 (mirrors Desktop: 信息采集)
                    SettingsSection(
                      title: '设备与采集',
                      children: [
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
    });
  }

  Future<void> _connect() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _working = true;
      _feedback = null;
    });
    try {
      final connection = Connection(
        _url.text,
        _deviceId.text,
        _token.text,
        installation: widget.session.installation,
        name: _name.text,
      );
      final ok = await widget.session.configure(connection);
      if (mounted) {
        setState(() {
          _connectionError = !ok;
          _feedback = ok ? '已验证并保存连接' : widget.session.error;
          if (ok) _editing = false;
        });
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _connectionError = true;
          _feedback = e.message;
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
    return AtmosphereScaffold(
      title: '连接',
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) {
                final conn = session.connection;
                final connected = conn != null;
                final showForm = !connected || _editing;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (!showForm)
                      SettingsSection(
                        title: '连接状态',
                        dividers: true,
                        children: [
                          _FactRow(
                            label: '状态',
                            value: session.error != null ? '连接异常' : '已连接',
                            highlight: session.error == null,
                          ),
                          _FactRow(label: '设备名称', value: conn.deviceName),
                          _FactRow(label: '设备 ID', value: conn.deviceId),
                          _FactRow(label: '服务地址', value: conn.url),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                            child: FilledButton.tonal(
                              onPressed: _startEditing,
                              child: const Text('编辑连接'),
                            ),
                          ),
                        ],
                      )
                    else
                      SettingsSection(
                        title: connected ? '编辑服务连接' : '服务连接',
                        footer: '将本机设备 ID 登记到后端，然后填写服务根地址与对应令牌。',
                        dividers: true,
                        children: [
                          _InlineField(
                            label: '服务地址',
                            controller: _url,
                            hintText: 'https://wintermute.example',
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                          ),
                          _InlineField(
                            label: '设备名称',
                            controller: _name,
                            maxLength: 80,
                            textInputAction: TextInputAction.next,
                          ),
                          _InlineField(
                            label: '设备 ID',
                            controller: _deviceId,
                            textInputAction: TextInputAction.next,
                          ),
                          _InlineField(
                            label: '设备令牌',
                            controller: _token,
                            obscureText: _obscureToken,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!_working && session.ready) _connect();
                            },
                            trailing: IconButton(
                              tooltip: _obscureToken ? '显示令牌' : '隐藏令牌',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(
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
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: FilledButton(
                                    onPressed: _working || !session.ready
                                        ? null
                                        : _connect,
                                    child: _working
                                        ? const CupertinoActivityIndicator(
                                            radius: 9,
                                          )
                                        : const Text('验证并保存'),
                                  ),
                                ),
                                if (connected && _editing) ...[
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: _working
                                        ? null
                                        : () => setState(() {
                                            _editing = false;
                                            _feedback = null;
                                          }),
                                    child: const Text('取消'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    if (_feedback != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _feedback!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: _connectionError
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    if (session.deviceStatus.supported) ...[
                      const SizedBox(height: 24),
                      SettingsSection(
                        title: '设备工具',
                        children: [
                          SettingsSwitchTile(
                            title: '允许 Agent 查询设备状态',
                            subtitle:
                                connected && !session.canEnableDeviceStatus
                                ? '请使用 HTTPS 或本机回环地址连接后启用。'
                                : '应用在前台时可返回电量、版本和采集开关。',
                            value: session.deviceStatusEnabled,
                            onChanged: session.canEnableDeviceStatus
                                ? session.setDeviceStatusEnabled
                                : null,
                          ),
                          if (session.deviceStatusError != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                              child: Text(
                                '设备工具连接失败 · ${session.deviceStatusError}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colors.error,
                                ),
                              ),
                            ),
                        ],
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

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

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
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                color: highlight ? colors.primary : colors.onSurface,
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
    return AtmosphereScaffold(
      title: '外观',
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
              children: [
                SettingsSection(
                  title: '主题',
                  footer: '外观偏好仅保存在当前设备上，切换后立即生效。',
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ValueListenableBuilder<ThemeMode>(
                            valueListenable: widget.session.themeMode,
                            builder: (context, selected, _) =>
                                AppleSegmentedControl<ThemeMode>(
                                  items: const [
                                    (ThemeMode.system, '跟随系统'),
                                    (ThemeMode.light, '浅色'),
                                    (ThemeMode.dark, '深色'),
                                  ],
                                  selected: selected,
                                  enabled: !_saving,
                                  onChanged: _setTheme,
                                ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.error,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
  Future<void> _nameLocation() async {
    var name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: const Text(
            '命名当前位置',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          content: TextField(
            autofocus: true,
            maxLength: 40,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '地点名称',
              hintText: '例如：公司',
              counterText: '',
            ),
            onChanged: (text) => update(() => name = text.trim()),
            onSubmitted: (_) {
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: name.isEmpty
                  ? null
                  : () => Navigator.pop(context, name),
              style: FilledButton.styleFrom(minimumSize: const Size(76, 40)),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (mounted && result != null) {
      await widget.session.nameCurrentLocation(result);
    }
  }

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
                          '请先在「连接」中配置并验证后端服务，再开启设备信息采集。',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    SettingsSection(
                      title: '应用与地点',
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SettingsSwitchTile(
                              title: '记录应用活动',
                              subtitle: '页面或前后台状态变化时上传。',
                              value: session.collecting,
                              onChanged: connected
                                  ? session.setCollecting
                                  : null,
                            ),
                            if (session.lastUpload != null ||
                                session.pending.isNotEmpty ||
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
                                    if (session.lastUpload != null)
                                      Text(
                                        '最近上传 ${session.lastUpload!.replaceFirst('T', ' ').split('.').first}',
                                        style: TextStyle(
                                          color: colors.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (session.pending.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          '待上传 ${session.pending.length} 条',
                                          style: TextStyle(
                                            color: colors.onSurfaceVariant,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                    if (session.collectionError != null) ...[
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SignalControl(
                              title: '地点变化',
                              description: '进入已命名地点时分享名称，其他位置仅分享约 1 公里精度的坐标。',
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
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (!session.backgroundLocation)
                                          _SubtleActionButton(
                                            label: '允许后台定位',
                                            onTap: () =>
                                                session.requestSignalAccess(
                                                  'backgroundLocation',
                                                ),
                                          ),
                                        _SubtleActionButton(
                                          icon: Icons.add_location_alt_outlined,
                                          label: '命名当前位置',
                                          onTap: session.canNameLocation
                                              ? _nameLocation
                                              : null,
                                        ),
                                      ],
                                    ),
                                    if (!session.canNameLocation)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          '取得近期、精度足够的位置后即可命名。',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            if (session.placeNames.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  16,
                                ),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final name in session.placeNames)
                                      ApplePillChip(
                                        label: name,
                                        deleteTooltip: '移除地点「$name」',
                                        onDelete: () =>
                                            session.removePlace(name),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        _SignalControl(
                          title: '其他 App 使用时段',
                          description: '分享进入前台的应用名称、起止时间和停留时长。',
                          source: 'usage',
                          enabled: session.usageEnabled,
                          access: session.usageAccess,
                          lastObservation: session.lastUsageLabel,
                          session: session,
                        ),
                      ],
                    ),
                    if (session.screenshots.supported) ...[
                      const SizedBox(height: 24),
                      SettingsSection(
                        title: '屏幕截图',
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SettingsSwitchTile(
                                title: '定时截屏',
                                subtitle:
                                    session.screenshotAccess == 'unsupported'
                                    ? '当前安装包不支持系统屏幕共享。'
                                    : session.screenshotAccess ==
                                          'usageRequired'
                                    ? '先开启「其他 App 使用时段」并授予使用情况访问权。'
                                    : session.screenshots.platform == 'ios'
                                    ? '系统共享屏幕后，在使用其他应用时采集画面并上传。iOS 不提供可靠的应用名称。'
                                    : '系统共享屏幕后，在使用其他应用时将截图和应用信息发送给 Agent。',
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
                    ],
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
  const _SubtleActionButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: enabled
                      ? colors.primary
                      : colors.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? colors.primary
                      : colors.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ],
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
      'unsupported' when source == 'usage' => '当前设备不支持。此项适用于 Android。',
      'unsupported' => '当前设备不支持地点采集。',
      'disabled' when enabled && source == 'location' => '系统定位服务已关闭。',
      'blocked' when enabled => '需要在系统设置中允许访问。',
      _ when needsAccess =>
        source == 'usage' ? '等待系统授予使用情况访问权。' : '等待系统授予定位权限。',
      _ => description,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSwitchTile(
          title: title,
          subtitle: subtitle,
          value: enabled,
          onChanged: session.connection == null || (unsupported && !enabled)
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
