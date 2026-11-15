import 'package:flutter/material.dart';
import '../data/demo_data.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});
  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  String _query = '', _filter = '全部';
  void _detail(Memory memory) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                memory.source,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                memory.title,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                memory.detail,
                style: const TextStyle(height: 1.75, fontSize: 16),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = memories.where(
      (m) =>
          (_filter == '全部' || (_filter == '录音') == m.isVoice) &&
          [
            m.title,
            m.summary,
            m.source,
            ...m.tags,
          ].any((s) => s.toLowerCase().contains(_query.toLowerCase())),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: const InputDecoration(
                    hintText: '搜索示例记忆',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final name in ['全部', '录音', '对话'])
                      ChoiceChip(
                        label: Text(name),
                        selected: _filter == name,
                        showCheckmark: false,
                        selectedColor: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer,
                        side: BorderSide(
                          color: _filter == name
                              ? Theme.of(context).colorScheme.secondary
                              : Theme.of(context).colorScheme.outline,
                        ),
                        onSelected: (_) => setState(() => _filter = name),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  '示例记忆',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('没有找到相关记忆。'),
                  ),
                for (final m in rows) ...[
                  InkWell(
                    onTap: () => _detail(m),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${m.time}  ·  ${m.source}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            m.title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            m.summary,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
