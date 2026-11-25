import 'package:flutter/material.dart';

import '../data/mobile_connectors.dart';
import '../data/mobile_session.dart';
import '../widgets/shared.dart';

extension on MobileConnector {
  (IconData, Color, String) get appearance => switch (this) {
    MobileConnector.clock => (
      Icons.alarm_rounded,
      const Color(0xffbf514a),
      '设一个 25 分钟的专注计时器',
    ),
    MobileConnector.usage => (
      Icons.timelapse_rounded,
      const Color(0xff7164ab),
      '今天我在哪些应用上花的时间最多？',
    ),
    MobileConnector.calendar => (
      Icons.calendar_today_rounded,
      const Color(0xffc4564c),
      '明天下午有什么日程？',
    ),
    MobileConnector.contacts => (
      Icons.contacts_outlined,
      const Color(0xff448c98),
      '帮我找一下小陈的工作邮箱',
    ),
    MobileConnector.files => (
      Icons.folder_open_rounded,
      const Color(0xffb38240),
      '工作资料目录里有哪些笔记？',
    ),
    MobileConnector.location => (
      Icons.location_on_outlined,
      const Color(0xff4c79ae),
      '我现在在哪里？',
    ),
    MobileConnector.notifications => (
      Icons.notifications_none_rounded,
      const Color(0xff7666a9),
      '现在通知栏里有哪些提醒？',
    ),
    MobileConnector.sms => (
      Icons.chat_bubble_outline_rounded,
      const Color(0xff398665),
      '最近有包含“快递”的短信吗？',
    ),
    MobileConnector.iosCalendar => (
      Icons.calendar_today_rounded,
      const Color(0xffc4564c),
      '明天下午有什么日程？',
    ),
    MobileConnector.iosContacts => (
      Icons.contacts_outlined,
      const Color(0xff448c98),
      '帮我查小陈的工作邮箱',
    ),
    MobileConnector.iosHealth => (
      Icons.favorite_rounded,
      const Color(0xffc84668),
      '帮我看看昨天的睡眠和运动摘要',
    ),
    MobileConnector.iosMusic => (
      Icons.music_note_rounded,
      const Color(0xffb94460),
      '搜索我想听的歌，然后播放',
    ),
    MobileConnector.iosPhotos => (
      Icons.photo_library_outlined,
      const Color(0xff8868ae),
      '找出昨天拍的截图',
    ),
    MobileConnector.iosReminders => (
      Icons.checklist_rounded,
      const Color(0xff427ca4),
      '明天八点提醒我带钥匙',
    ),
    MobileConnector.iosLocation => (
      Icons.location_on_outlined,
      const Color(0xff4c79ae),
      '我现在在哪里？',
    ),
  };
}

class MobileConnectorsScreen extends StatefulWidget {
  const MobileConnectorsScreen({super.key, required this.session});
  final MobileSession session;

  @override
  State<MobileConnectorsScreen> createState() => _MobileConnectorsScreenState();
}

class _MobileConnectorsScreenState extends State<MobileConnectorsScreen> {
  MobileConnector? _working;
  String? _feedback;

  Future<void> _change(MobileConnector item, bool value) async {
    setState(() {
      _working = item;
      _feedback = null;
    });
    String? issue;
    try {
      issue = await widget.session.setMobileConnector(item, value);
    } catch (e) {
      issue = '无法更改授权 · $e';
    } finally {
      if (mounted) {
        setState(() {
          _working = null;
          _feedback = issue;
        });
      }
    }
  }

  Future<void> _details(MobileConnector item) async {
    final session = widget.session;
    final supported = session.connectorSupported(item);
    final on = session.connectorEnabled(item);
    final granted = session.connectorGranted(item);
    final action = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(item.description),
              const SizedBox(height: 20),
              Text('可以这样问', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text('“${item.appearance.$3}”'),
              const SizedBox(height: 20),
              if (!supported) ...[
                Text(
                  '此连接器仅可在 ${item.platform.label} 设备上启用。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                const FilledButton(onPressed: null, child: Text('启用连接器')),
              ] else if (!session.canEnableConnectors)
                const Text('通过 HTTPS 或本机回环地址连接服务后，即可在此启用。')
              else ...[
                if (!on || !granted)
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(on ? '重新授权' : '启用连接器'),
                  ),
                if (on && !granted) const SizedBox(height: 8),
                if (on)
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('关闭连接器'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (action != null && mounted) await _change(item, action);
  }

  Widget _card(MobileConnector item, double width) {
    final session = widget.session;
    final (icon, color, _) = item.appearance;
    final theme = Theme.of(context);
    final supported = session.connectorSupported(item);
    final on = session.connectorEnabled(item);
    final granted = session.connectorGranted(item);
    final status = !supported
        ? '仅限 ${item.platform.label}'
        : on
        ? (granted ? '已启用' : '需要授权')
        : '未启用';
    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _working == null ? () => _details(item) : null,
          child: Opacity(
            opacity: supported ? 1 : 0.62,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color.lerp(color, Colors.white, .22)!, color],
                      ),
                    ),
                    child: Icon(icon, color: Colors.white, size: 25),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          item.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_working == item)
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (!supported)
                    Text(
                      '不可用',
                      semanticsLabel: status,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Icon(
                      on
                          ? (granted
                                ? Icons.check_circle_outline
                                : Icons.error_outline)
                          : Icons.add_circle_outline,
                      semanticLabel: status,
                      color: on
                          ? (granted
                                ? const Color(0xff38996f)
                                : theme.colorScheme.error)
                          : theme.colorScheme.outline,
                      size: 23,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AtmosphereScaffold(
    title: '连接器',
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          final session = widget.session;
          final currentPlatform = session.connectors.platform;
          final groups = currentPlatform.displayOrder;
          final theme = Theme.of(context);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  LayoutBuilder(
                    builder: (context, bounds) {
                      final width = bounds.maxWidth >= 600
                          ? (bounds.maxWidth - 12) / 2
                          : bounds.maxWidth;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < groups.length; i++) ...[
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                5,
                                i == 0 ? 0 : 22,
                                5,
                                12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      groups[i].label,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                  ),
                                  Flexible(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        groups[i] == currentPlatform
                                            ? (session.connection?.deviceName ??
                                                  '本机')
                                            : '仅限 ${groups[i].label} 设备',
                                        overflow: TextOverflow.ellipsis,
                                        style: groups[i] == currentPlatform
                                            ? null
                                            : theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: 12,
                              runSpacing: 9,
                              children: [
                                for (final item in groups[i].catalog)
                                  _card(item, width),
                              ],
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _feedback ??
                        session.connectorError ??
                        (currentPlatform == ConnectorPlatform.unsupported
                            ? '点开可查看连接器用法，请在 Android 或 iOS 设备上启用。'
                            : session.canEnableConnectors
                            ? '手机在前台时响应查询，结果会保存到当前会话。'
                            : '点开可查看用法，连接服务后即可启用。'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
