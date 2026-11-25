import 'dart:async';
import 'package:flutter/material.dart';

class ChatMascot extends StatefulWidget {
  const ChatMascot({
    super.key,
    required this.input,
    required this.focus,
    required this.thinking,
    required this.replyId,
    required this.historyLoaded,
    required this.compact,
    required this.onFold,
  });
  final TextEditingController input;
  final FocusNode focus;
  final bool thinking, historyLoaded, compact;
  final String? replyId;
  final VoidCallback onFold;

  @override
  State<ChatMascot> createState() => _ChatMascotState();
}

class _ChatMascotState extends State<ChatMascot> {
  Timer? _listeningTimer, _speakingTimer;
  late String _lastText;
  bool _listening = false, _speaking = false;

  @override
  void initState() {
    super.initState();
    _lastText = widget.input.text;
    widget.input.addListener(_onInput);
    widget.focus.addListener(_onFocus);
  }

  void _onInput() {
    final text = widget.input.text;
    if (text == _lastText) return;
    _lastText = text;
    _listeningTimer?.cancel();
    final typing = text.isNotEmpty && widget.focus.hasFocus;
    if (typing != _listening) setState(() => _listening = typing);
    if (typing) {
      _listeningTimer = Timer(
        const Duration(milliseconds: 1500),
        () => setState(() => _listening = false),
      );
    }
  }

  void _onFocus() {
    if (!widget.focus.hasFocus && _listening) {
      _listeningTimer?.cancel();
      setState(() => _listening = false);
    }
  }

  @override
  void didUpdateWidget(ChatMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replyId != widget.replyId) {
      _speakingTimer?.cancel();
      _speaking = widget.replyId != null && oldWidget.historyLoaded;
      if (_speaking) {
        _speakingTimer = Timer(
          const Duration(milliseconds: 3200),
          () => setState(() => _speaking = false),
        );
      }
    }
  }

  @override
  void dispose() {
    _listeningTimer?.cancel();
    _speakingTimer?.cancel();
    widget.input.removeListener(_onInput);
    widget.focus.removeListener(_onFocus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mood = _listening
        ? 'listening'
        : widget.thinking
        ? 'thinking'
        : _speaking
        ? 'speaking'
        : 'idle';
    final suffix = MediaQuery.disableAnimationsOf(context) ? '-still' : '';
    final side = widget.compact ? 32.0 : 46.0;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '收起助手到顶部胶囊',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onFold,
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Hero(
                tag: 'purin-island-cat',
                child: Image.asset(
                  'assets/mascot/$mood$suffix.webp',
                  width: side,
                  height: side,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(height: 4),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: colors.surfaceContainer.withValues(alpha: .94),
                  shape: const StadiumBorder(),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Text(
                    'Purin',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurface,
                    ),
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
