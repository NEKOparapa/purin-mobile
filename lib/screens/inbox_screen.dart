import 'package:flutter/material.dart';

import '../data/device_inbox.dart';

String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.inbox, this.initialNotice});
  final DeviceInbox inbox;
  final String? initialNotice;
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NoticeDetail(inbox: inbox, notice: notice),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inbox = widget.inbox;
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, child) => Scaffold(
        appBar: AppBar(
          title: const Text('通知'),
          actions: [
            IconButton(
              tooltip: '刷新通知',
              onPressed: inbox.refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: inbox.refresh,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (!inbox.allowed && inbox.connection != null)
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('允许系统提醒'),
                    onTap: () => inbox.refreshPermission(request: true),
                  ),
                if (inbox.error != null)
                  ListTile(
                    title: Text(inbox.error!),
                    trailing: TextButton(
                      onPressed: inbox.refresh,
                      child: const Text('重试'),
                    ),
                  ),
                if (inbox.notices.isEmpty && inbox.error == null)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        inbox.connection == null
                            ? '连接后可查看通知'
                            : !inbox.available
                            ? '当前后端尚未支持设备通知'
                            : inbox.loading
                            ? '正在读取通知…'
                            : '暂无通知',
                      ),
                    ),
                  ),
                for (final notice in inbox.notices)
                  ListTile(
                    key: ValueKey(notice.id),
                    onTap: () => open(notice),
                    leading: Icon(
                      notice.read || notice.expired
                          ? Icons.notifications_none
                          : Icons.notifications_active_outlined,
                    ),
                    title: Text(
                      notice.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: notice.read
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (notice.expired) '已过期',
                        if (notice.files.isNotEmpty)
                          '${notice.files.length} 个附件',
                        notice.body,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (inbox.cursor != null)
                  TextButton(
                    onPressed: inbox.loading
                        ? null
                        : () => inbox.refresh(more: true),
                    child: const Text('加载更早通知'),
                  ),
              ],
            ),
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
    final notice = widget.notice, theme = Theme.of(context);
    final local = notice.created.toLocal();
    final locale = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('通知详情')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Text(notice.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${locale.formatMediumDate(local)} · ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(local))}${notice.expired ? ' · 已过期' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            if (notice.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: SelectableText(
                  notice.body,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            if (notice.files.isNotEmpty) const Divider(),
            for (final file in notice.files)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(file.name),
                subtitle: Text(fileSize(file.size)),
                trailing: saving == file.id
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_outlined),
                onTap: saving == null ? () => _save(file) : null,
              ),
            if (readError != null)
              TextButton(onPressed: _read, child: Text(readError!)),
          ],
        ),
      ),
    );
  }
}
