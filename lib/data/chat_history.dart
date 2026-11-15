import 'dart:convert';

import 'agent_api.dart';

/// One authenticated connection's chat projection. Server pages are newest first.
class ChatHistory {
  final _pages =
      <String, ({String head, List<Json> rows, Map<String, int> indexes})>{};
  DateTime? _retryDialogue;

  Future<List<Json>> read(AgentApi api, Connection connection) async {
    if (_retryDialogue == null || !DateTime.now().isBefore(_retryDialogue!)) {
      try {
        final rows = await _readView(api, connection, 'dialogue');
        _retryDialogue = null;
        return rows.reversed.toList();
      } on ApiError catch (e) {
        if (e.status != 400 || e.code != 'invalid_query') rethrow;
        // Check again after an in-place server upgrade.
        _retryDialogue = DateTime.now().add(const Duration(minutes: 1));
      }
    }
    final layers = await Future.wait([
      _readView(api, connection, 'conversation'),
      _readView(api, connection, 'notification'),
    ]);
    // Older servers date each journal group by its input and return its output
    // just above it, without an output timestamp. Use that group's time to merge.
    final rows = <({Json row, int time, int order})>[];
    for (var i = 0; i < layers.length; i++) {
      var at = 0;
      for (final row in layers[i].reversed) {
        final timestamp = row['occurred_at'] as String?;
        if (timestamp != null) {
          at = DateTime.parse(timestamp).microsecondsSinceEpoch;
        }
        if (row['role'] == 'assistant' || (i == 0 && row['role'] == 'user')) {
          rows.add((
            row: {...row, 'layer': i == 0 ? 'conversation' : 'notification'},
            time: at,
            order: rows.length,
          ));
        }
      }
    }
    rows.sort(
      (a, b) => a.time == b.time
          ? a.order.compareTo(b.order)
          : a.time.compareTo(b.time),
    );
    return [for (final entry in rows) entry.row];
  }

  Future<List<Json>> _readView(
    AgentApi api,
    Connection conn,
    String view,
  ) async {
    final path = 'history?view=$view&limit=100';
    var page = await api.request(conn, path);
    final head = jsonEncode(page);
    final cached = _pages[view];
    if (cached?.head == head) return cached!.rows;
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
        conn,
        '$path&cursor=${Uri.encodeQueryComponent(cursor)}',
      );
    }
    _pages[view] = (
      head: head,
      rows: rows,
      indexes: {
        for (var i = 0; i < rows.length; i++) rows[i]['id'] as String: i,
      },
    );
    return rows;
  }
}
