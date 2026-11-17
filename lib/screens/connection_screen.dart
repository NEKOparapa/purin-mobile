import 'package:flutter/material.dart';
import '../data/agent_api.dart';
import '../data/mobile_session.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, required this.session});
  final MobileSession session;
  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final _url = TextEditingController(text: widget.session.connection?.url);
  late final _terminal = TextEditingController(
    text: widget.session.connection?.terminal ?? 'http-mobile',
  );
  late final _token = TextEditingController(
    text: widget.session.connection?.token,
  );
  bool _working = false;
  bool _savingTheme = false;
  String? _themeError;
  bool _connectionError = false;
  String? _feedback;
  @override
  void dispose() {
    _url.dispose();
    _terminal.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _setTheme(ThemeMode mode) async {
    if (_savingTheme || widget.session.themeMode.value == mode) return;
    setState(() {
      _savingTheme = true;
      _themeError = null;
    });
    try {
      await widget.session.setTheme(mode);
    } catch (_) {
      if (mounted) setState(() => _themeError = '外观设置保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _savingTheme = false);
    }
  }

  Future<void> _connect() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _working = true;
      _feedback = null;
    });
    try {
      final connection = Connection(_url.text, _terminal.text, _token.text);
      final ok = await widget.session.configure(connection);
      if (mounted) {
        setState(() {
          _connectionError = !ok;
          _feedback = ok ? '已验证并保存连接' : widget.session.error;
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

  Future<void> _nameLocation() async {
    var name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          scrollable: true,
          title: const Text('命名当前位置'),
          content: TextField(
            autofocus: true,
            maxLength: 40,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '地点名称',
              hintText: '例如：公司',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接与采集'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                children: [
                  const Text(
                    '外观',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: session.themeMode,
                    builder: (context, selected, _) => Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final (mode, label) in const [
                          (ThemeMode.system, '跟随系统'),
                          (ThemeMode.light, '浅色'),
                          (ThemeMode.dark, '深色'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            showCheckmark: true,
                            selected: mode == selected,
                            onSelected: _savingTheme
                                ? null
                                : (_) => _setTheme(mode),
                          ),
                      ],
                    ),
                  ),
                  if (_themeError != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _themeError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 24),
                  const Text(
                    '服务连接',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 23,
                      letterSpacing: -.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '服务地址',
                      hintText: 'https://wintermute.example',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _terminal,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '终端 ID'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _token,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '终端令牌'),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _working || !session.ready ? null : _connect,
                      child: Text(_working ? '正在验证…' : '验证并保存'),
                    ),
                  ),
                  if (_feedback != null) ...[
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _feedback!,
                        style: TextStyle(
                          color: _connectionError
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (session.deviceStatus.supported) ...[
                    const SizedBox(height: 14),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('允许 Agent 查询设备状态'),
                      subtitle: Text(
                        session.connection != null &&
                                !session.canEnableDeviceStatus
                            ? '请使用 HTTPS 或本机回环地址连接后启用。'
                            : '应用在前台时可返回电量、版本和采集开关。',
                      ),
                      value: session.deviceStatusEnabled,
                      onChanged: session.canEnableDeviceStatus
                          ? session.setDeviceStatusEnabled
                          : null,
                    ),
                    if (session.deviceStatusError != null)
                      Text(
                        '终端工具连接失败 · ${session.deviceStatusError}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 24),
                  const Text(
                    '活动采集',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 22,
                      letterSpacing: -.6,
                    ),
                  ),
                  SwitchListTile.adaptive(
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('记录应用活动', style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                      '页面或前后台状态变化时上传。',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: session.collecting,
                    onChanged: session.connection == null
                        ? null
                        : session.setCollecting,
                  ),
                  if (session.lastUpload != null)
                    Text(
                      '最近上传 ${session.lastUpload!.replaceFirst('T', ' ').split('.').first}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  if (session.pending.isNotEmpty)
                    Text(
                      '待上传 ${session.pending.length} 条',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  if (session.collectionError != null) ...[
                    Text(
                      '采集上传失败 · ${session.collectionError}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: session.sync,
                        child: const Text('重试上传'),
                      ),
                    ),
                  ],
                  const Divider(),
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
                      session.locationAccess == 'granted') ...[
                    if (!session.backgroundLocation)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              session.requestSignalAccess('backgroundLocation'),
                          child: const Text('允许后台定位'),
                        ),
                      ),
                    Text(
                      session.backgroundLocation ? '后台定位已授权' : '当前为使用期间定位',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: session.canNameLocation
                            ? _nameLocation
                            : null,
                        icon: const Icon(
                          Icons.add_location_alt_outlined,
                          size: 18,
                        ),
                        label: const Text('命名当前位置'),
                      ),
                    ),
                    if (!session.canNameLocation)
                      Text(
                        '取得近期、精度足够的位置后即可命名。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                  if (session.placeNames.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final name in session.placeNames)
                          InputChip(
                            label: Text(name),
                            deleteButtonTooltipMessage: '移除地点「$name」',
                            onDeleted: () => session.removePlace(name),
                          ),
                      ],
                    ),
                  const Divider(),
                  _SignalControl(
                    title: '其他 App 使用时段',
                    description: '分享进入前台的应用名称、起止时间和停留时长。',
                    source: 'usage',
                    enabled: session.usageEnabled,
                    access: session.usageAccess,
                    lastObservation: session.lastUsageLabel,
                    session: session,
                  ),
                  if (session.screenshots.supported) ...[
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('定时截屏'),
                      subtitle: Text(
                        session.screenshotAccess == 'unsupported'
                            ? '当前安装包不支持系统屏幕共享。'
                            : session.screenshotAccess == 'usageRequired'
                            ? '先开启「其他 App 使用时段」并授予使用情况访问权。'
                            : session.screenshots.platform == 'ios'
                            ? '系统共享屏幕后，在使用其他应用时采集画面并上传。iOS 不提供可靠的应用名称。'
                            : '系统共享屏幕后，在使用其他应用时将截图和应用信息发送给 Agent。',
                      ),
                      value: session.screenshotsEnabled,
                      onChanged:
                          session.connection == null ||
                              (!session.screenshotsEnabled &&
                                  [
                                    'usageRequired',
                                    'unsupported',
                                    'unavailable',
                                  ].contains(session.screenshotAccess))
                          ? null
                          : session.setScreenshots,
                    ),
                    if (session.screenshotsEnabled) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('截图间隔'),
                        trailing: DropdownButton<int>(
                          value: session.screenshotInterval,
                          items: [
                            for (final seconds in [60, 300, 900])
                              DropdownMenuItem(
                                value: seconds,
                                child: Text('${seconds ~/ 60} 分钟'),
                              ),
                          ],
                          onChanged: (seconds) {
                            if (seconds != null) {
                              session.setScreenshotInterval(seconds);
                            }
                          },
                        ),
                      ),
                      if (session.screenshotAccess == 'active')
                        const Text('屏幕共享中')
                      else if ([
                        'ready',
                        'denied',
                      ].contains(session.screenshotAccess))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: session.startScreenshotCapture,
                            child: const Text('开始系统屏幕共享'),
                          ),
                        ),
                      if (session.pendingScreenshots > 0)
                        Text('待上传截图 ${session.pendingScreenshots} 张'),
                    ],
                    if (session.screenshotError != null)
                      Text(
                        session.screenshotError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                  if (session.signalError != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        session.signalError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
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
        SwitchListTile.adaptive(
          activeTrackColor: Theme.of(context).colorScheme.primary,
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: const TextStyle(fontSize: 16)),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          value: enabled,
          onChanged: session.connection == null || (unsupported && !enabled)
              ? null
              : (value) => session.setSignalEnabled(source, value),
        ),
        if (needsAccess)
          TextButton(
            onPressed: () => systemSettings
                ? session.openSignalSettings(source)
                : session.requestSignalAccess(source),
            child: Text(systemSettings ? '打开系统设置' : '前往授权'),
          ),
        if (enabled && access == 'granted' && lastObservation != null)
          Text(
            '最近记录 · $lastObservation',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
