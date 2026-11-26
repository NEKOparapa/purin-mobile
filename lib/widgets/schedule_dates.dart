import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_language.dart';

import '../data/schedule.dart';

const _chineseWeekdays = '一二三四五六日';

DateTime _weekday(int index) => DateTime(2024, 1, 1 + index);

class _Mark extends StatelessWidget {
  const _Mark({required this.notice, required this.color});
  final bool notice;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: notice ? .785398 : 0,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          shape: notice ? BoxShape.rectangle : BoxShape.circle,
          color: notice ? null : color,
          border: Border.all(color: color),
        ),
      ),
    );
  }
}

class ScheduleDatePicker extends StatelessWidget {
  const ScheduleDatePicker({
    super.key,
    required this.selected,
    required this.start,
    required this.end,
    required this.month,
    required this.entries,
    required this.onSelect,
    required this.onMove,
    required this.onToggle,
  });

  final DateTime selected, start, end;
  final bool month;
  final Map<DateTime, List<ScheduleEntry>>? entries;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onMove;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final language = context.appLanguage;
    final tag = language.locale.toLanguageTag();
    final today = DateUtils.dateOnly(DateTime.now());
    final quiet = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    final toggle = month ? context.tr('收起月历') : context.tr('展开月历');
    final first = DateTime(
      start.year,
      start.month,
      start.day + 1 - start.weekday,
    );
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() > 260) onMove(velocity < 0 ? 1 : -1);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selected.day.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 52,
                      letterSpacing: -2.5,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        language == AppLanguage.chinese
                            ? '${selected.year}年${selected.month}月'
                            : DateFormat.yMMMM(tag).format(selected),
                        style: quiet,
                      ),
                      Text(
                        language == AppLanguage.chinese
                            ? '星期${_chineseWeekdays[selected.weekday - 1]}'
                            : DateFormat.EEEE(tag).format(selected),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: month ? context.tr('上个月') : context.tr('上一周'),
                    onPressed: () => onMove(-1),
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                  ),
                  TextButton(
                    onPressed: () => onSelect(today),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(40, 44),
                      foregroundColor: colors.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: Text(context.tr('今天')),
                  ),
                  IconButton(
                    tooltip: month ? context.tr('下个月') : context.tr('下一周'),
                    onPressed: () => onMove(1),
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  for (var i = 0; i < 7; i++)
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          language == AppLanguage.chinese
                              ? _chineseWeekdays[i]
                              : DateFormat.E(tag).format(_weekday(i)),
                          semanticsLabel: language == AppLanguage.chinese
                              ? '星期${_chineseWeekdays[i]}'
                              : DateFormat.EEEE(tag).format(_weekday(i)),
                          style: quiet,
                        ),
                      ),
                    ),
                ],
              ),
              for (
                var week = first;
                week.isBefore(end);
                week = DateTime(week.year, week.month, week.day + 7)
              )
                TableRow(
                  children: [
                    for (var i = 0; i < 7; i++)
                      _cell(
                        context,
                        DateTime(week.year, week.month, week.day + i),
                        today,
                      ),
                  ],
                ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Mark(notice: false, color: colors.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(context.tr('安排'), style: quiet),
                  const SizedBox(width: 12),
                  _Mark(notice: true, color: colors.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(context.tr('通知'), style: quiet),
                ],
              ),
              Tooltip(
                message: toggle,
                excludeFromSemantics: true,
                child: TextButton(
                  onPressed: onToggle,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onSurfaceVariant,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(toggle, style: quiet),
                      Icon(
                        month ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, DateTime day, DateTime today) {
    final colors = Theme.of(context).colorScheme;
    final chosen = day == selected;
    final outside = day.isBefore(start) || !day.isBefore(end);
    final isToday = day == today;
    final rows = entries?[day] ?? const <ScheduleEntry>[];
    final notices = rows.where((item) => item.notification != null).length;
    final agenda = rows.length - notices;
    final color = chosen
        ? colors.onPrimary
        : isToday
        ? colors.primary
        : outside
        ? colors.onSurfaceVariant.withValues(alpha: .65)
        : colors.onSurface;
    return Semantics(
      button: true,
      selected: chosen,
      excludeSemantics: true,
      label:
          '${context.appLanguage.date(day)}${isToday ? context.tr('，今天') : ''}'
          '${entries == null || outside ? '' : context.tr('，{0}项安排', [agenda])}'
          '${notices > 0 ? context.tr('，{0}条通知', [notices]) : ''}',
      onTap: () => onSelect(day),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelect(day),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                alignment: Alignment.center,
                width: MediaQuery.textScalerOf(context).scale(15) + 16,
                height: MediaQuery.textScalerOf(context).scale(15) + 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chosen ? colors.primary : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 15,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      decoration: isToday && !chosen
                          ? TextDecoration.underline
                          : null,
                      decorationColor: color,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 7,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (agenda > 0)
                      _Mark(notice: false, color: colors.onSurfaceVariant),
                    if (agenda > 0 && notices > 0) const SizedBox(width: 4),
                    if (notices > 0)
                      _Mark(notice: true, color: colors.onSurfaceVariant),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
