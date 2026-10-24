import 'dart:convert';

/// 笔记图片模型
class NoteImage {
  final String bImg;
  final String sImg;
  final String? localPath;
  final int bWidth;
  final int bHeight;

  NoteImage({
    required this.bImg,
    required this.sImg,
    this.localPath,
    this.bWidth = 0,
    this.bHeight = 0,
  });

  Map<String, dynamic> toJson() => {
        'b_img': bImg,
        's_img': sImg,
        if (localPath != null) 'local_path': localPath,
        'b_width': bWidth,
        'b_height': bHeight,
      };

  factory NoteImage.fromJson(Map<String, dynamic> json) {
    return NoteImage(
      bImg: json['b_img']?.toString() ?? '',
      sImg: json['s_img']?.toString() ?? json['b_img']?.toString() ?? '',
      localPath: json['local_path']?.toString(),
      bWidth: int.tryParse(json['b_width']?.toString() ?? '0') ?? 0,
      bHeight: int.tryParse(json['b_height']?.toString() ?? '0') ?? 0,
    );
  }
}

/// 用户题目笔记模型
class QuestionNote {
  final String id;
  final String? remoteId;
  final String questionId;
  final String content;
  final List<NoteImage> images;
  final int timestamp; // 毫秒时间戳
  final int updatedAt; // 毫秒时间戳
  final int syncStatus; // 0: 已同步, 1: 待同步/上传, 2: 待删除

  QuestionNote({
    required this.id,
    this.remoteId,
    required this.questionId,
    required this.content,
    required this.images,
    required this.timestamp,
    required this.updatedAt,
    this.syncStatus = 0,
  });

  QuestionNote copyWith({
    String? id,
    String? remoteId,
    String? questionId,
    String? content,
    List<NoteImage>? images,
    int? timestamp,
    int? updatedAt,
    int? syncStatus,
  }) {
    return QuestionNote(
      id: id ?? this.id,
      remoteId: remoteId ?? this.remoteId,
      questionId: questionId ?? this.questionId,
      content: content ?? this.content,
      images: images ?? this.images,
      timestamp: timestamp ?? this.timestamp,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'remote_id': remoteId,
      'question_id': questionId,
      'content': content,
      'imgs': jsonEncode(images.map((img) => img.toJson()).toList()),
      'timestamp': timestamp,
      'updated_at': updatedAt,
      'sync_status': syncStatus,
    };
  }

  factory QuestionNote.fromMap(Map<String, dynamic> map) {
    List<NoteImage> imgsList = [];
    final imgsRaw = map['imgs']?.toString() ?? '';
    if (imgsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(imgsRaw);
        if (decoded is List) {
          imgsList = decoded
              .map((e) => NoteImage.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }
    return QuestionNote(
      id: map['id']?.toString() ?? '',
      remoteId: map['remote_id']?.toString(),
      questionId: map['question_id']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      images: imgsList,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
      syncStatus: (map['sync_status'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 笔记同步队列项
class NoteSyncQueueItem {
  final String id;
  final String action; // 'upload', 'delete', 'download'
  final String? noteId;
  final String questionId;
  final String? payload;
  final int retryCount;
  final int createdAt;
  final String? lastError;
  final String? lastResponse;

  NoteSyncQueueItem({
    required this.id,
    required this.action,
    this.noteId,
    required this.questionId,
    this.payload,
    this.retryCount = 0,
    required this.createdAt,
    this.lastError,
    this.lastResponse,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'action': action,
      'note_id': noteId,
      'question_id': questionId,
      'payload': payload,
      'retry_count': retryCount,
      'created_at': createdAt,
      'last_error': lastError,
      'last_response': lastResponse,
    };
  }

  factory NoteSyncQueueItem.fromMap(Map<String, dynamic> map) {
    return NoteSyncQueueItem(
      id: map['id']?.toString() ?? '',
      action: map['action']?.toString() ?? 'upload',
      noteId: map['note_id']?.toString(),
      questionId: map['question_id']?.toString() ?? '',
      payload: map['payload']?.toString(),
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      lastError: map['last_error']?.toString(),
      lastResponse: map['last_response']?.toString(),
    );
  }
}
