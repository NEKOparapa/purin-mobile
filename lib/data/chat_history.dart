import 'dart:convert';

import 'agent_api.dart';

/// One authenticated connection's chat projection. Server pages are newest first.
class ChatHistory {
  ({String head, List<Json> rows, Map<String, int> indexes})? _page;

  Future<List<Json>> read(AgentApi api, Connection connection) async {
    const path = 'history?view=dialogue&limit=100';
    var page = await api.request(connection, path);
    final head = jsonEncode(page);
    final cached = _page;
    if (cached != null && cached.head == head) {
      return cached.rows.reversed.toList();
    }
    final ids = <String>{};
    final cursors = <String>{};
    final rows = <Json>[];
    while (true) {
      for (final row in (page['items'] as List).cast<Json>()) {
        if (row['role'] is! String || row['text'] is! String) {
          throw const FormatException('服务端返回的对话历史格式有误');
        }
        if (ids.add(row['id'] as String)) rows.add(row);
      }
      final cursor = page['next_cursor'] as String?;
      if (cursor == null) break;
      // The journals have immutable event/output IDs. Once the end of a new
      // page meets a known row we can reuse the older suffix. After a reset
      // every ID is new, so the reader reaches the server's end instead.
      if (cached != null && rows.isNotEmpty) {
        final anchor = rows.last['id'];
        final index = cached.indexes[anchor];
        if (index != null) {
          rows.addAll(
            cached.rows
                .skip(index + 1)
                .where((old) => ids.add(old['id'] as String)),
          );
          break;
        }
      }
      if (cursor.isEmpty || !cursors.add(cursor)) {
        throw const FormatException('服务端返回了重复的历史分页位置');
      }
      page = await api.request(
        connection,
        '$path&cursor=${Uri.encodeQueryComponent(cursor)}',
      );
    }
    _page = (
      head: head,
      rows: rows,
      indexes: {
        for (var i = 0; i < rows.length; i++) rows[i]['id'] as String: i,
      },
    );
    return rows.reversed.toList();
  }
}
