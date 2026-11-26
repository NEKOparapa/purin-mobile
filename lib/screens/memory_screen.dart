import 'package:flutter/material.dart';
import '../l10n/app_language.dart';
import '../data/demo_data.dart';
import '../widgets/app_theme.dart';
import '../widgets/shared.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({
    super.key,
    this.embedded = false,
    this.topInset = 0,
    this.bottomInset = 24,
  });

  final bool embedded;
  final double topInset;
  final double bottomInset;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _search = TextEditingController();
  String _query = '', _filter = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _detail(Memory memory) {
    FocusManager.instance.primaryFocus?.unfocus();
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: atmo.inputFill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${memory.time} · ${memory.source}',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                memory.title,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.3,
                  letterSpacing: -0.4,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                memory.detail,
                style: TextStyle(
                  height: 1.75,
                  fontSize: 15.5,
                  color: colors.onSurface.withValues(alpha: 0.9),
                ),
              ),
              if (memory.tags.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final tag in memory.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: atmo.inputFill,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '# $tag',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: atmo.inputFill,
                    foregroundColor: colors.onSurface,
                  ),
                  child: Text(context.tr('关闭')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    final rows = localizedMemories(context.appLanguage)
        .where(
          (m) =>
              (_filter == 'all' || (_filter == 'voice') == m.isVoice) &&
              [
                m.title,
                m.summary,
                m.source,
                ...m.tags,
              ].any((s) => s.toLowerCase().contains(_query.toLowerCase())),
        )
        .toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.embedded ? widget.topInset : 10,
            16,
            widget.bottomInset,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            GlassCard(
              radius: 20,
              shadows: false,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v.trim()),
                style: TextStyle(fontSize: 15, color: colors.onSurface),
                decoration: InputDecoration(
                  filled: false,
                  hintText: context.tr('搜索记忆、标签或来源…'),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.tr('清除'),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            AppleSegmentedControl<String>(
              items: [
                ('all', context.tr('全部')),
                ('voice', context.tr('录音')),
                ('chat', context.tr('对话')),
              ],
              selected: _filter,
              onChanged: (value) => setState(() => _filter = value),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                context.tr('示例记忆'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: atmo.sectionHeader,
                ),
              ),
            ),
            if (rows.isEmpty)
              GlassCard(
                radius: 24,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 36,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 28,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr('没有找到相关记忆'),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final m in rows) ...[
                GlassCard(
                  radius: 24,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _detail(m),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  m.isVoice
                                      ? Icons.graphic_eq_rounded
                                      : Icons.chat_bubble_outline_rounded,
                                  size: 14,
                                  color: colors.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${m.time} · ${m.source}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              m.title,
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                color: colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              m.summary,
                              style: TextStyle(
                                fontSize: 14,
                                color: colors.onSurfaceVariant,
                                height: 1.55,
                              ),
                            ),
                            if (m.tags.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final tag in m.tags)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 3.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: atmo.inputFill,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildContent(context);
    return AtmosphereScaffold(
      title: context.tr('记忆'),
      body: SafeArea(top: false, child: _buildContent(context)),
    );
  }
}
