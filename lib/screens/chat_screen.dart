import 'package:flutter/material.dart';
import '../main.dart';
import '../data/demo_data.dart';
import '../widgets/shared.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<({bool user, String text})> _messages = [];
  void _send([String? prompt]) {
    final text = (prompt ?? _input.text).trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add((user: true, text: text));
      _messages.add((user: false, text: demoReply));
      _input.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('和 Wintermute 聊聊', style: TextStyle(fontSize: 17)),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '本地模拟对话 · 离开此页面后清空',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(32),
                        children: [
                          const SizedBox(height: 36),
                          const Center(child: BrandMark(size: 52)),
                          const SizedBox(height: 25),
                          const Text(
                            '我在这里，听你说。',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 23),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            '可以说说今天，也可以只是一个突然的想法。',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted, height: 1.8),
                          ),
                          const SizedBox(height: 28),
                          OutlinedButton(
                            onPressed: () => _send('帮我回顾一下今天'),
                            child: const Text('帮我回顾一下今天'),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(20),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return Align(
                            alignment: message.user
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 480),
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: message.user
                                    ? const Color(0xFF35432E)
                                    : surface,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.user ? '你' : 'Wintermute · 模拟回复',
                                    style: const TextStyle(
                                      color: accent,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    message.text,
                                    style: const TextStyle(
                                      height: 1.9,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: '有什么想和我说的？',
                          counterText: '',
                          semanticCounterText: '最多 2000 字',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: '发送消息',
                      onPressed: _send,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
