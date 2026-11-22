import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../data/agent_api.dart';
import '../data/device_inbox.dart';
import '../data/mobile_session.dart';
import '../widgets/app_theme.dart';
import '../widgets/question_cards.dart';
import '../widgets/shared.dart';
import 'connection_screen.dart';
import 'inbox_screen.dart';
import 'memory_screen.dart';

enum _HomeTab { chat, memory, inbox }

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

  String _pageNameFor(_HomeTab tab) => switch (tab) {
    _HomeTab.chat => 'Agent 对话',
    _HomeTab.memory => '记忆',
    _HomeTab.inbox => '通知',
  };

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
    if (text.isEmpty || widget.session.connection == null) return;
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
    final topPadding = media.padding.top;
    final bottomPadding = media.padding.bottom;
    final keyboardVisible = media.viewInsets.bottom > 60;
    final headerHeight = topPadding + 58.0;
    final showInboxTab = session.inbox.supported;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AtmosphereBackground(
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final messages = session.messages;
          final connected = session.connection != null;
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

          final atmo = AppAtmosphere.of(context);
          final composerBottom = keyboardVisible
              ? 8.0
              : (bottomPadding > 0 ? bottomPadding + 6.0 : 14.0);

          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: true,
            drawerEdgeDragWidth: 44,
            drawerScrimColor: Colors.black.withValues(
              alpha: dark ? 0.45 : 0.18,
            ),
            onDrawerChanged: (opened) {
              if (opened) FocusManager.instance.primaryFocus?.unfocus();
            },
            drawer: _GlassSidebarDrawer(
              tab: _tab,
              connected: connected,
              deviceName: session.connection?.deviceName,
              showInboxTab: showInboxTab,
              inbox: session.inbox,
              onSelectTab: (tab) {
                Navigator.of(context).pop();
                _selectTab(tab);
              },
              onSettings: () {
                Navigator.of(context).pop();
                _settings();
              },
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          // Main content area
                          Positioned.fill(
                            child: IndexedStack(
                              index: switch (_tab) {
                                _HomeTab.chat => 0,
                                _HomeTab.memory => 1,
                                _HomeTab.inbox => showInboxTab ? 2 : 0,
                              },
                              children: [
                                _buildChatBody(
                                  context,
                                  session: session,
                                  messages: filteredMessages,
                                  totalCount: messages.length,
                                  connected: connected,
                                  topInset:
                                      headerHeight +
                                      (_searching ? 60.0 : 8.0) +
                                      (session.error != null ? 56.0 : 0.0),
                                ),
                                MemoryScreen(
                                  embedded: true,
                                  topInset: headerHeight + 10,
                                  bottomInset: bottomPadding + 28,
                                ),
                                if (showInboxTab)
                                  InboxScreen(
                                    inbox: session.inbox,
                                    embedded: true,
                                    topInset: headerHeight + 10,
                                    bottomInset: bottomPadding + 28,
                                  ),
                              ],
                            ),
                          ),

                          // Soft top atmospheric veil so scrolled content melts cleanly
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: headerHeight + 22,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: const [0.0, 0.56, 1.0],
                                    colors: [
                                      atmo.topFadeColor.withValues(alpha: 0.92),
                                      atmo.topFadeColor.withValues(alpha: 0.48),
                                      atmo.topFadeColor.withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Minimal Floating Top Bar (completely punch-hole & Dynamic-Island safe)
                          Positioned(
                            top: topPadding + 8,
                            left: 16,
                            right: 16,
                            child: _FloatingHeader(
                              tab: _tab,
                              connected: connected,
                              searching: _searching,
                              showInboxTab: showInboxTab,
                              inbox: session.inbox,
                              onMenu: _openDrawer,
                              onSearchToggle: _toggleSearch,
                              onRefreshInbox: session.inbox.refresh,
                            ),
                          ),

                          // Floating Search Bar (when active on Chat tab)
                          if (_tab == _HomeTab.chat && _searching)
                            Positioned(
                              top: headerHeight + 4,
                              left: 16,
                              right: 16,
                              child: _FloatingSearchBar(
                                controller: _searchInput,
                                focusNode: _searchFocus,
                                query: _searchQuery,
                                matchCount: filteredMessages.length,
                                onChanged: (v) =>
                                    setState(() => _searchQuery = v.trim()),
                                onClear: () {
                                  _searchInput.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                            ),

                          // Floating Error Pill (when session has an error)
                          if (_tab == _HomeTab.chat && session.error != null)
                            Positioned(
                              top: headerHeight + (_searching ? 60.0 : 4.0),
                              left: 16,
                              right: 16,
                              child: _FloatingErrorPill(
                                message: session.error!,
                                onRetry: connected ? session.sync : null,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Pending Questions hovering above the floating input capsule
                    if (_tab == _HomeTab.chat &&
                        connected &&
                        session.questions.isNotEmpty)
                      QuestionCards(
                        questions: session.questions,
                        onAnswer: session.answerQuestion,
                        onDismiss: session.dismissQuestion,
                      ),

                    // Minimal Floating Input Capsule (Chat tab only)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _tab == _HomeTab.chat
                          ? Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                4,
                                16,
                                composerBottom,
                              ),
                              child: _FloatingComposer(
                                connected: connected,
                                ready: session.ready,
                                input: _input,
                                focusNode: _focus,
                                onSend: _send,
                                onSettings: _settings,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChatBody(
    BuildContext context, {
    required MobileSession session,
    required List<Json> messages,
    required int totalCount,
    required bool connected,
    required double topInset,
  }) {
    if (totalCount == 0) {
      return _EmptyThread(
        ready: session.ready,
        connected: connected,
        topInset: topInset,
        onSettings: _settings,
      );
    }
    if (messages.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: topInset * 0.5),
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
        padding: EdgeInsets.fromLTRB(16, topInset, 16, 10),
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

class _FloatingHeader extends StatelessWidget {
  const _FloatingHeader({
    required this.tab,
    required this.connected,
    required this.searching,
    required this.showInboxTab,
    required this.inbox,
    required this.onMenu,
    required this.onSearchToggle,
    required this.onRefreshInbox,
  });

  final _HomeTab tab;
  final bool connected;
  final bool searching;
  final bool showInboxTab;
  final DeviceInbox inbox;
  final VoidCallback onMenu;
  final VoidCallback onSearchToggle;
  final VoidCallback onRefreshInbox;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = switch (tab) {
      _HomeTab.chat => 'Wintermute',
      _HomeTab.memory => '记忆',
      _HomeTab.inbox => '通知',
    };

    Widget rightButton;
    if (tab == _HomeTab.chat) {
      rightButton = GlassIconButton(
        icon: searching ? Icons.close_rounded : Icons.search_rounded,
        active: searching,
        tooltip: searching ? '关闭搜索' : '搜索对话',
        onPressed: onSearchToggle,
      );
    } else if (tab == _HomeTab.memory) {
      rightButton = const SizedBox(width: 42, height: 42);
    } else {
      rightButton = GlassIconButton(
        icon: Icons.refresh_rounded,
        tooltip: '刷新通知',
        onPressed: onRefreshInbox,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ListenableBuilder(
          listenable: inbox,
          builder: (_, _) => GlassIconButton(
            icon: Icons.menu_rounded,
            tooltip: '导航菜单',
            badge: showInboxTab && inbox.unread > 0,
            onPressed: onMenu,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab == _HomeTab.chat && !connected) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: colors.onSurface.withValues(alpha: 0.86),
              ),
            ),
          ],
        ),
        rightButton,
      ],
    );
  }
}

/// Floating Apple-style frosted glass sidebar drawer (ChatGPT / iPadOS aesthetic).
class _GlassSidebarDrawer extends StatelessWidget {
  const _GlassSidebarDrawer({
    required this.tab,
    required this.connected,
    required this.deviceName,
    required this.showInboxTab,
    required this.inbox,
    required this.onSelectTab,
    required this.onSettings,
  });

  final _HomeTab tab;
  final bool connected;
  final String? deviceName;
  final bool showInboxTab;
  final DeviceInbox inbox;
  final ValueChanged<_HomeTab> onSelectTab;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    final width = (MediaQuery.sizeOf(context).width * 0.78).clamp(264.0, 320.0);

    return Drawer(
      width: width,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 0, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: atmo.shadowColor,
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  decoration: BoxDecoration(
                    color: atmo.dockFill,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: atmo.dockBorder, width: 0.9),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Brand Identity Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                        child: Row(
                          children: [
                            const BrandMark(size: 38),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Wintermute',
                                    style: TextStyle(
                                      fontSize: 17.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.35,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: connected
                                              ? colors.primary
                                              : colors.onSurfaceVariant
                                                    .withValues(alpha: 0.45),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          connected
                                              ? (deviceName?.isNotEmpty == true
                                                    ? deviceName!
                                                    : '已连接')
                                              : '尚未连接服务',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Primary Navigation Items (infinitely scalable)
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            _DrawerNavItem(
                              label: '对话',
                              icon: Icons.chat_bubble_outline_rounded,
                              activeIcon: Icons.chat_bubble_rounded,
                              selected: tab == _HomeTab.chat,
                              onTap: () => onSelectTab(_HomeTab.chat),
                            ),
                            const SizedBox(height: 4),
                            _DrawerNavItem(
                              label: '记忆',
                              icon: Icons.auto_awesome_outlined,
                              activeIcon: Icons.auto_awesome_rounded,
                              selected: tab == _HomeTab.memory,
                              onTap: () => onSelectTab(_HomeTab.memory),
                            ),
                            if (showInboxTab) ...[
                              const SizedBox(height: 4),
                              ListenableBuilder(
                                listenable: inbox,
                                builder: (_, _) => _DrawerNavItem(
                                  label: '通知',
                                  icon: Icons.notifications_none_rounded,
                                  activeIcon: Icons.notifications_rounded,
                                  selected: tab == _HomeTab.inbox,
                                  badgeCount: inbox.unread,
                                  onTap: () => onSelectTab(_HomeTab.inbox),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Pinned Settings Footer
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Divider(
                                height: 0.6,
                                thickness: 0.6,
                                color: atmo.hairline,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _DrawerNavItem(
                              label: '设置与连接',
                              icon: Icons.settings_outlined,
                              activeIcon: Icons.settings_outlined,
                              selected: false,
                              trailingChevron: true,
                              onTap: onSettings,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
    this.trailingChevron = false,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;
  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    return Material(
      color: selected ? atmo.activeTabPill : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
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
                )
              else if (trailingChevron)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.6),
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
      blur: 18,
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
      blur: 16,
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

/// Pure, feather-light floating glass input capsule at the bottom of the Chat screen.
class _FloatingComposer extends StatelessWidget {
  const _FloatingComposer({
    required this.connected,
    required this.ready,
    required this.input,
    required this.focusNode,
    required this.onSend,
    required this.onSettings,
  });

  final bool connected;
  final bool ready;
  final TextEditingController input;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);

    if (!connected) {
      return GlassCard(
        radius: 26,
        blur: 20,
        color: atmo.dockFill,
        borderColor: atmo.dockBorder,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: ready ? onSettings : null,
            borderRadius: BorderRadius.circular(26),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '连接服务后即可开始对话',
                      style: TextStyle(
                        fontSize: 14.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '去设置',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GlassCard(
      radius: 26,
      blur: 22,
      color: atmo.dockFill,
      borderColor: focusNode.hasFocus
          ? colors.primary.withValues(alpha: 0.42)
          : atmo.dockBorder,
      padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: input,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              textInputAction: TextInputAction.newline,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.45,
                color: colors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: '发消息给 Wintermute…',
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                ),
                counterText: '',
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ValueListenableBuilder(
              valueListenable: input,
              builder: (context, value, _) {
                final canSend = value.text.trim().isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: canSend
                        ? colors.primary
                        : colors.onSurface.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: canSend ? onSend : null,
                      customBorder: const CircleBorder(),
                      child: Tooltip(
                        message: '发送消息',
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          size: 19,
                          color: canSend
                              ? colors.onPrimary
                              : colors.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread({
    required this.ready,
    required this.connected,
    required this.topInset,
    required this.onSettings,
  });
  final bool ready, connected;
  final double topInset;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, layout) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, topInset, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (layout.maxHeight - topInset - 24).clamp(
              0,
              double.infinity,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: GlassCard(
                radius: 28,
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandMark(size: 52),
                    const SizedBox(height: 18),
                    Text(
                      connected ? '今天聊些什么？' : '连接你的 Agent',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.3,
                        letterSpacing: -0.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      connected
                          ? '在下方输入框写下想法，Wintermute 会安静陪你处理日常。'
                          : '从管理面板获取配对码，即可开始对话与跨设备同步。',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: colors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (!connected) ...[
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: ready ? onSettings : null,
                        label: const Text('设置连接'),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        iconAlignment: IconAlignment.end,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
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
              if (user)
                Semantics(
                  label: '你',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 11,
                      horizontal: 15,
                    ),
                    decoration: BoxDecoration(
                      color: atmo.userBubbleFill,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(6),
                      ),
                      border: Border.all(
                        color: atmo.userBubbleBorder,
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (session.connection case final connection?)
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
                )
              else
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                  decoration: BoxDecoration(
                    color: atmo.assistantBubbleFill,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                      bottomLeft: Radius.circular(6),
                    ),
                    border: Border.all(color: atmo.cardBorder, width: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: atmo.shadowColor,
                        blurRadius: 16,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: body,
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
