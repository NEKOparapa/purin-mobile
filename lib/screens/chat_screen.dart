import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import '../data/agent_api.dart';
import '../data/device_inbox.dart';
import '../data/island_activity.dart';
import '../data/mobile_session.dart';
import '../widgets/app_theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_mascot.dart';
import '../widgets/mascot_island.dart';
import '../widgets/question_cards.dart';
import '../widgets/shared.dart';
import 'connection_screen.dart';
import '../widgets/schedule_notice.dart';
import 'schedule_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.session});
  final MobileSession session;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  PageRoute<void>? _scheduleRoute;
  ({String id, Connection? connection})? _systemFold;
  final _openedNotice = ValueNotifier<({String scope, DeviceNotice notice})?>(
    null,
  );
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  int _lastCount = 0;
  String? _scope;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_updateFocus);
    widget.session.inbox.onOpen = _openNotice;
    IslandActivity.listenForOpen(_returnToChat);
  }

  void _returnToChat() {
    if (_systemFold != null) setState(() => _systemFold = null);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  int _openRequest = 0;

  Future<void> _openNotice(String scope, String id) async {
    final inbox = widget.session.inbox;
    if (!mounted || scope != inbox.connection?.scope) return;
    final nav = Navigator.of(context);
    final existing = _scheduleRoute;
    nav.popUntil((route) => route == existing || route.isFirst);
    _openSchedule();
    final route = _scheduleRoute!;
    final request = ++_openRequest;
    final notice = await inbox.findNotice(id);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        notice == null ||
        request != _openRequest ||
        route != _scheduleRoute ||
        !route.isCurrent ||
        scope != inbox.connection?.scope) {
      return;
    }
    _openedNotice.value = (scope: scope, notice: notice);
    final pageContext = route.subtreeContext;
    if (pageContext != null && pageContext.mounted) {
      await showScheduleNotice(pageContext, inbox, notice);
    }
  }

  void _updateFocus() => setState(() {});

  void _foldAssistant() {
    if (_systemFold != null || _scheduleRoute != null) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    if (defaultTargetPlatform == TargetPlatform.android) {
      setState(
        () => _systemFold = (id: id, connection: widget.session.connection),
      );
    } else {
      _openSchedule(islandId: id);
    }
  }

  void _systemFoldResult(String id, String? result) {
    if (!mounted || _systemFold?.id != id || result == 'promoted') return;
    setState(() => _systemFold = null);
    if (result == 'cancelled' || ModalRoute.isCurrentOf(context) != true) {
      return;
    }
    _openSchedule(islandId: id);
    final message = switch (result) {
      'disabled' => '通知权限或助手胶囊通知已关闭，当前在应用内显示',
      'notPromoted' => '系统未显示实时胶囊，当前在应用内显示',
      'unavailable' => '系统胶囊暂时不可用，当前在应用内显示',
      _ => null,
    };
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _openSchedule({String? islandId}) {
    if (_systemFold != null) setState(() => _systemFold = null);
    if (_scheduleRoute?.isCurrent ?? false) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _openedNotice.value = null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Widget page(BuildContext context) => _schedulePage(context, islandId);
    final PageRoute<void> route =
        Theme.of(context).platform == TargetPlatform.iOS
        ? CupertinoPageRoute<void>(builder: page)
        : PageRouteBuilder<void>(
            transitionDuration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 210),
            reverseTransitionDuration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 170),
            pageBuilder: (context, _, _) => page(context),
            transitionsBuilder: (context, animation, _, child) =>
                SlideTransition(
                  position: animation.drive(
                    Tween(
                      begin: const Offset(0, .13),
                      end: Offset.zero,
                    ).chain(CurveTween(curve: Curves.easeOutCubic)),
                  ),
                  child: FadeTransition(opacity: animation, child: child),
                ),
          );
    _scheduleRoute = route;
    widget.session.page('日程');
    Navigator.of(context).push(route).then((_) {
      if (!mounted || _scheduleRoute != route) return;
      _scheduleRoute = null;
      _openRequest++;
      widget.session.page('Agent 对话');
    });
  }

  Widget _schedulePage(BuildContext context, String? islandId) {
    final session = widget.session;
    final safeTop = MediaQuery.paddingOf(context).top;
    final toolbarHeight =
        kToolbarHeight +
        (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
          0,
          double.infinity,
        );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListenableBuilder(
                  listenable: session,
                  builder: (context, _) => ValueListenableBuilder(
                    valueListenable: _openedNotice,
                    builder: (context, notice, _) => ScheduleScreen(
                      key: ObjectKey(session.connection),
                      api: session.api,
                      connection: session.connection,
                      inbox: session.inbox,
                      onSettings: _settings,
                      topInset:
                          safeTop + toolbarHeight + FadingPageHeader.feather,
                      openedNotice: notice?.scope == session.connection?.scope
                          ? notice?.notice
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FadingPageHeader(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(8, safeTop, 8, 0),
                  child: SizedBox(
                    height: toolbarHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.chevron_left_rounded),
                          label: const Text('对话'),
                        ),
                        _settingsButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (islandId != null)
              Positioned.fill(
                top: safeTop,
                child: ListenableBuilder(
                  listenable: session,
                  builder: (context, _) => MascotIsland(
                    key: ObjectKey(session.connection),
                    islandId: islandId,
                    session: session,
                    onReturn: _returnToChat,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _settings() async {
    if (ModalRoute.isCurrentOf(context) != true &&
        _scheduleRoute?.isCurrent != true) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    widget.session.page('连接与采集');
    final page = ConnectionScreen(session: widget.session);
    await Navigator.of(context).push(appleRoute<void>(page));
    if (!mounted) return;
    if (_scheduleRoute?.isCurrent ?? false) {
      widget.session.page('日程');
    } else if (ModalRoute.isCurrentOf(context) ?? false) {
      widget.session.page('Agent 对话');
    }
  }

  Widget _settingsButton() => IconButton(
    tooltip: '设置',
    icon: const Icon(Icons.settings_outlined),
    iconSize: 22,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    onPressed: _settings,
  );

  void _scrollAfterSend() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    IslandActivity.listenForOpen(null);
    widget.session.inbox.onOpen = null;
    _openedNotice.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom > 0;
    final availableHeight =
        media.size.height - media.viewInsets.bottom - media.padding.vertical;
    final compact = keyboard || availableHeight < 480;
    final showHeader = !keyboard || availableHeight >= 200;
    final toolbarHeight =
        (compact ? 38 : 54) + media.textScaler.scale(13) * 1.3;
    final topInset =
        media.padding.top +
        (showHeader ? toolbarHeight + (compact ? 2 : 14) : 0);
    final chatVisible = ModalRoute.isCurrentOf(context) ?? true;
    return AtmosphereBackground(
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final messages = session.messages;
          final last = messages.lastOrNull;
          final thinking =
              last?['role'] == 'user' &&
              const {'sending', 'queued', 'running'}.contains(last?['status']);
          final itemCount = messages.length + (thinking ? 1 : 0);
          final scope = session.connection?.scope;
          if (_systemFold case final fold?
              when fold.connection != session.connection) {
            _systemFold = null;
          }
          if (scope != _scope || itemCount != _lastCount) {
            final follow =
                scope != _scope ||
                !_scroll.hasClients ||
                _scroll.position.extentAfter < 90;
            _scope = scope;
            _lastCount = itemCount;
            if (follow && chatVisible) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });
            }
          }

          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              top: false,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: _chatPane(
                        session,
                        thinking: thinking,
                        keyboard: keyboard,
                        topInset: topInset,
                      ),
                    ),
                  ),
                  if (showHeader)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: FadingPageHeader(
                        child: Padding(
                          padding: EdgeInsets.only(top: media.padding.top),
                          child: _header(
                            session,
                            messages,
                            thinking,
                            compact,
                            toolbarHeight,
                          ),
                        ),
                      ),
                    ),
                  if (_systemFold case final fold?) ...[
                    const ModalBarrier(
                      dismissible: false,
                      color: Colors.transparent,
                    ),
                    MascotIsland(
                      key: ValueKey(fold.id),
                      session: session,
                      islandId: fold.id,
                      onReturn: _returnToChat,
                      onSystemFold: (result) =>
                          _systemFoldResult(fold.id, result),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(
    MobileSession session,
    List<Json> messages,
    bool thinking,
    bool compact,
    double toolbarHeight,
  ) {
    final scope = session.connection?.scope;
    final reply = messages.reversed
        .where((m) => m['role'] == 'assistant')
        .firstOrNull;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, compact ? 0 : 6, 8, compact ? 2 : 8),
      child: SizedBox(
        height: toolbarHeight,
        child: NavigationToolbar(
          middleSpacing: 0,
          leading: ListenableBuilder(
            listenable: session.inbox,
            builder: (_, _) => _CalendarEntry(
              unread: session.inbox.hasUnread,
              onPressed: _openSchedule,
            ),
          ),
          middle: FittedBox(
            fit: BoxFit.scaleDown,
            child: ChatMascot(
              key: ValueKey(scope),
              input: _input,
              focus: _focus,
              thinking: thinking,
              replyId: reply?['id'] as String?,
              historyLoaded: session.chatHistoryLoaded,
              compact: compact,
              onFold: _foldAssistant,
            ),
          ),
          trailing: _settingsButton(),
        ),
      ),
    );
  }

  Widget _chatPane(
    MobileSession session, {
    required bool thinking,
    required bool keyboard,
    required double topInset,
  }) {
    final connected = session.connection != null;
    final messages = session.messages;
    final welcome =
        messages.isEmpty && (!connected || session.questions.isEmpty);
    final scrollUnderHeader = messages.isNotEmpty && session.error == null;
    return Column(
      children: [
        if (!scrollUnderHeader) SizedBox(height: topInset),
        if (session.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: _FloatingErrorPill(
              message: session.error!,
              onRetry: connected ? session.sync : null,
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) => _chatContent(
              session,
              messages,
              thinking: thinking,
              welcome: welcome,
              keyboard: keyboard,
              bounds: bounds,
              listTopInset: scrollUnderHeader ? topInset : 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chatContent(
    MobileSession session,
    List<Json> messages, {
    required bool thinking,
    required bool welcome,
    required bool keyboard,
    required BoxConstraints bounds,
    required double listTopInset,
  }) {
    final connected = session.connection != null;
    final showTopics = welcome && !keyboard && bounds.maxHeight > 300;
    return Column(
      children: [
        Expanded(
          child: welcome && bounds.maxHeight < 170
              ? const SizedBox.shrink()
              : welcome
              ? const Align(
                  alignment: Alignment.bottomCenter,
                  child: _Greeting(),
                )
              : _buildChatBody(
                  session: session,
                  messages: messages,
                  thinking: thinking,
                  topInset: listTopInset,
                ),
        ),
        if (session.questions.isNotEmpty && connected)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: bounds.maxHeight * .38),
            child: SingleChildScrollView(
              child: QuestionCards(
                questions: session.questions,
                onAnswer: session.answerQuestion,
                onDismiss: session.dismissQuestion,
              ),
            ),
          ),
        Padding(
          key: const ValueKey('composer'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: ChatComposer(
            input: _input,
            focusNode: _focus,
            session: session,
            connection: session.connection,
            maxLines: bounds.maxHeight < 280 ? 2 : 4,
            showConnect: !connected && !keyboard && bounds.maxHeight >= 280,
            active: ModalRoute.isCurrentOf(context) ?? true,
            onSettings: _settings,
            onSent: _scrollAfterSend,
          ),
        ),
        if (showTopics) ...[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              _TopicButton(
                label: '聊聊今天',
                icon: Icons.wb_sunny_outlined,
                onTap: () => _fillPrompt('我想跟你聊聊今天发生的事。'),
              ),
              _TopicButton(
                label: '想想晚饭',
                icon: Icons.rice_bowl_outlined,
                onTap: () => _fillPrompt('今晚吃点什么好呢？'),
              ),
            ],
          ),
          const Spacer(),
        ],
      ],
    );
  }

  void _fillPrompt(String text) {
    _focus.requestFocus();
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Widget _buildChatBody({
    required MobileSession session,
    required List<Json> messages,
    required bool thinking,
    required double topInset,
  }) {
    return LayoutBuilder(
      builder: (context, layout) => ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          topInset + FadingPageHeader.feather,
          16,
          10,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: messages.length + (thinking ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AssistantThinkingBubble(),
              ),
            );
          }
          final entry = messages[index];
          final prev = index > 0 ? messages[index - 1] : null;
          final stamp = _timestampHeader(entry, prev);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stamp != null) _TimestampDivider(label: stamp),
              _Message(
                entry: entry,
                session: session,
                maxWidth: layout.maxWidth,
                onRetry: () => session.retry(entry),
              ),
            ],
          );
        },
      ),
    );
  }
}

