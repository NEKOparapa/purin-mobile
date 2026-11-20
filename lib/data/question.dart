import 'agent_api.dart';

class PendingQuestion {
  const PendingQuestion({
    required this.id,
    required this.title,
    required this.question,
    required this.options,
    required this.multiSelect,
    required this.allowCustom,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String question;
  final List<String> options;
  final bool multiSelect;
  final bool allowCustom;
  final String status;
  final String createdAt;

  factory PendingQuestion.fromJson(Json row) => PendingQuestion(
    id: row['id'] as String,
    title: (row['title'] as String?) ?? '',
    question: (row['question'] as String?) ?? '',
    options: [
      for (final opt in (row['options'] as List? ?? const []))
        if (opt is String) opt,
    ],
    multiSelect: row['multi_select'] == true,
    allowCustom: row['allow_custom'] != false,
    status: (row['status'] as String?) ?? 'pending',
    createdAt: (row['created_at'] as String?) ?? '',
  );
}
