import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../l10n/app_language.dart';
import '../data/agent_api.dart';
import '../data/chat_attachment.dart';
import '../data/chat_dictation.dart';
import '../data/mobile_session.dart';
import 'shared.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.input,
    required this.focusNode,
    required this.session,
    required this.connection,
    required this.maxLines,
    required this.showConnect,
    required this.active,
    required this.onSettings,
    required this.onSent,
  });
  final TextEditingController input;
  final FocusNode focusNode;
  final MobileSession session;
  final Connection? connection;
  final int maxLines;
  final bool showConnect, active;
  final VoidCallback onSettings, onSent;
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

enum _VoicePhase { idle, permission, recording, transcribing }

/// Measures the controls first so wrapping always uses the inline editor width.
class _ComposerRow extends MultiChildRenderObjectWidget {
  _ComposerRow({
    required this.draft,
    required Widget leading,
    required Widget editor,
    required Widget trailing,
  }) : super(children: [leading, editor, trailing]);

  final String draft;

  @override
  _RenderComposerRow createRenderObject(BuildContext context) =>
      _RenderComposerRow(draft, Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderComposerRow renderObject,
  ) => renderObject.update(draft, Directionality.of(context));
}

class _ComposerParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderComposerRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ComposerParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ComposerParentData> {
  _RenderComposerRow(this._draft, this._direction);
  static final _lineBreak = RegExp(r'[\n-\r\u0085\u2028\u2029]');
  String _draft;
  TextDirection _direction;

