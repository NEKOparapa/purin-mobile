import 'agent_api.dart';

class ScheduleEntry {
  const ScheduleEntry(
    this.id,
    this.title,
    this.content,
    this.at,
    this.action,
    this.triggered,
  );

  final String id, title, content, action;
  final DateTime at;
  final bool triggered;

  factory ScheduleEntry.fromJson(dynamic value) {
    if (value case {
      'id': String id,
      'title': String title,
      'trigger_at': String instant,
      'action': String action,
      'status': String status,
    }) {
      final at = DateTime.tryParse(instant);
      final content = value['content'];
      if (at != null &&
          at.isUtc &&
          (status == 'scheduled' || status == 'triggered') &&
          (content == null || content is String)) {
        return ScheduleEntry(
          id,
          title,
          content ?? '',
          at.toLocal(),
          action,
          status == 'triggered',
        );
      }
    }
    throw const FormatException('日历数据格式有误，请检查后端版本。');
  }
}

Stream<List<ScheduleEntry>> schedulePages(
  AgentApi api,
  Connection connection,
  DateTime start,
  DateTime end,
) async* {
  final query = {
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    'limit': '100',
  };
  final cursors = <String>{};
  while (true) {
    final path = Uri(path: 'schedule', queryParameters: query);
    final page = await api.request(connection, path.toString());
    if (page case {'items': List rows, 'next_cursor': final cursor}) {
      if (cursor != null &&
          (cursor is! String || cursor.isEmpty || !cursors.add(cursor))) {
        throw const FormatException('日历分页位置无效，请刷新重试。');
      }
      yield rows.map(ScheduleEntry.fromJson).toList();
      if (cursor == null) return;
      query['cursor'] = cursor as String;
    } else {
      throw const FormatException('日历数据格式有误，请检查后端版本。');
    }
  }
}