DateTime? _parseOccurredAt(Json entry) {
  final raw = entry['occurred_at'];
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

String? _timestampHeader(Json current, Json? previous) {
  final cur = _parseOccurredAt(current);
  if (cur == null) return null;
  if (previous != null) {
    final prev = _parseOccurredAt(previous);
    if (prev != null && cur.difference(prev).inMinutes.abs() < 5) {
      return null;
    }
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(cur.year, cur.month, cur.day);
  final diffDays = today.difference(day).inDays;
  final hh = cur.hour.toString().padLeft(2, '0');
  final mm = cur.minute.toString().padLeft(2, '0');
  if (diffDays == 0) return '$hh:$mm';
  if (diffDays == 1) return '昨天 $hh:$mm';
  if (cur.year == now.year) return '${cur.month}月${cur.day}日 $hh:$mm';
  return '${cur.year}年${cur.month}月${cur.day}日 $hh:$mm';
}

class _Greeting extends StatelessWidget {
  const _Greeting();
  @override
  Widget build(BuildContext context) => const FittedBox(
    fit: BoxFit.scaleDown,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Text(
        '今天过得怎么样？',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          letterSpacing: -.7,
        ),
      ),
    ),
  );
}

class _TimestampDivider extends StatelessWidget {
  const _TimestampDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final atmo = AppAtmosphere.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 14),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: atmo.sectionHeader.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

