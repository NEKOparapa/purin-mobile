import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/device_inbox.dart';
import '../widgets/app_theme.dart';
import '../widgets/shared.dart';

String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.inbox,
    this.initialNotice,
    this.embedded = false,
    this.topInset = 0,
    this.bottomInset = 24,
  });

  final DeviceInbox inbox;
  final String? initialNotice;
  final bool embedded;
  final double topInset;
  final double bottomInset;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final inbox = widget.inbox;
      await inbox.refresh();
      final id = widget.initialNotice;
      if (!mounted || id == null) return;
      while (mounted) {
        final item = inbox.notices.where((n) => n.id == id).firstOrNull;
        if (item != null) {
          await open(item);
          return;
        }
        final cursor = inbox.cursor;
        if (cursor == null || inbox.error != null) return;
        await inbox.refresh(more: true);
        if (cursor == inbox.cursor) return;
      }
    });
  }

  Future<void> open(DeviceNotice notice) async {
    final inbox = widget.inbox;
    await Navigator.of(
      context,
    ).push<void>(appleRoute(NoticeDetail(inbox: inbox, notice: notice)));
  }

  Widget _buildBody(BuildContext context) {
    final inbox = widget.inbox;
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    final locale = MaterialLocalizations.of(context);

    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: RefreshIndicator(
            edgeOffset: widget.embedded ? widget.topInset : 0,
            onRefresh: inbox.refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                widget.embedded ? widget.topInset : 10,
                16,
                widget.bottomInset,
              ),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (!inbox.allowed && inbox.connection != null) ...[
                  GlassCard(
                    radius: 22,
                    child: SettingsTile(
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.notifications_outlined,
                          size: 18,
                          color: colors.primary,
                        ),
                      ),
                      title: '允许系统提醒',
                      subtitle: '开启后可及时收到来自 Wintermute 的通知',
                      showChevron: true,
                      onTap: () => inbox.refreshPermission(request: true),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (inbox.error != null) ...[
                  GlassCard(
                    radius: 22,
                    padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
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
                            inbox.error!,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: colors.error,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: inbox.refresh,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (inbox.notices.isEmpty && inbox.error == null)
                  GlassCard(
                    radius: 26,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 44,
                    ),
                    child: Column(
                      children: [
                        if (inbox.loading)
                          const CupertinoActivityIndicator(radius: 11)
                        else
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 30,
                            color: colors.onSurfaceVariant.withValues(
                              alpha: 0.65,
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          inbox.connection == null
                              ? '连接后可查看通知'
                              : !inbox.available
                              ? '当前后端尚未支持设备通知'
                              : inbox.loading
                              ? '正在读取通知…'
                              : '暂无通知',
                          style: TextStyle(
                            fontSize: 14.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (inbox.notices.isNotEmpty)
                  GlassCard(
                    radius: 26,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (var i = 0; i < inbox.notices.length; i++) ...[
                          _NoticeRow(
                            notice: inbox.notices[i],
                            locale: locale,
                            onTap: () => open(inbox.notices[i]),
                          ),
                          if (i < inbox.notices.length - 1)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Divider(
                                height: 0.6,
                                thickness: 0.6,
                                color: atmo.hairline,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                if (inbox.cursor != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Center(
                      child: TextButton(
                        onPressed: inbox.loading
                            ? null
                            : () => inbox.refresh(more: true),
                        child: Text(inbox.loading ? '正在加载…' : '加载更早通知'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildBody(context);
    return AtmosphereScaffold(
      title: '通知',
      actions: [
        IconButton(
          tooltip: '刷新通知',
          onPressed: widget.inbox.refresh,
          icon: const Icon(Icons.refresh_rounded, size: 21),
        ),
      ],
      body: SafeArea(top: false, child: _buildBody(context)),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.notice,
    required this.locale,
    required this.onTap,
  });

  final DeviceNotice notice;
  final MaterialLocalizations locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = !notice.read && !notice.expired;
    final local = notice.created.toLocal();
    final timeStr = locale.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    final subtitle = [
      if (notice.expired) '已过期',
      if (notice.files.isNotEmpty) '${notice.files.length} 个附件',
      notice.body,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      key: ValueKey(notice.id),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 15, 16, 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 12),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: unread ? colors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notice.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: notice.expired
                                  ? colors.onSurfaceVariant
                                  : colors.onSurface,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoticeDetail extends StatefulWidget {
  const NoticeDetail({super.key, required this.inbox, required this.notice});
  final DeviceInbox inbox;
  final DeviceNotice notice;
  @override
  State<NoticeDetail> createState() => _NoticeDetailState();
}

class _NoticeDetailState extends State<NoticeDetail> {
  String? saving, readError;
  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      await widget.inbox.markRead(widget.notice);
      if (mounted && readError != null) setState(() => readError = null);
    } catch (e) {
      if (mounted) setState(() => readError = '未能标记已读：$e');
    }
  }

  Future<void> _save(NoticeFile file) async {
    setState(() => saving = file.id);
    try {
      final saved = await widget.inbox.save(widget.notice, file);
      if (mounted && saved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('附件已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    final local = notice.created.toLocal();
    final locale = MaterialLocalizations.of(context);

    return AtmosphereScaffold(
      title: '通知详情',
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
              children: [
                GlassCard(
                  radius: 26,
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notice.title,
                        style: TextStyle(
                          fontSize: 21,
                          height: 1.32,
                          letterSpacing: -0.4,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: atmo.inputFill,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${locale.formatMediumDate(local)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(local))}${notice.expired ? ' · 已过期' : ''}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (notice.body.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        SelectableText(
                          notice.body,
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.72,
                            color: colors.onSurface.withValues(alpha: 0.92),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (notice.files.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SettingsSection(
                    title: '附件',
                    dividers: true,
                    children: [
                      for (final file in notice.files)
                        SettingsTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: atmo.inputFill,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.attach_file_rounded,
                              size: 18,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          title: file.name,
                          subtitle: fileSize(file.size),
                          trailing: saving == file.id
                              ? const CupertinoActivityIndicator(radius: 9)
                              : Icon(
                                  Icons.download_rounded,
                                  size: 20,
                                  color: colors.primary,
                                ),
                          enabled: saving == null,
                          onTap: () => _save(file),
                        ),
                    ],
                  ),
                ],
                if (readError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Center(
                      child: TextButton(
                        onPressed: _read,
                        child: Text(readError!),
                      ),
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
