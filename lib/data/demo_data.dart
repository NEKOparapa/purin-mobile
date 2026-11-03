class Memory {
  final String title, time, source, summary, detail;
  final List<String> tags;
  final bool isVoice;
  const Memory({
    required this.title,
    required this.time,
    required this.source,
    required this.summary,
    required this.detail,
    required this.tags,
    this.isVoice = true,
  });
}

const memories = [
  Memory(
    title: '让 AI 成为日常里安静的陪伴',
    time: '14:32',
    source: '随身录音 · 18 分钟',
    summary: '比起更多的功能，更希望它能理解上下文，在恰当的时候出现。',
    detail:
        '理想中的 AI 执事不需要一直提醒自己它的存在。它应该记得之前聊过的事，理解那些没说完整的想法。\n\n下一步：先把跨设备的主页做出来，让想法有一个可以触碰的起点。\n\n这是一条示例记忆。',
    tags: ['产品灵感', 'Wintermute'],
  ),
  Memory(
    title: '专注，也需要一些边界',
    time: '11:06',
    source: '桌面对话',
    isVoice: false,
    summary: '尝试把上午留给深度工作，消息和琐事放到下午集中处理。',
    detail: '给自己留出一段完整的时间，只做一件重要的事。暂时放下消息提醒，在下午统一处理琐事。\n\n这是一条示例记忆，尚未创建真实日程。',
    tags: ['生活方式', '专注'],
  ),
  Memory(
    title: '周末的小小出逃计划',
    time: '09:18',
    source: '随身录音 · 24 分钟',
    summary: '找一条安静的山间小路，带上相机，不急着抵达。',
    detail: '想在周末去附近的山里走走。带上相机和水，不设定一定要到达的目的地，只是看看沿途的风景。\n\n这是一条示例记忆。',
    tags: ['周末计划', '随想'],
  ),
];

const demoReply =
    '我已经记下了。在这份演示中，你可以查看今天的 3 条记忆切片，以及随身录音设备的示例状态。连接 Wintermute 服务后，我们就可以继续真正的对话。';
