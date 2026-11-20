import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../data/question.dart';
import 'app_theme.dart';
import 'shared.dart';

class QuestionCards extends StatefulWidget {
  const QuestionCards({
    super.key,
    required this.questions,
    required this.onAnswer,
    required this.onDismiss,
  });

  final List<PendingQuestion> questions;
  final Future<void> Function(
    String id, {
    required List<String> selectedOptions,
    required String answerText,
  })
  onAnswer;
  final Future<void> Function(String id) onDismiss;

  @override
  State<QuestionCards> createState() => _QuestionCardsState();
}

class _QuestionCardsState extends State<QuestionCards> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) return const SizedBox.shrink();
    final safeIndex = _index >= widget.questions.length ? 0 : _index;
    final item = widget.questions[safeIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: _QuestionCard(
        key: ValueKey(item.id),
        item: item,
        index: safeIndex,
        total: widget.questions.length,
        onPrev: () => setState(
          () => _index =
              (safeIndex - 1 + widget.questions.length) %
              widget.questions.length,
        ),
        onNext: () =>
            setState(() => _index = (safeIndex + 1) % widget.questions.length),
        onAnswer: widget.onAnswer,
        onDismiss: widget.onDismiss,
      ),
    );
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({
    super.key,
    required this.item,
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
    required this.onAnswer,
    required this.onDismiss,
  });

  final PendingQuestion item;
  final int index;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final Future<void> Function(
    String id, {
    required List<String> selectedOptions,
    required String answerText,
  })
  onAnswer;
  final Future<void> Function(String id) onDismiss;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  final _selected = <String>[];
  final _input = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _toggleOption(String option) {
    setState(() {
      _error = null;
      if (widget.item.multiSelect) {
        if (_selected.contains(option)) {
          _selected.remove(option);
        } else {
          _selected.add(option);
        }
      } else {
        if (_selected.length == 1 && _selected.first == option) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..add(option);
        }
      }
    });
  }

  bool get _canSubmit =>
      !_submitting && (_selected.isNotEmpty || _input.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onAnswer(
        widget.item.id,
        selectedOptions: List<String>.from(_selected),
        answerText: _input.text.trim(),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _dismiss() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onDismiss(widget.item.id);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    final showCustom = widget.item.allowCustom || widget.item.options.isEmpty;

    return GlassCard(
      radius: 24,
      blur: 18,
      color: atmo.dockFill,
      borderColor: atmo.dockBorder,
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                widget.item.multiSelect ? '待回答 · 可多选' : '待回答',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
              const Spacer(),
              if (widget.total > 1) ...[
                _MiniIconTap(
                  tooltip: '上一条',
                  icon: Icons.chevron_left_rounded,
                  onTap: widget.onPrev,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '${widget.index + 1}/${widget.total}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                _MiniIconTap(
                  tooltip: '下一条',
                  icon: Icons.chevron_right_rounded,
                  onTap: widget.onNext,
                ),
                const SizedBox(width: 4),
              ],
              _MiniIconTap(
                tooltip: '忽略提问',
                icon: Icons.close_rounded,
                onTap: _submitting ? null : _dismiss,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.item.title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
              letterSpacing: -0.2,
            ),
          ),
          if (widget.item.question.isNotEmpty) ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 88),
              child: SingleChildScrollView(
                child: Text(
                  widget.item.question,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
          if (widget.item.options.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in widget.item.options)
                  ApplePillChip(
                    label: option,
                    selected: _selected.contains(option),
                    onTap: _submitting ? null : () => _toggleOption(option),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (showCustom)
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_submitting,
                    minLines: 1,
                    maxLines: 2,
                    textInputAction: TextInputAction.send,
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.item.options.isNotEmpty
                          ? '补充说明（可选）'
                          : '输入你的回答…',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: colors.primary.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    '选择上方选项后提交',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              ValueListenableBuilder(
                valueListenable: _input,
                builder: (context, _, _) => FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: _submitting
                      ? const CupertinoActivityIndicator(radius: 8)
                      : const Text('提交'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: TextStyle(fontSize: 12, color: colors.error)),
          ],
        ],
      ),
    );
  }
}

class _MiniIconTap extends StatelessWidget {
  const _MiniIconTap({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}
