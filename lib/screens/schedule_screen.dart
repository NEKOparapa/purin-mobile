import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../data/agent_api.dart';
import '../data/device_inbox.dart';
import '../data/schedule.dart';
import '../widgets/schedule_dates.dart';
import '../widgets/schedule_notice.dart';

DateTime _shiftDay(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);
String _formatClock(DateTime at, {bool includeSeconds = false}) {
  String d(int n) => n.toString().padLeft(2, '0');
  return [
    at.hour,
    at.minute,
    if (includeSeconds && at.second != 0) at.second,
  ].map(d).join(':');
}

enum _AgendaFilter {
  all('全部状态'),
  pending('待触发'),
  triggered('已触发');

  const _AgendaFilter(this.label);
  final String label;
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.api,
    required this.connection,
    required this.inbox,
    required this.onSettings,
    this.openedNotice,
    this.topInset = 0,
  });
  final AgentApi api;
  final Connection? connection;
  final DeviceInbox inbox;
  final VoidCallback onSettings;
  final DeviceNotice? openedNotice;
  final double topInset;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with WidgetsBindingObserver {
  DateTime _selected = DateUtils.dateOnly(DateTime.now());
  bool _month = false, _visible = false;
  _AgendaFilter _filter = _AgendaFilter.all;
  Map<DateTime, List<ScheduleEntry>>? _byDay;
  String? _error;
  int _revision = 0;
  Future<void>? _pending;
  Timer? _timer;

  DateTime get _start => _month
      ? DateTime(_selected.year, _selected.month)
      : _shiftDay(_selected, 1 - _selected.weekday);
  DateTime get _end => _month
      ? DateTime(_selected.year, _selected.month + 1)
      : _shiftDay(_start, 7);

  @override
  void initState() {
    super.initState();
    if (widget.openedNotice case final notice?) {
      _selected = DateUtils.dateOnly(notice.notifyAt);
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(ScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openedNotice != null &&
        widget.openedNotice != oldWidget.openedNotice) {
      _select(widget.openedNotice!.notifyAt);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _updateVisibility();

  void _updateVisibility() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final visible =
        (ModalRoute.isCurrentOf(context) ?? true) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    if (_visible == visible) return;
    _visible = visible;
    _revision++;
    _pending = null;
    _timer?.cancel();
    if (visible && widget.inbox.supported) {
      widget.inbox.refreshPermission();
    }
    if (visible && widget.connection != null) {
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() {
    final connection = widget.connection;
    if (connection == null || !_visible) return Future.value();
    return _pending ??= _read(connection, _revision);
  }

  Future<void> _read(Connection connection, int revision) async {
    bool current() => mounted && revision == _revision;
    try {
      final entries = <String, ScheduleEntry>{};
      await for (final rows in schedulePages(
        widget.api,
        connection,
        _start,
        _end,
      )) {
        if (!current()) return;
        for (final entry in rows) {
          entries[entry.id] = entry;
        }
      }
      if (!current()) return;
      final ordered = entries.values.toList()
        ..sort((a, b) {
          final order = a.at.compareTo(b.at);
          return order != 0 ? order : a.id.compareTo(b.id);
        });
      final byDay = <DateTime, List<ScheduleEntry>>{};
      for (final entry in ordered) {
        (byDay[DateUtils.dateOnly(entry.at)] ??= []).add(entry);
      }
      setState(() {
        _byDay = byDay;
        _error = null;
      });
    } catch (e) {
      if (!current()) return;
      setState(
        () => _error = switch (e) {
          ApiError(status: 404 || 400) => '当前后端未提供按日通知，请升级后端后刷新。',
          FormatException(:final message) => message,
          _ => '日历读取失败，请检查连接后重试。',
        },
      );
    } finally {
      if (current()) _pending = null;
    }
  }

  void _select(DateTime day, {bool? month}) {
    final previous = (_start, _end);
    setState(() {
      _selected = DateUtils.dateOnly(day);
      _month = month ?? _month;
      _filter = _AgendaFilter.all;
      if (previous != (_start, _end)) {
        _revision++;
        _pending = null;
        _byDay = null;
        _error = null;
      }
    });
    if (previous != (_start, _end)) _refresh();
  }

  void _move(int delta) {
    if (!_month) {
      _select(_shiftDay(_selected, delta * 7));
      return;
    }
    final last = DateTime(_selected.year, _selected.month + delta + 1, 0);
    _select(DateTime(last.year, last.month, math.min(_selected.day, last.day)));
  }

  DateTime? _findNearestOtherDay() {
    final map = _byDay;
    if (map == null || map.isEmpty) return null;
    final candidates = [
      for (final entry in map.entries)
        if (entry.key != _selected && entry.value.isNotEmpty) entry.key,
    ];
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final aAhead = !a.isBefore(_selected) ? 0 : 1;
      final bAhead = !b.isBefore(_selected) ? 0 : 1;
      if (aAhead != bAhead) return aAhead - bAhead;
      return (a.difference(_selected).inDays.abs()).compareTo(
        b.difference(_selected).inDays.abs(),
      );
    });
    return candidates.first;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final isToday = _selected == today;
    final entries = _byDay?[_selected] ?? const <ScheduleEntry>[];
    final agenda = entries.where((e) => e.notification == null).toList();
    final notices = entries.map((e) => e.notification).nonNulls.toList();
    final pendingAgenda = agenda.where((e) => !e.triggered).length;
    final triggeredAgenda = agenda.length - pendingAgenda;
    final showFilters = pendingAgenda > 0 && triggeredAgenda > 0;
    final activeFilter = showFilters ? _filter : _AgendaFilter.all;
    final visibleAgenda = switch (activeFilter) {
      _AgendaFilter.pending => agenda.where((e) => !e.triggered).toList(),
      _AgendaFilter.triggered => agenda.where((e) => e.triggered).toList(),
      _AgendaFilter.all => agenda,
    };

    ScheduleEntry? nextUpcoming;
    if (isToday) {
      for (final item in entries) {
        if (item.notification case final n?) {
          if (n.status == 'scheduled' && !n.notifyAt.isBefore(now)) {
            nextUpcoming = item;
            break;
          }
        } else if (!item.triggered && !item.at.isBefore(now)) {
          nextUpcoming = item;
          break;
        }
      }
    }

    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    final nearest = entries.isEmpty ? _findNearestOtherDay() : null;
    final connected = widget.connection != null;
    final loaded = _byDay != null;
    return RefreshIndicator(
      edgeOffset: widget.topInset,
      onRefresh: _refresh,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(20, widget.topInset + 8, 20, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visibleAgenda.length + 2,
        itemBuilder: (context, index) {
          if (index == visibleAgenda.length + 1) {
            return Padding(
              padding: const EdgeInsets.only(top: 22),
              child: _DayNotices(
                key: ValueKey(_selected),
                inbox: widget.inbox,
                notices: notices,
                loaded: loaded,
                nextId: nextUpcoming?.notification?.id,
                emptyText: !connected
                    ? '连接后可查看当日通知'
                    : loaded
                    ? '当日没有通知'
                    : _error == null
                    ? '正在读取通知…'
                    : '尚未获取当日通知',
              ),
            );
          }
          if (index > 0) {
            final entry = visibleAgenda[index - 1];
            return _AgendaRow(
              entry: entry,
              next: nextUpcoming?.id == entry.id,
              divider: index > 1,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScheduleDatePicker(
                selected: _selected,
                start: _start,
                end: _end,
                month: _month,
                entries: _byDay,
                onSelect: _select,
                onMove: _move,
                onToggle: () => _select(_selected, month: !_month),
              ),
              const SizedBox(height: 22),
              if (!connected) ...[
                const _SectionHeading(title: '当日安排'),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('连接后可查看主 Agent 的安排。', style: muted),
                    TextButton(
                      onPressed: widget.onSettings,
                      child: const Text('打开连接设置'),
                    ),
                  ],
                ),
              ] else ...[
                if (_error != null)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text(
                        _error! + (loaded ? ' 当前显示上次读取的安排。' : ''),
                        style: TextStyle(color: colors.error),
                      ),
                      TextButton(onPressed: _refresh, child: const Text('重试')),
                    ],
                  ),
                _SectionHeading(
                  title: '当日安排',
                  count: loaded ? agenda.length : null,
                  action: showFilters
                      ? PopupMenuButton<_AgendaFilter>(
                          tooltip: '筛选当日安排',
                          initialValue: activeFilter,
                          onSelected: (value) =>
                              setState(() => _filter = value),
                          itemBuilder: (_) => [
                            for (final value in _AgendaFilter.values)
                              PopupMenuItem(
                                value: value,
                                child: Text(value.label),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(activeFilter.label, style: muted),
                                Icon(
                                  Icons.expand_more,
                                  size: 16,
                                  color: colors.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        )
                      : null,
                ),
                if (agenda.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(
                          loaded
                              ? '当天没有安排'
                              : _error == null
                              ? '正在读取安排…'
                              : '尚未获取当天安排',
                          style: muted,
                        ),
                        if (nearest != null)
                          TextButton(
                            onPressed: () => _select(nearest),
                            child: Text(
                              '查看 ${nearest.month}/${nearest.day} 日程',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.count, this.action});
  final String title;
  final int? count;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (count != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            ?action,
          ],
        ),
        const SizedBox(height: 7),
        const Divider(height: 1),
      ],
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.entry,
    required this.next,
    required this.divider,
  });
  final ScheduleEntry entry;
  final bool next, divider;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final meta = TextStyle(color: colors.onSurfaceVariant, fontSize: 12);
    final action = switch (entry.action) {
      'notify_agent' => '通知主 Agent',
      'notify_device' => '发送设备通知',
      _ => entry.action,
    };
    return Column(
      children: [
        if (divider) const Divider(height: 1),
        ScheduleTimedRow(
          time: _formatClock(entry.at, includeSeconds: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (entry.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    entry.content,
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
                  Text(entry.triggered ? '已触发' : '待触发', style: meta),
                  Text(action, style: meta),
                  if (next)
                    Text('下一项', style: meta.copyWith(color: colors.primary)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayNotices extends StatefulWidget {
  const _DayNotices({
    super.key,
    required this.inbox,
    required this.notices,
    required this.emptyText,
    required this.loaded,
    required this.nextId,
  });
  final DeviceInbox inbox;
  final List<DeviceNotice> notices;
  final String emptyText;
  final bool loaded;
  final String? nextId;

  @override
  State<_DayNotices> createState() => _DayNoticesState();
}

class _DayNoticesState extends State<_DayNotices> {
  bool _showAll = false;
  bool _requesting = false;

  Future<void> _requestPermission() async {
    setState(() => _requesting = true);
    try {
      await widget.inbox.refreshPermission(request: true);
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = widget.inbox;
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        final shown = _showAll
            ? widget.notices
            : widget.notices.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeading(
              title: '当日通知',
              count: widget.loaded ? widget.notices.length : null,
              action: widget.notices.length > 3
                  ? TextButton(
                      onPressed: () => setState(() => _showAll = !_showAll),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                      child: Text(
                        _showAll ? '收起' : '显示全部 ${widget.notices.length} 条',
                      ),
                    )
                  : null,
            ),
            if (inbox.supported && inbox.allowed == false)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _requesting ? null : _requestPermission,
                  child: const Text('获取通知权限'),
                ),
              ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  widget.emptyText,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              NoticeRow(
                notice: shown[i],
                next: widget.nextId == shown[i].id,
                locale: MaterialLocalizations.of(context),
                onTap: () => showScheduleNotice(context, inbox, shown[i]),
              ),
            ],
          ],
        );
      },
    );
  }
}
