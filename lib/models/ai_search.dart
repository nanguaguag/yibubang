class AiAnswerModel {
  final String id;
  final String label;
  final String resolvedModel;
  final String contextWindow;
  final String availability;
  final bool preview;
  const AiAnswerModel({
    required this.id,
    required this.label,
    required this.resolvedModel,
    required this.contextWindow,
    this.availability = 'documented',
    this.preview = false,
  });
  factory AiAnswerModel.fromJson(Map<String, dynamic> j) => AiAnswerModel(
    id: j['id'] as String,
    label: j['label'] as String,
    resolvedModel: j['resolved_model'] as String? ?? j['id'] as String,
    contextWindow: j['context_window'] as String? ?? '',
    availability: j['availability'] as String? ?? 'documented',
    preview: j['preview'] == true,
  );
}

class AiModelCatalog {
  final List<AiAnswerModel> models;
  final String sourceUrl;
  final DateTime fetchedAt;
  final bool stale;
  final String catalogType;
  const AiModelCatalog({
    required this.models,
    required this.sourceUrl,
    required this.fetchedAt,
    this.stale = false,
    this.catalogType = 'official_documentation',
  });
  factory AiModelCatalog.fromJson(Map<String, dynamic> j) => AiModelCatalog(
    models: (j['models'] as List)
        .map((m) => AiAnswerModel.fromJson(Map<String, dynamic>.from(m)))
        .toList(),
    sourceUrl: j['source_url'] as String,
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(
      ((j['fetched_at'] as num) * 1000).round(),
    ),
    stale: j['stale'] == true,
    catalogType: j['catalog_type'] as String? ?? 'official_documentation',
  );
}

class AiCitation {
  final int number;
  final String questionId;
  final String title;
  final List<String> sourceIds;
  final String kind;
  final String bookId;
  final String bookTitle;
  final String sourceVersion;
  final String edition;
  final String printedPage;
  final String imageKey;
  final int pdfPage;
  final int pageCount;
  final bool needsReview;
  bool get isTextbook => kind == 'textbook';
  const AiCitation({
    required this.number,
    required this.questionId,
    required this.title,
    this.sourceIds = const [],
    this.kind = 'question',
    this.bookId = '',
    this.bookTitle = '',
    this.sourceVersion = '',
    this.edition = '',
    this.printedPage = '',
    this.imageKey = '',
    this.pdfPage = 0,
    this.pageCount = 0,
    this.needsReview = false,
  });
  factory AiCitation.fromJson(Map<String, dynamic> json) => AiCitation(
    number: (json['number'] as num).toInt(),
    questionId: json['question_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    sourceIds: List<String>.from(json['source_ids'] as List? ?? []),
    kind: json['kind'] as String? ?? 'question',
    bookId: json['book_id'] as String? ?? '',
    bookTitle: json['book_title'] as String? ?? '',
    sourceVersion: json['source_version'] as String? ?? '',
    edition: json['edition'] as String? ?? '',
    printedPage: '${json['printed_page'] ?? ''}',
    imageKey: json['image_key'] as String? ?? '',
    pdfPage: (json['pdf_page'] as num?)?.toInt() ?? 0,
    pageCount: (json['page_count'] as num?)?.toInt() ?? 0,
    needsReview: json['needs_review'] == true,
  );
  Map<String, dynamic> toJson() => {
    'number': number,
    'question_id': questionId,
    'title': title,
    'source_ids': sourceIds,
    'kind': kind,
    'book_id': bookId,
    'book_title': bookTitle,
    'source_version': sourceVersion,
    'edition': edition,
    'printed_page': printedPage,
    'image_key': imageKey,
    'pdf_page': pdfPage,
    'page_count': pageCount,
    'needs_review': needsReview,
  };
}

class AiTurn {
  final String id;
  final String question;
  String answer;
  String status;
  String? error;
  List<AiCitation> citations;
  String? model;
  final DateTime createdAt;
  AiTurn({
    required this.id,
    required this.question,
    this.answer = '',
    this.status = 'pending',
    this.error,
    this.citations = const [],
    this.model,
    required this.createdAt,
  });
  factory AiTurn.fromJson(Map<String, dynamic> j) => AiTurn(
    id: j['id'],
    question: j['question'],
    answer: j['answer'] ?? '',
    status: j['status'] ?? 'interrupted',
    error: j['error'],
    model: j['model'],
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
    'model': model,
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
  const AiQuota({required this.remaining, this.limit = 200, required this.day});
  factory AiQuota.fromJson(Map<String, dynamic> j) => AiQuota(
    remaining: (j['remaining'] as num).toInt(),
    limit: (j['limit'] as num?)?.toInt() ?? 200,
    day: j['day'] as String? ?? '',
  );
}

class AiStreamEvent {
  final String type;
  final Map<String, dynamic> data;
  const AiStreamEvent(this.type, this.data);
}