class _CalendarEntry extends StatefulWidget {
  const _CalendarEntry({required this.unread, required this.onPressed});
  final bool unread;
  final VoidCallback onPressed;
  @override
  State<_CalendarEntry> createState() => _CalendarEntryState();
}

class _CalendarEntryState extends State<_CalendarEntry>
    with WidgetsBindingObserver {
  int _day = DateTime.now().day;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshDay();
  }

  void _refreshDay() {
    final now = DateTime.now();
    if (_day != now.day) setState(() => _day = now.day);
    _timer?.cancel();
    _timer = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      _refreshDay,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDay();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: TextButton(
        onPressed: widget.onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          foregroundColor: colors.onSurface,
          minimumSize: const Size(48, 48),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Transform.rotate(
                angle: -.07,
                child: Container(
                  width: 25,
                  height: 26,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color: colors.outlineVariant,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(height: 4, color: colors.primary),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '$_day',
                            style: TextStyle(
                              fontFamily: 'serif',
                              fontSize: 15,
                              height: 1.1,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Text('日程', semanticsLabel: widget.unread ? '日程，有未读通知' : '日程'),
            if (widget.unread) ...[
              const SizedBox(width: 4),
              ExcludeSemantics(child: Badge(backgroundColor: colors.primary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _FloatingErrorPill extends StatelessWidget {
  const _FloatingErrorPill({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      radius: 20,
      color: colors.errorContainer.withValues(alpha: 0.92),
      borderColor: colors.error.withValues(alpha: 0.25),
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: colors.onErrorContainer),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: colors.error,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class _TopicButton extends StatelessWidget {
  const _TopicButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.onSurfaceVariant,
        side: BorderSide(color: colors.outlineVariant),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.entry,
    required this.session,
    required this.maxWidth,
    required this.onRetry,
  });
  final Json entry;
  final MobileSession session;
  final double maxWidth;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final user = entry['role'] == 'user';
    final status = const {
      'sending': '正在发送',
      'unsent': '未确认送达',
      'queued': '已排队',
      'running': '处理中',
      'failed': '处理失败',
      'interrupted': '已中断',
      'missing': '任务不存在',
    }[entry['status']];

    final text = entry['text'] as String;
    final body = SelectableText(
      text,
      style: TextStyle(
        color: colors.onSurface,
        fontSize: 15.5,
        height: 1.62,
        letterSpacing: -0.1,
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: user ? 14 : 16),
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: user ? maxWidth * 0.8 : maxWidth * 0.86,
          ),
          child: Column(
            crossAxisAlignment: user
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: user ? '你' : 'Purin',
                child: ChatBubble(
                  fromUser: user,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (user) ...[
                        for (final data
                            in (entry['images'] as List? ?? [])
                                .whereType<String>())
                          if (data.startsWith('data:image/jpeg;base64,'))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: _OutgoingImage(
                                  key: ValueKey(data),
                                  url: data,
                                ),
                              ),
                            ),
                        for (final doc
                            in (entry['documents'] as List? ?? [])
                                .whereType<Json>())
                          _DocumentName(name: doc['name'] as String),
                      ],
                      if (session.connection case final connection? when user)
                        for (final file
                            in (entry['files'] as List? ?? [])
                                .whereType<Json>())
                          if (file['content_type'] == 'image/jpeg' &&
                              file['id'] is String)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: text.trim().isNotEmpty ? 8 : 0,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: _ChatImage(
                                  key: ValueKey((connection, file['id'])),
                                  connection: connection,
                                  api: session.api,
                                  id: file['id'],
                                ),
                              ),
                            )
                          else if (file['name'] is String)
                            _DocumentName(name: file['name']),
                      if (text.trim().isNotEmpty) body,
                    ],
                  ),
                ),
              ),
              if (user && status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (entry['status'] == 'unsent' &&
                          entry['job'] == null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onRetry,
                          child: Text(
                            '重试发送',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutgoingImage extends StatefulWidget {
  const _OutgoingImage({super.key, required this.url});
  final String url;

  @override
  State<_OutgoingImage> createState() => _OutgoingImageState();
}

class _OutgoingImageState extends State<_OutgoingImage> {
  late final bytes = UriData.parse(widget.url).contentAsBytes();

  @override
  Widget build(BuildContext context) => Image.memory(
    bytes,
    cacheWidth: 512,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
  );
}

class _DocumentName extends StatelessWidget {
  const _DocumentName({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.attach_file_rounded, size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

class _ChatImage extends StatefulWidget {
  const _ChatImage({
    super.key,
    required this.connection,
    required this.api,
    required this.id,
  });
  final Connection connection;
  final AgentApi api;
  final String id;
  @override
  State<_ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<_ChatImage> {
  late Future<Uint8List> image = widget.api.chatImage(
    widget.connection,
    widget.id,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: image,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () => setState(() {
            image = widget.api.chatImage(widget.connection, widget.id);
          }),
          child: const Text('重新加载图片'),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 84,
          width: 140,
          child: Center(child: CupertinoActivityIndicator()),
        );
      }
      return Image.memory(
        snapshot.data!,
        height: 150,
        fit: BoxFit.contain,
        semanticLabel: '聊天图片',
      );
    },
  );
}
