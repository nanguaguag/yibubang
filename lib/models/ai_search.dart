class AiCitation {
  final int number;
  final String questionId;
  final String title;
  final List<String> sourceIds;
  const AiCitation({
    required this.number,
    required this.questionId,
    required this.title,
    this.sourceIds = const [],
  });
  factory AiCitation.fromJson(Map<String, dynamic> json) => AiCitation(
    number: (json['number'] as num).toInt(),
    questionId: json['question_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    sourceIds: List<String>.from(json['source_ids'] as List? ?? []),
  );
  Map<String, dynamic> toJson() => {
    'number': number,
    'question_id': questionId,
    'title': title,
    'source_ids': sourceIds,
  };
}

class AiTurn {
  final String id;
  final String question;
  String answer;
  String status;
  String? error;
  List<AiCitation> citations;
  final DateTime createdAt;
  AiTurn({
    required this.id,
    required this.question,
    this.answer = '',
    this.status = 'pending',
    this.error,
    this.citations = const [],
    required this.createdAt,
  });
  factory AiTurn.fromJson(Map<String, dynamic> j) => AiTurn(
    id: j['id'],
    question: j['question'],
    answer: j['answer'] ?? '',
    status: j['status'] ?? 'interrupted',
    error: j['error'],
    citations: (j['citations'] as List? ?? [])
        .map((c) => AiCitation.fromJson(Map<String, dynamic>.from(c)))
        .toList(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['created_at']),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'answer': answer,
    'status': status,
    'error': error,
    'citations': citations.map((c) => c.toJson()).toList(),
    'created_at': createdAt.millisecondsSinceEpoch,
  };
}

class AiSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  AiSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });
}

class AiQuota {
  final int remaining;
  final int limit;
  final String day;
  const AiQuota({required this.remaining, this.limit = 100, required this.day});
  factory AiQuota.fromJson(Map<String, dynamic> j) => AiQuota(
    remaining: (j['remaining'] as num).toInt(),
    limit: (j['limit'] as num?)?.toInt() ?? 100,
    day: j['day'] as String? ?? '',
  );
}

class AiStreamEvent {
  final String type;
  final Map<String, dynamic> data;
  const AiStreamEvent(this.type, this.data);
}
