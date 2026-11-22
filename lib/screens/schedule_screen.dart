import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../data/agent_api.dart';
import '../data/device_inbox.dart';
import '../data/schedule.dart';
import 'inbox_screen.dart';

const _weekdays = '一二三四五六日';
DateTime _shiftDay(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);
String _monthLabel(DateTime day) => '${day.year}年${day.month}月';
const _heading = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.api,
    required this.connection,
    required this.inbox,
    required this.onSettings,
    required this.onInbox,
    required this.onNotice,
  });
  final AgentApi api;
  final Connection? connection;
  final DeviceInbox inbox;
  final VoidCallback onSettings, onInbox;
  final ValueChanged<DeviceNotice> onNotice;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with WidgetsBindingObserver {
  DateTime _selected = DateUtils.dateOnly(DateTime.now());
  bool _month = false, _visible = false;
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
    WidgetsBinding.instance.addObserver(this);
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
          ApiError(status: 404) => '当前后端未提供日历，请升级后端后刷新。',
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

  @override
  Widget build(BuildContext context) {
    final agenda = _byDay?[_selected] ?? const <ScheduleEntry>[];
    final colors = Theme.of(context).colorScheme;
    final last = _shiftDay(_end, -1);
    var period = _monthLabel(_start);
    if (last.month != _start.month) {
      period += _start.year == last.year
          ? '至${last.month}月'
          : '至${_monthLabel(last)}';
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 1 + agenda.length,
        itemBuilder: (context, index) {
          if (index > 0) return _AgendaRow(entry: agenda[index - 1]);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tooltip(
                    message: _month ? '收起月历' : '展开月历',
                    child: TextButton(
                      onPressed: () => _select(_selected, month: !_month),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurface,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(period, style: _heading),
                          Icon(
                            _month ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _month ? '上个月' : '上一周',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _move(-1),
                      ),
                      TextButton(
                        onPressed: () => _select(DateTime.now()),
                        child: const Text('今天'),
                      ),
                      IconButton(
                        tooltip: _month ? '下个月' : '下一周',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _move(1),
                      ),
                    ],
                  ),
                ],
              ),
              _DateGrid(
                start: _start,
                end: _end,
                selected: _selected,
                entries: _byDay,
                onSelect: _select,
              ),
              const SizedBox(height: 10),
              const Divider(),
              if (widget.connection != null && widget.inbox.supported)
                _RecentNotices(
                  inbox: widget.inbox,
                  onInbox: widget.onInbox,
                  onNotice: widget.onNotice,
                ),
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${_selected.month}月${_selected.day}日的安排',
                      style: _heading,
                    ),
                    Text(
                      '星期${_weekdays[_selected.weekday - 1]}',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (widget.connection == null)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    const Text('连接后可查看主 Agent 的安排。'),
                    TextButton(
                      onPressed: widget.onSettings,
                      child: const Text('打开连接设置'),
                    ),
                  ],
                )
              else if (_error != null)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      _error! + (_byDay == null ? '' : ' 当前显示上次读取的安排。'),
                      style: TextStyle(color: colors.error),
                    ),
                    TextButton(onPressed: _refresh, child: const Text('重试')),
                  ],
                )
              else if (_byDay == null || agenda.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    _byDay == null ? '正在读取安排…' : '当天没有安排',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DateGrid extends StatelessWidget {
  const _DateGrid({
    required this.start,
    required this.end,
    required this.selected,
    required this.entries,
    required this.onSelect,
  });
  final DateTime start, end, selected;
  final Map<DateTime, List<ScheduleEntry>>? entries;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    return Table(
      children: [
        TableRow(
          children: [
            for (final day in _weekdays.split(''))
              Center(
                child: Text(
                  '周$day',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        for (
          var monday = _shiftDay(start, 1 - start.weekday);
          monday.isBefore(end);
          monday = _shiftDay(monday, 7)
        )
          TableRow(
            children: [
              for (int i = 0; i < 7; i++)
                _cell(context, _shiftDay(monday, i), today),
            ],
          ),
      ],
    );
  }

  Widget _cell(BuildContext context, DateTime day, DateTime today) {
    if (day.isBefore(start) || !day.isBefore(end)) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final count = entries?[day]?.length ?? 0;
    final chosen = day == selected;
    final ink = chosen
        ? colors.surface
        : day == today
        ? colors.primary
        : colors.onSurface;
    return Semantics(
      button: true,
      selected: chosen,
      excludeSemantics: true,
      label:
          '${day.year}年${day.month}月${day.day}日${day == today ? '，今天' : ''}${entries == null ? '' : '，$count项安排'}',
      onTap: () => onSelect(day),
      child: InkWell(
        onTap: () => onSelect(day),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 46,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: chosen ? colors.onSurface : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: ink,
                        fontWeight: chosen || day == today
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      bottom: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: ink,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 4),
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

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.entry});
  final ScheduleEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final at = entry.at;
    String digits(int n) => n.toString().padLeft(2, '0');
    final time = [
      at.hour,
      at.minute,
      if (at.second != 0) at.second,
    ].map(digits).join(':');
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 70, child: Text(time, style: muted)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (entry.content.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(entry.content),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 15,
                          color: colors.onSurfaceVariant,
                        ),
                        Text(
                          entry.action == 'notify_agent'
                              ? '通知主 Agent'
                              : entry.action,
                          style: muted,
                        ),
                        Text(entry.triggered ? '已触发' : '待触发', style: muted),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(),
      ],
    );
  }
}

class _RecentNotices extends StatelessWidget {
  const _RecentNotices({
    required this.inbox,
    required this.onInbox,
    required this.onNotice,
  });
  final DeviceInbox inbox;
  final VoidCallback onInbox;
  final ValueChanged<DeviceNotice> onNotice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: inbox,
    builder: (context, _) {
      if (!inbox.available) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('最近通知', style: _heading),
              TextButton(onPressed: onInbox, child: const Text('查看通知')),
            ],
          ),
          for (final notice in inbox.notices.take(2))
            NoticeRow(
              notice: notice,
              locale: MaterialLocalizations.of(context),
              onTap: () => onNotice(notice),
            ),
          if (inbox.notices.isEmpty)
            Text(
              inbox.error ?? (inbox.loading ? '正在读取通知…' : '暂无通知'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
          const Divider(),
        ],
      );
    },
  );
}
