import 'package:flutter/material.dart';
import '../data/agent_api.dart';
import '../data/device_inbox.dart';
import 'inbox_screen.dart';
import '../data/mobile_session.dart';
import '../widgets/shared.dart';
import 'memory_screen.dart';
import 'connection_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.session});
  final MobileSession session;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
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
    if (mounted) {
      _open('通知', InboxScreen(inbox: widget.session.inbox, initialNotice: id));
    }
  }

  void _updateFocus() => setState(() {});

  Future<void> _open(String name, Widget page) async {
    FocusManager.instance.primaryFocus?.unfocus();
    widget.session.page(name);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) widget.session.page('Agent 对话');
  }

  void _settings() => _open('连接与采集', ConnectionScreen(session: widget.session));

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || widget.session.connection == null) return;
    widget.session.send(text);
    _input.clear();
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  void dispose() {
    widget.session.inbox.onOpen = null;
    widget.session.inbox.onArrival = null;
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 20,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 32),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Wintermute',
                style: wordmarkStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (session.inbox.supported)
            ListenableBuilder(
              listenable: session.inbox,
              builder: (_, _) => IconButton(
                tooltip: '通知收件箱',
                onPressed: _inbox,
                icon: Badge(
                  isLabelVisible: session.inbox.unread > 0,
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
            ),
          IconButton(
            tooltip: '浏览记忆',
            onPressed: () => _open('记忆', const MemoryScreen()),
            icon: const Icon(Icons.bookmarks_outlined, size: 21),
          ),
          IconButton(
            tooltip: '连接与采集',
            onPressed: _settings,
            icon: const Icon(Icons.tune_rounded, size: 22),
          ),
          const SizedBox(width: 6),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
                  if (follow) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _scroll.hasClients) {
                        _scroll.jumpTo(_scroll.position.maxScrollExtent);
                      }
                    });
                  }
                }
                return Column(
                  children: [
                    if (session.error != null)
                      Material(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  session.error!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                              if (connected)
                                TextButton(
                                  onPressed: session.sync,
                                  child: const Text('重试'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: messages.isEmpty
                          ? _EmptyThread(
                              ready: session.ready,
                              connected: connected,
                              onSettings: _settings,
                            )
                          : LayoutBuilder(
                              builder: (context, layout) => ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.fromLTRB(
                                  22,
                                  28,
                                  22,
                                  4,
                                ),
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final e = messages[index];
                                  return _Message(
                                    entry: e,
                                    maxWidth: layout.maxWidth,
                                    onRetry: () => session.retry(e),
                                  );
                                },
                              ),
                            ),
                    ),
                    if (connected)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: _focus.hasFocus
                                  ? Theme.of(context).colorScheme.secondary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _input,
                                  focusNode: _focus,
                                  minLines: 1,
                                  maxLines: 4,
                                  maxLength: 2000,
                                  textInputAction: TextInputAction.newline,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.45,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: '发消息给 Wintermute',
                                    counterText: '',
                                    filled: false,
                                    contentPadding: EdgeInsets.fromLTRB(
                                      12,
                                      13,
                                      8,
                                      13,
                                    ),
                                    border: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                  ),
                                ),
                              ),
                              ValueListenableBuilder(
                                valueListenable: _input,
                                builder: (context, value, _) => IconButton(
                                  tooltip: '发送消息',
                                  onPressed: value.text.trim().isEmpty
                                      ? null
                                      : _send,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                    disabledBackgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                    disabledForegroundColor: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    visualDensity: VisualDensity.standard,
                                  ),
                                  icon: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 21,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread({
    required this.ready,
    required this.connected,
    required this.onSettings,
  });
  final bool ready, connected;
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, layout) => SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: layout.maxHeight),
        child: Align(
          alignment: const Alignment(0, -.16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    connected
                        ? Icons.forum_outlined
                        : Icons.chat_bubble_outline_rounded,
                    size: 36,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    connected ? '今天聊些什么？' : '连接你的 Agent',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      height: 1.3,
                      letterSpacing: -.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!connected) ...[
                    const SizedBox(height: 10),
                    Text(
                      '填入服务地址和终端令牌，即可开始对话。',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.65,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
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

class _Message extends StatelessWidget {
  const _Message({
    required this.entry,
    required this.maxWidth,
    required this.onRetry,
  });
  final Json entry;
  final double maxWidth;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final user = entry['role'] == 'user';
    final notice = entry['layer'] == 'notification';
    final status = const {
      'sending': '正在发送',
      'unsent': '未确认送达',
      'queued': '已排队',
      'running': '处理中',
      'failed': '处理失败',
      'interrupted': '已中断',
      'missing': '任务不存在',
    }[entry['status']];
    final body = SelectableText(
      entry['text'] as String,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 16,
        height: 1.65,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: user ? 18 : 28),
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: user ? maxWidth * .78 : maxWidth - 44,
          ),
          child: Column(
            crossAxisAlignment: user
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!user) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (notice)
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )
                    else
                      const BrandMark(size: 19),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        notice ? '后台通知' : 'Wintermute',
                        style: TextStyle(
                          fontSize: notice ? 13 : 16,
                          fontFamily: notice ? null : 'serif',
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: notice
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (user)
                Semantics(
                  label: '你',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 15,
                      ),
                      child: body,
                    ),
                  ),
                )
              else if (notice)
                Container(
                  padding: const EdgeInsets.only(left: 13),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                        width: 2,
                      ),
                    ),
                  ),
                  child: body,
                )
              else
                body,
              if (user && status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 4),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (user && entry['status'] == 'unsent' && entry['job'] == null)
                TextButton(onPressed: onRetry, child: const Text('重试发送')),
            ],
          ),
        ),
      ),
    );
  }
}
