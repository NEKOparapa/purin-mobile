import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../data/island_activity.dart';
import '../data/mobile_session.dart';
import '../data/schedule.dart';

class MascotIsland extends StatefulWidget {
  const MascotIsland({
    super.key,
    required this.session,
    required this.islandId,
    required this.onReturn,
    this.onSystemFold,
  });

  final MobileSession session;
  final String islandId;
  final VoidCallback onReturn;
  final ValueChanged<String?>? onSystemFold;

  @override
  State<MascotIsland> createState() => _MascotIslandState();
}

class _MascotIslandState extends State<MascotIsland>
    with WidgetsBindingObserver {
  bool _expanded = false, _loading = false;
  List<ScheduleEntry>? _entries;
  DateTime? _day;
  String? _error, _initialReply;
  bool _historyLoaded = false;
  Timer? _timer;
  late final _live = IslandActivity(widget.session, widget.islandId);
  bool _visible = false;

  String? get _reply =>
      widget.session.messages.reversed
              .where((m) => m['role'] == 'assistant')
              .firstOrNull?['id']
          as String?;

  @override
  void initState() {
    super.initState();
    _initialReply = _reply;
    _historyLoaded = widget.session.chatHistoryLoaded;
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_sessionChanged);
    widget.session.inbox.addListener(_sessionChanged);
    _live.attach();
    if (widget.onSystemFold != null) {
      IslandActivity.foldAndroid(
        widget.islandId,
        widget.session.connection != null,
      ).then((result) {
        if (mounted) widget.onSystemFold?.call(result);
      });
    }
    _sessionChanged();
  }

  void _sessionChanged() {
    if (!_historyLoaded && widget.session.chatHistoryLoaded) {
      _historyLoaded = true;
      _initialReply ??= _reply;
    }
    _live.sync(_status().$2);
    if (_live.watchesToday && _entries == null && _error == null) _readToday();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_visible == visible) return;
    _visible = visible;
    if (visible && (_expanded || _live.watchesToday)) _readToday();
    if (!visible) _timer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _live.lifecycle(state);
    if (state == AppLifecycleState.resumed &&
        (_expanded || _live.watchesToday)) {
      _readToday();
    }
  }

  Future<void> _readToday() async {
    final session = widget.session;
    final conn = session.connection;
    if (conn == null || _loading) return;
    final day = DateUtils.dateOnly(DateTime.now());
    final end = DateTime(day.year, day.month, day.day + 1);
    _loading = true;
    if (_day != day) {
      setState(() {
        _day = day;
        _entries = null;
        _error = null;
      });
    }
    bool current() => mounted && widget.session.connection == conn;
    try {
      final entries = await readScheduleRange(
        session.api,
        conn,
        day,
        end,
        current: current,
      );
      if (!current()) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
      _live.today(entries, day);
    } catch (_) {
      if (current()) {
        setState(() => _error = '今日内容暂时无法读取');
        _live.todayUnavailable();
      }
    } finally {
      _loading = false;
      if (current() && _visible && (_expanded || _live.watchesToday)) {
        _timer?.cancel();
        final now = DateTime.now();
        final delay = end.difference(now);
        _timer = Timer(
          delay < const Duration(seconds: 30)
              ? delay
              : const Duration(seconds: 30),
          () async {
            if (!_visible || (!_expanded && !_live.watchesToday)) return;
            final foreground =
                WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed;
            if (!foreground && !await _live.stillOnAndroid()) return;
            if (current()) _readToday();
          },
        );
      }
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    widget.session.inbox.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _live.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _tap() {
    if (_expanded) {
      widget.onReturn();
      return;
    }
    setState(() => _expanded = true);
    _readToday();
  }

  (IconData, String) _status() {
    final session = widget.session;
    final last = session.messages.lastOrNull;
    if (session.connection == null) return (Icons.cloud_off_outlined, '未连接');
    if (last?['role'] == 'user') {
      switch (last?['status']) {
        case 'sending':
        case 'queued':
        case 'running':
          return (Icons.more_horiz_rounded, '正在回复');
        case 'unsent':
        case 'failed':
        case 'interrupted':
        case 'missing':
          return (Icons.error_outline_rounded, '消息需要处理');
      }
    }
    if (_reply != null && _reply != _initialReply) {
      return (Icons.mark_email_unread_outlined, '收到新回复');
    }
    if (session.inbox.hasUnread) {
      return (Icons.notifications_active_outlined, '有未读通知');
    }
    return (Icons.bedtime_outlined, '待机');
  }

  @override
  Widget build(BuildContext context) {
    // MagicOS captures the current activity for its minimize animation.
    // Keep publishing the summary without painting a second capsule in that snapshot.
    if (widget.onSystemFold != null) return const SizedBox.shrink();
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = _expanded
            ? math.min(360.0, bounds.maxWidth - 20)
            : math.min(100.0, bounds.maxWidth);
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ListenableBuilder(
              listenable: widget.session.inbox,
              builder: (context, _) {
                final (icon, status) = _status();
                return Semantics(
                  button: true,
                  label: _expanded ? '返回对话' : '展开今日通知与安排，$status',
                  child: Material(
                    color: const Color(0xF218212E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: Color(0x24C8DEF8)),
                    ),
                    elevation: 2,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _tap,
                      child: AnimatedSize(
                        duration: motion,
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: width,
                            maxWidth: width,
                            maxHeight: math.max(48.0, bounds.maxHeight * .56),
                          ),
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: _expanded
                                  ? _summary()
                                  : SizedBox(
                                      height: 48,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Hero(
                                            tag: 'purin-island-cat',
                                            child: Image.asset(
                                              'assets/mascot/island-head@3x.png',
                                              width: 32,
                                              height: 29,
                                              excludeFromSemantics: true,
                                            ),
                                          ),
                                          Icon(
                                            icon,
                                            size: 20,
                                            color: const Color(0xFF92C8FF),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _summary() {
    final entries = _entries;
    final message = widget.session.connection == null
        ? '连接后可查看今天的内容'
        : _error ??
              (entries == null
                  ? '正在读取…'
                  : entries.isEmpty
                  ? '今天没有通知或安排'
                  : null);
    return DefaultTextStyle(
      style: const TextStyle(color: Color(0xfff4f4f6), fontSize: 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '今日通知与安排',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (message != null) Text(message),
            if (_error != null)
              TextButton(
                onPressed: _readToday,
                child: const Text(
                  '重新读取',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            for (final entry in entries ?? const <ScheduleEntry>[])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      entry.notification == null
                          ? Icons.event_outlined
                          : Icons.notifications_none_rounded,
                      semanticLabel: entry.notification == null ? '安排' : '通知',
                      size: 16,
                      color: const Color(0xFF92C8FF),
                    ),
                    const SizedBox(width: 6),
                    Text(islandTime(entry.at)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.notification?.title ?? entry.title),
                          if ((entry.notification?.body ?? entry.content).trim()
                              case final detail when detail.isNotEmpty)
                            Text(
                              detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFA0B3C8),
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
