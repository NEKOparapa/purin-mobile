import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../data/agent_api.dart';
import '../data/mobile_session.dart';
import '../widgets/app_theme.dart';
import '../widgets/shared.dart';

class MemoryScheduleScreen extends StatefulWidget {
  const MemoryScheduleScreen({super.key, required this.session});
  final MobileSession session;

  @override
  State<MemoryScheduleScreen> createState() => _MemoryScheduleScreenState();
}

class _MemoryScheduleScreenState extends State<MemoryScheduleScreen> {
  final days = TextEditingController();
  late final connection = widget.session.connection;
  TimeOfDay? time;
  String zone = '', next = '', feedback = '';
  bool isError = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    days.dispose();
    super.dispose();
  }

  Future<void> load({bool save = false}) async {
    final conn = connection;
    if (conn == null || conn != widget.session.connection) {
      setState(() {
        isError = true;
        feedback = '连接已更改，请重新打开记忆整理。';
      });
      return;
    }
    final count = int.tryParse(days.text);
    if (save && (count == null || count < 1 || count > 3650)) {
      setState(() {
        isError = true;
        feedback = '请输入 1 至 3650 之间的整数天数。';
      });
      return;
    }
    setState(() {
      busy = true;
      feedback = '';
      isError = false;
    });
    try {
      final hour = time?.hour.toString().padLeft(2, '0');
      final minute = time?.minute.toString().padLeft(2, '0');
      final plan = await widget.session.api.request(
        conn,
        'memory/schedule',
        body: save
            ? {'interval_days': count, 'local_time': '$hour:$minute'}
            : null,
      );
      if (!mounted) return;
      if (conn != widget.session.connection) throw StateError('连接已更改');
      final hhmm = (plan['local_time'] as String).split(':');
      setState(() {
        days.text = (plan['interval_days'] as int).toString();
        time = TimeOfDay(hour: int.parse(hhmm[0]), minute: int.parse(hhmm[1]));
        zone = plan['timezone'] as String;
        next = (plan['next_run_at'] as String)
            .substring(0, 16)
            .replaceFirst('T', ' ');
        isError = false;
        feedback = save ? '整理计划已保存' : '';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          isError = true;
          feedback = e is ApiError && e.code == 'memory_unconfigured'
              ? '后端尚未配置当前账号的记忆目录。'
              : '无法读写整理计划，请检查连接后重试。';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final atmo = AppAtmosphere.of(context);
    return AtmosphereScaffold(
      title: '记忆整理',
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
              children: [
                if (time == null && busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: CupertinoActivityIndicator(radius: 12),
                    ),
                  ),
                if (time != null) ...[
                  SettingsSection(
                    title: '整理周期',
                    footer: '同一账号的所有设备共用此计划。',
                    dividers: true,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '间隔天数',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '1 至 3650 天',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 96,
                              child: TextField(
                                controller: days,
                                enabled: !busy,
                                textAlign: TextAlign.center,
                                onChanged: (_) {
                                  if (feedback.isNotEmpty) {
                                    setState(() => feedback = '');
                                  }
                                },
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  suffixText: '天',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  fillColor: atmo.inputFill,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SettingsTile(
                        title: '运行时间',
                        subtitle: zone.isEmpty ? null : '时区 · $zone',
                        enabled: !busy,
                        showChevron: true,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: atmo.inputFill,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            time!.format(context),
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        onTap: () async {
                          final value = await showTimePicker(
                            context: context,
                            initialTime: time!,
                          );
                          if (mounted && value != null) {
                            setState(() {
                              time = value;
                              feedback = '';
                            });
                          }
                        },
                      ),
                      if (next.isNotEmpty)
                        SettingsTile(
                          title: '下次整理',
                          trailing: Text(
                            next,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilledButton(
                      onPressed: busy ? null : () => load(save: true),
                      child: busy
                          ? const CupertinoActivityIndicator(radius: 9)
                          : const Text('保存计划'),
                    ),
                  ),
                ],
                if (feedback.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        feedback,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: isError
                              ? colors.error
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                if (time == null && !busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Center(
                      child: FilledButton.tonal(
                        onPressed: () => load(),
                        child: const Text('重新加载'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
