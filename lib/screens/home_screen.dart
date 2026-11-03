import 'package:flutter/material.dart';
import '../main.dart';
import '../data/demo_data.dart';
import '../widgets/shared.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _page = 0;
  String _query = '';
  String _filter = '全部';
  void _chat() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ChatScreen()));
  void _memory(Memory memory) =>
      showDetail(context, memory.title, memory.detail);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 72,
      titleSpacing: 22,
      title: const Row(
        children: [
          BrandMark(size: 32),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              'Wintermute',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -.5,
              ),
            ),
          ),
        ],
      ),
      actions: [
        const DemoBadge(),
        IconButton(
          tooltip: '通知',
          onPressed: () => showDetail(
            context,
            '一切都已整理妥当',
            '今天的 3 条记忆切片已整理完成。\n\n当前为静态演示，尚未连接真实通知。',
          ),
          icon: const Icon(Icons.notifications_none_rounded, size: 22),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            key: ValueKey(_page),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            children: _page == 0
                ? _home()
                : _page == 1
                ? _memories()
                : _devices(),
          ),
        ),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _page,
      onDestinationSelected: (value) => setState(() {
        _page = value;
        _query = '';
        _filter = '全部';
      }),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: '主页',
        ),
        NavigationDestination(
          icon: Icon(Icons.layers_outlined),
          selectedIcon: Icon(Icons.layers_rounded),
          label: '记忆',
        ),
        NavigationDestination(
          icon: Icon(Icons.devices_outlined),
          selectedIcon: Icon(Icons.devices_rounded),
          label: '设备',
        ),
      ],
    ),
  );

  List<Widget> _heading(String title, String subtitle) => [
    const Text(
      'YOUR DAY, A LITTLE CLEARER',
      style: TextStyle(color: accent, fontSize: 9, letterSpacing: 1.8),
    ),
    const SizedBox(height: 13),
    Text(
      title,
      style: const TextStyle(
        fontSize: 27,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
    ),
    const SizedBox(height: 10),
    Text(
      subtitle,
      style: const TextStyle(fontSize: 12, height: 1.9, color: muted),
    ),
    const SizedBox(height: 25),
  ];
  Widget _section(
    String title, {
    VoidCallback? action,
    String label = '查看全部',
  }) => Padding(
    padding: const EdgeInsets.only(top: 25, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: action,
            child: Text('$label →', style: const TextStyle(fontSize: 11)),
          ),
      ],
    ),
  );

  List<Widget> _home() => [
    ..._heading('慢慢来，我一直在。', '把琐碎交给我，把注意力留给真正重要的事。'),
    Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF263D2E), Color(0xFF172A22)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4A6247)),
      ),
      child: CustomPaint(
        painter: SignalPainter(),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '●  WINTERMUTE / 待命中',
                style: TextStyle(color: accent, fontSize: 9, letterSpacing: 1),
              ),
              const SizedBox(height: 19),
              const Text(
                '记住日常，\n理解独一无二的你。',
                style: TextStyle(
                  fontSize: 23,
                  height: 1.65,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '那些重要的小事，我会替你留意。',
                style: TextStyle(
                  color: Color(0xFFB0C5B1),
                  fontSize: 11,
                  height: 1.8,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _chat,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('聊一聊今天', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 15),
                    Icon(Icons.arrow_forward, size: 17),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    const SizedBox(height: 24),
    LayoutBuilder(
      builder: (context, constraints) {
        final items = [
          ('03', '今日记忆', '条切片'),
          ('42', '聆听时长', '分钟'),
          ('02', '连接设备', '台 · 示例'),
        ];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items
              .map(
                (item) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$2,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          item.$1,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        Text(
                          item.$3,
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
    _section('今天，值得记住', action: () => setState(() => _page = 1)),
    ...memories
        .take(2)
        .expand(
          (memory) => [
            MemoryCard(memory: memory, onTap: () => _memory(memory)),
            const SizedBox(height: 12),
          ],
        ),
    _section('身边的设备', action: () => setState(() => _page = 2)),
    _clip(),
    const SizedBox(height: 28),
    const Text(
      '一个逐渐理解你的个人 AI 执事。\n本地演示 · 未连接服务',
      textAlign: TextAlign.center,
      style: TextStyle(color: muted, fontSize: 10, height: 2),
    ),
  ];
  List<Widget> _memories() {
    final filtered = memories.where(
      (memory) =>
          '${memory.title}${memory.summary}'.contains(_query.trim()) &&
          (_filter == '全部' || memory.isVoice == (_filter == '语音')),
    );
    return [
      ..._heading('记忆空间', '让每一个片刻，都有迹可循。'),
      TextField(
        onChanged: (value) => setState(() => _query = value),
        decoration: const InputDecoration(
          hintText: '搜索你的记忆…',
          prefixIcon: Icon(Icons.search, size: 20),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: ['全部', '语音', '对话']
            .map(
              (label) => ChoiceChip(
                label: Text(label),
                selected: _filter == label,
                onSelected: (_) => setState(() => _filter = label),
              ),
            )
            .toList(),
      ),
      _section('今天 · 10 月 31 日（示例）'),
      if (filtered.isEmpty)
        const Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            '没有找到相关记忆。\n换个关键词试试。',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, height: 2),
          ),
        ),
      ...filtered.expand(
        (memory) => [
          MemoryCard(memory: memory, onTap: () => _memory(memory)),
          const SizedBox(height: 14),
        ],
      ),
    ];
  }

  Widget _clip() => Panel(
    onTap: () => showDetail(
      context,
      'Wintermute Clip',
      '模拟设备状态：电量 86%，Wi-Fi 已连接，今天已同步 2 段录音，共 42 分钟。\n\n当前客户端没有连接硬件，也不会启动录音或上传音频。',
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF314332),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.graphic_eq, color: accent, size: 26),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wintermute Clip', style: TextStyle(fontSize: 15)),
                  SizedBox(height: 5),
                  Text(
                    '● 示例在线 · 随身录音设备',
                    style: TextStyle(color: accent, fontSize: 10, height: 1.7),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: muted),
          ],
        ),
        const SizedBox(height: 20),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('电量 86%', style: TextStyle(color: muted, fontSize: 11)),
            Text('Wi-Fi 已连接', style: TextStyle(color: muted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 10),
        const LinearProgressIndicator(
          value: .86,
          minHeight: 3,
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
      ],
    ),
  );
  List<Widget> _devices() => [
    ..._heading('我的设备', '无论在哪里，都能接续你的日常。'),
    _clip(),
    const SizedBox(height: 16),
    Panel(
      onTap: () => showDetail(
        context,
        'Wintermute Mobile',
        'Flutter 构建的 Android / iOS 客户端。\n\n当前为离线主页演示，所有设备状态与记忆均为本地示例。',
      ),
      child: const Row(
        children: [
          Icon(Icons.phone_iphone, color: accent, size: 30),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Wintermute Mobile'),
                SizedBox(height: 6),
                Text(
                  '当前客户端 · 本地演示',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: muted),
        ],
      ),
    ),
    const SizedBox(height: 24),
    OutlinedButton.icon(
      onPressed: () =>
          showDetail(context, '让日常保持连接', '设备配对功能将在后续版本开放。当前不会搜索或连接真实设备。'),
      icon: const Icon(Icons.add),
      label: const Text('添加新设备'),
    ),
    const SizedBox(height: 30),
    TextButton.icon(
      onPressed: () => showDetail(
        context,
        '关于 Wintermute',
        '你的个人 AI 执事。\n\nMobile demo 0.1.0\n所有数据均为示例，无需账号或 API Key。对话仅用于演示，不会发送至服务器。',
      ),
      icon: const Icon(Icons.info_outline, size: 18),
      label: const Text('关于这个空间'),
    ),
  ];
}
