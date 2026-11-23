import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/device_inbox.dart';

String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Future<void> showScheduleNotice(
  BuildContext context,
  DeviceInbox inbox,
  DeviceNotice notice,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .82,
    ),
    child: _NoticeDetails(inbox: inbox, notice: notice),
  ),
);

class ScheduleTimedRow extends StatelessWidget {
  const ScheduleTimedRow({
    super.key,
    required this.time,
    required this.child,
    this.semanticsLabel,
    this.trailing,
  });
  final String time;
  final String? semanticsLabel;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final clock = Text(
      time,
      semanticsLabel: semanticsLabel,
      style: TextStyle(
        fontSize: 13,
        height: 1.65,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < scaler.scale(14) * 16) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [clock, ?trailing],
                ),
                const SizedBox(height: 3),
                child,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: scaler.scale(13) * 4.9 + 8, child: clock),
              Expanded(child: child),
              ?trailing,
            ],
          );
        },
      ),
    );
  }
}

class NoticeRow extends StatelessWidget {
  const NoticeRow({
    super.key,
    required this.notice,
    this.next = false,
    required this.locale,
    required this.onTap,
  });

  final DeviceNotice notice;
  final bool next;
  final MaterialLocalizations locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unread = notice.inInbox && !notice.read && !notice.expired;
    final time = locale.formatTimeOfDay(
      TimeOfDay.fromDateTime(notice.notifyAt),
      alwaysUse24HourFormat: true,
    );
    final meta = TextStyle(color: colors.onSurfaceVariant, fontSize: 12);
    return Semantics(
      key: ValueKey(notice.id),
      container: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ScheduleTimedRow(
          time: time,
          semanticsLabel: '${unread ? '未读，' : ''}通知时间 $time',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary,
                    ),
                  ),
                ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notice.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (notice.body.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    notice.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 9,
                children: [
                  Text(notice.statusLabel, style: meta),
                  if (notice.targetNames.isNotEmpty)
                    Text('目标设备 · ${notice.targetNames.join('、')}', style: meta),
                  if (notice.files.isNotEmpty)
                    Text('${notice.files.length} 个附件', style: meta),
                  if (next)
                    Text('下一项', style: meta.copyWith(color: colors.primary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeDetails extends StatefulWidget {
  const _NoticeDetails({required this.inbox, required this.notice});
  final DeviceInbox inbox;
  final DeviceNotice notice;
  @override
  State<_NoticeDetails> createState() => _NoticeDetailsState();
}

class _NoticeDetailsState extends State<_NoticeDetails> {
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
    final local = notice.notifyAt;
    final locale = MaterialLocalizations.of(context);
    final time = locale.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: true,
    );
    final meta = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    return SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            children: [
              Text(
                notice.title,
                style: const TextStyle(
                  fontSize: 21,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '通知时间 · ${local.year}年${local.month}月${local.day}日 $time　${notice.statusLabel}',
                style: meta,
              ),
              if (notice.targetNames.isNotEmpty)
                Text('目标设备 · ${notice.targetNames.join('、')}', style: meta),
              if (notice.body.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                SelectableText(
                  notice.body,
                  style: const TextStyle(fontSize: 15, height: 1.7),
                ),
              ],
              if (notice.files.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('附件', style: meta),
                for (final file in notice.files)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(file.name),
                    subtitle: Text(fileSize(file.size)),
                    trailing: saving == file.id
                        ? const CupertinoActivityIndicator()
                        : const Icon(Icons.download_outlined, size: 18),
                    enabled: saving == null,
                    onTap: () => _save(file),
                  ),
              ],
              if (readError != null)
                TextButton(onPressed: _read, child: Text(readError!)),
            ],
          ),
        ),
      ),
    );
  }
}
