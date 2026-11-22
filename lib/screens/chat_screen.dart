import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../data/agent_api.dart';
import '../data/device_inbox.dart';
import '../data/mobile_session.dart';
import '../widgets/app_theme.dart';
import '../widgets/chat_mascot.dart';
import '../widgets/question_cards.dart';
import '../widgets/shared.dart';
import 'connection_screen.dart';
import 'inbox_screen.dart';
import 'memory_screen.dart';
import 'schedule_screen.dart';

enum _HomeTab {
  chat('对话', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
  schedule('日程', Icons.calendar_month_outlined, Icons.calendar_month_rounded),
  memory('记忆', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
  inbox('通知', Icons.notifications_none_rounded, Icons.notifications_rounded);

  const _HomeTab(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon, activeIcon;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.session});
  final MobileSession session;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _input = TextEditingController();
  final _searchInput = TextEditingController();
  final _focus = FocusNode();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();

  _HomeTab _tab = _HomeTab.chat;
  bool _searching = false;
  String _searchQuery = '';
  int _lastCount = 0;
  String? _scope;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_updateFocus);
    widget.session.inbox.onOpen = (_, id) => _inbox(id);
    widget.session.inbox.onArrival = _arrival;
  }

  void _arrival(DeviceNotice notice) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(notice.title),
        action: SnackBarAction(label: '查看', onPressed: () => _inbox(notice.id)),
      ),
    );
  }

  void _inbox([String? id]) {
    if (!mounted) return;
    if (id != null) {
      _open('通知', InboxScreen(inbox: widget.session.inbox, initialNotice: id));
    } else if (widget.session.inbox.supported) {
      _selectTab(_HomeTab.inbox);
    } else {
      _open('通知', InboxScreen(inbox: widget.session.inbox));
    }
  }

  void _updateFocus() => setState(() {});

  String _pageNameFor(_HomeTab tab) =>
      tab == _HomeTab.chat ? 'Agent 对话' : tab.label;

  void _openDrawer() {
    FocusManager.instance.primaryFocus?.unfocus();
    _scaffoldKey.currentState?.openDrawer();
  }

  void _selectTab(_HomeTab tab) {
    if (_tab == tab) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tab = tab;
      if (tab != _HomeTab.chat && _searching) {
        _searching = false;
        _searchQuery = '';
        _searchInput.clear();
      }
    });
    widget.session.page(_pageNameFor(tab));
    if (tab == _HomeTab.inbox) {
      widget.session.inbox.refresh();
    }
  }

  Future<void> _open(String name, Widget page) async {
    FocusManager.instance.primaryFocus?.unfocus();
    widget.session.page(name);
    await Navigator.of(context).push(appleRoute<void>(page));
    if (mounted) widget.session.page(_pageNameFor(_tab));
  }

  void _settings() => _open('连接与采集', ConnectionScreen(session: widget.session));

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchQuery = '';
        _searchInput.clear();
        _searchFocus.unfocus();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocus.requestFocus();
        });
      }
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    if (widget.session.connection == null) {
      _settings();
      return;
    }
    widget.session.send(text);
    _input.clear();
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
    widget.session.inbox.onOpen = null;
    widget.session.inbox.onArrival = null;
    _input.dispose();
    _searchInput.dispose();
    _focus.dispose();
    _searchFocus.dispose();
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
    final android = Theme.of(context).platform == TargetPlatform.android;
    final tabs = [
      _HomeTab.chat,
      if (android) _HomeTab.schedule else _HomeTab.memory,
      if (session.inbox.supported) _HomeTab.inbox,
    ];
    return AtmosphereBackground(
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final messages = session.messages;
          final scope = session.connection?.scope;
          if (scope != _scope || messages.length != _lastCount) {
            final follow =
                scope != _scope ||
                !_scroll.hasClients ||
                _scroll.position.extentAfter < 90;
            _scope = scope;
            _lastCount = messages.length;
            if (follow && _tab == _HomeTab.chat && _searchQuery.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });
            }
          }

          final filteredMessages = _searchQuery.isEmpty
              ? messages
              : messages
                    .where(
                      (m) => (m['text'] as String? ?? '')
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()),
                    )
                    .toList();

          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.transparent,
            drawerEdgeDragWidth: 44,
            drawerScrimColor: Colors.black.withValues(alpha: .22),
            onDrawerChanged: (opened) {
              if (opened) FocusManager.instance.primaryFocus?.unfocus();
            },
            drawer: _SidebarDrawer(
              tab: _tab,
              inbox: session.inbox,
              tabs: tabs,
              onSelectTab: (tab) {
                Navigator.of(context).pop();
                _selectTab(tab);
              },
              onSettings: () {
                Navigator.of(context).pop();
                _settings();
              },
            ),
            body: SafeArea(
              child: Column(
                children: [
                  if (!keyboard || availableHeight >= 200)
                    _header(session, messages, compact),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: IndexedStack(
                          index: tabs.indexOf(_tab),
                          children: [
                            _chatPane(
                              session,
                              filteredMessages,
                              empty: messages.isEmpty,
                              keyboard: keyboard,
                            ),
                            if (_tab == _HomeTab.schedule)
                              ScheduleScreen(
                                key: ObjectKey(session.connection),
                                api: session.api,
                                connection: session.connection,
                                inbox: session.inbox,
                                onSettings: _settings,
                                onInbox: () => _selectTab(_HomeTab.inbox),
                                onNotice: (notice) => _open(
                                  '通知',
                                  NoticeDetail(
                                    inbox: session.inbox,
                                    notice: notice,
                                  ),
                                ),
                              )
                            else if (android)
                              const SizedBox.shrink()
                            else
                              const MemoryScreen(
                                embedded: true,
                                topInset: 8,
                                bottomInset: 16,
                              ),
                            if (session.inbox.supported)
                              InboxScreen(
                                inbox: session.inbox,
                                embedded: true,
                                topInset: 8,
                                bottomInset: 16,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(MobileSession session, List<Json> messages, bool compact) {
    final scope = session.connection?.scope;
    final showInboxTab = session.inbox.supported;
    final last = messages.lastOrNull;
    final thinking =
        last?['role'] == 'user' &&
        const {'sending', 'queued', 'running'}.contains(last?['status']);
    final reply = messages.reversed
        .where((m) => m['role'] == 'assistant')
        .firstOrNull;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, compact ? 0 : 6, 8, compact ? 2 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListenableBuilder(
            listenable: session.inbox,
            builder: (_, _) => GlassIconButton(
              icon: Icons.menu_rounded,
              tooltip: '导航菜单',
              badge: showInboxTab && session.inbox.unread > 0,
              onPressed: _openDrawer,
            ),
          ),
          Expanded(
            child: Center(
              child: _tab == _HomeTab.chat
                  ? ChatMascot(
                      key: ValueKey(scope),
                      input: _input,
                      focus: _focus,
                      thinking: thinking,
                      replyId: reply?['id'] as String?,
                      historyLoaded: session.chatHistoryLoaded,
                      compact: compact,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _pageNameFor(_tab),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(
            width: 48,
            child: _tab == _HomeTab.inbox
                ? GlassIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: '刷新通知',
                    onPressed: session.inbox.refresh,
                  )
                : _tab == _HomeTab.chat && (messages.isNotEmpty || _searching)
                ? GlassIconButton(
                    icon: _searching
                        ? Icons.close_rounded
                        : Icons.search_rounded,
                    tooltip: _searching ? '关闭搜索' : '搜索对话',
                    active: _searching,
                    onPressed: _toggleSearch,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _chatPane(
    MobileSession session,
    List<Json> filteredMessages, {
    required bool empty,
    required bool keyboard,
  }) {
    final connected = session.connection != null;
    final welcome =
        empty && (!connected || session.questions.isEmpty) && !_searching;
    return Column(
      children: [
        if (_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: _FloatingSearchBar(
              controller: _searchInput,
              focusNode: _searchFocus,
              query: _searchQuery,
              matchCount: filteredMessages.length,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              onClear: () {
                _searchInput.clear();
                setState(() => _searchQuery = '');
              },
            ),
          ),
        if (session.error != null && (!_searching || !keyboard))
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
              filteredMessages,
              welcome: welcome,
              keyboard: keyboard,
              bounds: bounds,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chatContent(
    MobileSession session,
    List<Json> filteredMessages, {
    required bool welcome,
    required bool keyboard,
    required BoxConstraints bounds,
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
                  context,
                  session: session,
                  messages: filteredMessages,
                ),
        ),
        if (session.questions.isNotEmpty &&
            connected &&
            (!_searching || !keyboard))
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
        if (!_searching || !keyboard)
          Padding(
            key: const ValueKey('composer'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _Composer(
              input: _input,
              focusNode: _focus,
              connected: connected,
              ready: session.ready,
              compact: bounds.maxHeight < 280 || keyboard,
              onSettings: _settings,
              onSend: _send,
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

  Widget _buildChatBody(
    BuildContext context, {
    required MobileSession session,
    required List<Json> messages,
  }) {
    if (messages.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            radius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Text(
              '没有包含「$_searchQuery」的对话',
              style: TextStyle(
                fontSize: 14.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, layout) => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: messages.length,
        itemBuilder: (context, index) {
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

class _SidebarDrawer extends StatelessWidget {
  const _SidebarDrawer({
    required this.tab,
    required this.inbox,
    required this.tabs,
    required this.onSelectTab,
    required this.onSettings,
  });
  final _HomeTab tab;
  final DeviceInbox inbox;
  final List<_HomeTab> tabs;
  final ValueChanged<_HomeTab> onSelectTab;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Drawer(
      width: (MediaQuery.sizeOf(context).width * .76).clamp(0, 268).toDouble(),
      backgroundColor: Colors.transparent,
      elevation: 0,
      semanticLabel: '导航菜单',
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
          child: Material(
            color: colors.surfaceContainer,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ListenableBuilder(
                    listenable: inbox,
                    builder: (_, _) => ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: tabs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (_, index) {
                        final item = tabs[index];
                        return _DrawerNavItem(
                          label: item.label,
                          icon: item.icon,
                          activeIcon: item.activeIcon,
                          selected: tab == item,
                          badgeCount: item == _HomeTab.inbox ? inbox.unread : 0,
                          onTap: () => onSelectTab(item),
                        );
                      },
                    ),
                  ),
                ),
                Divider(
                  indent: 14,
                  endIndent: 14,
                  height: 1,
                  color: colors.outlineVariant,
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: _DrawerNavItem(
                    label: '设置',
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings_outlined,
                    selected: false,
                    onTap: onSettings,
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

class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    return Material(
      color: selected ? atmo.activeTabPill : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12.5),
          child: Row(
            children: [
              Icon(
                selected ? activeIcon : icon,
                size: 20,
                color: selected ? colors.onSurface : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    letterSpacing: -0.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? colors.onSurface
                        : colors.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7.5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingSearchBar extends StatelessWidget {
  const _FloatingSearchBar({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.matchCount,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final int matchCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    return GlassCard(
      radius: 22,
      color: atmo.dockFill,
      borderColor: atmo.dockBorder,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          const SizedBox(width: 10),
          Icon(Icons.search_rounded, size: 19, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: TextStyle(fontSize: 14.5, color: colors.onSurface),
              decoration: const InputDecoration(
                filled: false,
                isDense: true,
                hintText: '搜索对话内容…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (query.isNotEmpty) ...[
            Text(
              '$matchCount 条',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            IconButton(
              tooltip: '清除',
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: Icon(
                Icons.close_rounded,
                size: 17,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.focusNode,
    required this.connected,
    required this.ready,
    required this.compact,
    required this.onSettings,
    required this.onSend,
  });
  final TextEditingController input;
  final FocusNode focusNode;
  final bool connected, ready, compact;
  final VoidCallback onSettings, onSend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final field = TextField(
      controller: input,
      focusNode: focusNode,
      minLines: 1,
      maxLines: compact ? 2 : 4,
      maxLength: 2000,
      textInputAction: TextInputAction.newline,
      style: TextStyle(fontSize: 16, height: 1.45, color: colors.onSurface),
      decoration: const InputDecoration(
        hintText: '想说点什么？',
        counterText: '',
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
      ),
    );
    final send = ValueListenableBuilder(
      valueListenable: input,
      builder: (context, value, _) {
        return IconButton.filled(
          tooltip: '发送消息',
          onPressed: ready && value.text.trim().isNotEmpty ? onSend : null,
          style: IconButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            disabledBackgroundColor: colors.surfaceContainerHigh,
            disabledForegroundColor: colors.onSurfaceVariant,
            minimumSize: const Size.square(36),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          icon: const Icon(Icons.arrow_upward_rounded, size: 20),
        );
      },
    );
    final pair = TextButton(onPressed: onSettings, child: const Text('去连接'));
    return GlassCard(
      radius: 20,
      color: colors.surfaceContainer,
      borderColor: focusNode.hasFocus ? colors.primary : colors.outline,
      padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.only(
                right: compact ? (!connected && ready ? 124 : 50) : 0,
                bottom: compact ? 0 : 44,
              ),
              child: field,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!compact) ...[
                if (!connected && ready) pair,
                const Spacer(),
              ] else if (!connected && ready)
                pair,
              send,
            ],
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
    final atmo = AppAtmosphere.of(context);
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
                label: user ? '你' : 'Wintermute',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: user
                        ? atmo.userBubbleFill
                        : atmo.assistantBubbleFill,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                            ),
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