  void update(String draft, TextDirection direction) {
    if (draft == _draft && direction == _direction) return;
    _draft = draft;
    _direction = direction;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ComposerParentData) {
      child.parentData = _ComposerParentData();
    }
  }

  Size _layout(BoxConstraints bounds, {required bool dry}) {
    final leading = firstChild!,
        trailing = lastChild!,
        editor = childAfter(leading)!;
    final measure = dry
        ? ChildLayoutHelper.dryLayoutChild
        : ChildLayoutHelper.layoutChild;
    final start = measure(leading, bounds.loosen());
    final end = measure(trailing, bounds.loosen());
    final width = bounds.maxWidth;
    final inlineWidth = math.max(0.0, width - start.width - end.width);
    final expanded =
        _draft.isNotEmpty &&
        (_lineBreak.hasMatch(_draft) ||
            editor.getMaxIntrinsicWidth(double.infinity) > inlineWidth);
    final field = measure(
      editor,
      BoxConstraints.tightFor(width: expanded ? width : inlineWidth),
    );
    final buttonsHeight = math.max(start.height, end.height);
    final rowHeight = expanded
        ? buttonsHeight
        : math.max(buttonsHeight, field.height);
    final rowTop = expanded ? field.height : 0.0;

    if (!dry) {
      void place(RenderBox child, double x, double y) {
        final data = child.parentData! as _ComposerParentData;
        data.offset = Offset(
          _direction == TextDirection.ltr ? x : width - child.size.width - x,
          y,
        );
      }

      place(leading, 0, rowTop + (rowHeight - start.height) / 2);
      place(trailing, width - end.width, rowTop + (rowHeight - end.height) / 2);
      place(
        editor,
        expanded ? 0 : start.width,
        expanded ? 0 : (rowHeight - field.height) / 2,
      );
    }
    return bounds.constrain(Size(width, rowTop + rowHeight));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, dry: true);
  @override
  void performLayout() => size = _layout(constraints, dry: false);
  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _ChatComposerState extends State<ChatComposer>
    with WidgetsBindingObserver {
  final _attachments = <ChatAttachment>[];
  bool _picking = false;
  Completer<void>? _upload;
  ChatDictation? _voice;
  _VoicePhase _phase = _VoicePhase.idle;
  String? _error, _uploadingName;
  bool get _busy => _picking || _upload != null || _voice != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _voice?.cancel();
    if (oldWidget.connection != null &&
        oldWidget.connection != widget.connection) {
      _voice?.cancel();
      _upload?.complete();
      _upload = null;
      _attachments.clear();
      _uploadingName = _error = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) _voice?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _phase == _VoicePhase.recording) {
      _voice?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice?.cancel();
    _upload?.complete();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_busy) return;
    final conn = widget.connection;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final added = await ChatAttachment.pick(
        ChatAttachment.maxCount - _attachments.length,
      );
      if (mounted && widget.session.connection == conn) {
        setState(() => _attachments.addAll(added));
      }
    } catch (e) {
      if (mounted && widget.session.connection == conn) {
        setState(
          () => _error = chatMediaError(e, widget.session.language.value),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    final conn = widget.connection;
    if (conn == null) {
      widget.onSettings();
      return;
    }
    final text = widget.input.text;
    if (text.trim().isEmpty && _attachments.isEmpty) return;
    final upload = Completer<void>();
    bool current() =>
        mounted && !upload.isCompleted && widget.session.connection == conn;
    setState(() {
      _upload = upload;
      _error = null;
    });
    try {
      final images = <String>[], names = <String>[], documents = <Json>[];
      for (final item in List.of(_attachments)) {
        if (item.jpeg case final jpeg?) {
          images.add('data:image/jpeg;base64,${base64Encode(jpeg)}');
          names.add(item.name);
        } else {
          if (item.uploaded == null) {
            setState(() => _uploadingName = item.name);
            final bytes = await item.read();
            if (!current()) return;
            item.uploaded = await widget.session.api.uploadChatFile(
              conn,
              item.name,
              bytes,
              cancel: upload.future,
            );
            if (!current()) return;
          }
          documents.add(item.uploaded!);
        }
      }
      setState(() => _uploadingName = null);
      await widget.session.send(
        text,
        images: images,
        imageNames: names,
        documents: documents,
        expectedConnection: conn,
      );
      if (!current()) return;
      if (widget.input.text == text) widget.input.clear();
      _attachments.clear();
      widget.onSent();
    } catch (e) {
      if (current()) {
        setState(
          () => _error = [
            _uploadingName,
            chatMediaError(e, widget.session.language.value),
          ].nonNulls.join(' · '),
        );
      }
    } finally {
      if (mounted && _upload == upload) {
        setState(() {
          _upload = null;
          _uploadingName = null;
        });
      }
    }
  }

  Future<void> _dictate() async {
    if (_phase == _VoicePhase.recording) {
      _voice?.stop();
      return;
    }
    if (_busy) return;
    final conn = widget.connection;
    if (conn == null) {
      widget.onSettings();
      return;
    }
    final take = ChatDictation();
    bool current() =>
        mounted &&
        !take.isCancelled &&
        widget.active &&
        widget.session.connection == conn;
    setState(() {
      _voice = take;
      _phase = _VoicePhase.permission;
      _error = null;
    });
    try {
      final wav = await take.record(() {
        if (!current() ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.paused) {
          take.cancel();
        } else {
          setState(() => _phase = _VoicePhase.recording);
        }
      });
      if (!current() || wav == null) return;
      setState(() => _phase = _VoicePhase.transcribing);
      final words = await widget.session.api.transcribe(
        conn,
        wav,
        cancel: take.cancelled,
      );
      if (!current()) return;
      final draft = widget.input.text;
      final separator = draft.isEmpty || RegExp(r'\s$').hasMatch(draft)
          ? ''
          : ' ';
      final updated = '$draft$separator$words';
      widget.input.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: updated.length),
      );
      widget.focusNode.requestFocus();
    } catch (e) {
      if (current()) {
        setState(
          () => _error = chatMediaError(e, widget.session.language.value),
        );
      }
    } finally {
      if (mounted && _voice == take) {
        setState(() {
          _voice = null;
          _phase = _VoicePhase.idle;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ready = widget.session.ready;
    final voiceLabel = switch (_phase) {
      _VoicePhase.idle => context.tr('语音输入'),
      _VoicePhase.permission => context.tr('等待麦克风权限'),
      _VoicePhase.recording => context.tr('结束录音并转写'),
      _VoicePhase.transcribing => context.tr('正在转写'),
    };
    final status =
        _error ??
        (_picking
            ? context.tr('正在读取附件…')
            : _uploadingName != null
            ? context.tr('正在上传 {0}', [_uploadingName])
            : _phase == _VoicePhase.recording
            ? context.tr('正在录音')
            : _phase != _VoicePhase.idle
            ? voiceLabel
            : null);
    return GlassCard(
      radius: 20,
      color: colors.surfaceContainer,
      borderColor: widget.focusNode.hasFocus ? colors.primary : colors.outline,
      padding: const EdgeInsets.fromLTRB(7, 4, 7, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_attachments.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 5),
                itemBuilder: (_, i) {
                  final item = _attachments[i];
                  return InputChip(
                    avatar: item.jpeg == null
                        ? const Icon(Icons.insert_drive_file_outlined, size: 16)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(
                              item.jpeg!,
                              width: 22,
                              height: 22,
                              fit: BoxFit.cover,
                              cacheWidth: 64,
                            ),
                          ),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 148),
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    deleteButtonTooltipMessage: context.tr('移除 {0}', [
                      item.name,
                    ]),
                    onDeleted: _busy
                        ? null
                        : () => setState(() {
                            _attachments.remove(item);
                            _error = null;
                          }),
                  );
                },
              ),
            ),
          if (status != null)
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: _error == null
                              ? colors.onSurfaceVariant
                              : colors.error,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_voice != null)
                  IconButton(
                    tooltip: context.tr('取消语音输入'),
                    visualDensity: VisualDensity.compact,
                    onPressed: _voice!.cancel,
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          ValueListenableBuilder(
            valueListenable: widget.input,
            builder: (context, value, _) => _ComposerRow(
              draft: value.text,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: context.tr('添加附件'),
                    onPressed:
                        ready &&
                            !_busy &&
                            _attachments.length < ChatAttachment.maxCount
                        ? _pick
                        : null,
                    icon: const Icon(Icons.attach_file_rounded, size: 21),
                  ),
                  if (widget.showConnect && ready)
                    TextButton(
                      onPressed: widget.onSettings,
                      child: Text(context.tr('去连接')),
                    ),
                ],
              ),
              editor: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: TextField(
                  controller: widget.input,
                  focusNode: widget.focusNode,
                  minLines: 1,
                  maxLines: widget.maxLines,
                  maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    color: colors.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: context.tr('想说点什么？'),
                    hintMaxLines: 1,
                    maintainHintSize: false,
                    counterText: '',
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 9,
                    ),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: voiceLabel,
                    onPressed:
                        ready && (!_busy || _phase == _VoicePhase.recording)
                        ? _dictate
                        : null,
                    color: _phase == _VoicePhase.recording
                        ? colors.primary
                        : null,
                    icon: Icon(
                      _phase == _VoicePhase.recording
                          ? Icons.stop_rounded
                          : Icons.mic_none_rounded,
                      size: 22,
                    ),
                  ),
                  IconButton.filled(
                    tooltip: context.tr('发送消息'),
                    onPressed:
                        ready &&
                            !_busy &&
                            (value.text.trim().isNotEmpty ||
                                _attachments.isNotEmpty)
                        ? _send
                        : null,
                    style: IconButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      disabledBackgroundColor: colors.surfaceContainerHigh,
                      disabledForegroundColor: colors.onSurfaceVariant,
                      minimumSize: const Size.square(36),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
