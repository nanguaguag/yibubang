class QuestionStat {
  String commentCount;
  String errorCorrectionNumber;
  String collectionCount;
  String rightCount;
  String wrongCount;
  String statInfo;
  String isNote;
  String isCollection;
  String isComment;
  String isPraise;
  String restoreCorrectionNumber;
  String explainCorrectionNumber;
  String optionAnalysisCorrectionNumber;

  QuestionStat({
    required this.commentCount,
    required this.errorCorrectionNumber,
    required this.collectionCount,
    required this.rightCount,
    required this.wrongCount,
    required this.statInfo,
    required this.isNote,
    required this.isCollection,
    required this.isComment,
    required this.isPraise,
    required this.restoreCorrectionNumber,
    required this.explainCorrectionNumber,
    required this.optionAnalysisCorrectionNumber,
  });

  // Convert a QuestionStat to a map
  Map<String, dynamic> toMap() {
    return {
      'comment_count': commentCount,
      'error_correction_number': errorCorrectionNumber,
      'collection_count': collectionCount,
      'right_count': rightCount,
      'wrong_count': wrongCount,
      'stat_info': statInfo,
      'is_note': isNote,
      'is_collection': isCollection,
      'is_comment': isComment,
      'is_praise': isPraise,
      'restore_correction_number': restoreCorrectionNumber,
      'explain_correction_number': explainCorrectionNumber,
      'option_analysis_correction_number': optionAnalysisCorrectionNumber,
    };
  }

  // Convert a map to a QuestionStat
  factory QuestionStat.fromMap(Map<String, dynamic> map) {
    return QuestionStat(
      commentCount: map['comment_count'],
      errorCorrectionNumber: map['error_correction_number'],
      collectionCount: map['collection_count'],
      rightCount: map['right_count'],
      wrongCount: map['wrong_count'],
      statInfo: map['stat_info'],
      isNote: map['is_note'],
      isCollection: map['is_collection'],
      isComment: map['is_comment'],
      isPraise: map['is_praise'],
      restoreCorrectionNumber: map['restore_correction_number'],
      explainCorrectionNumber: map['explain_correction_number'],
      optionAnalysisCorrectionNumber: map['option_analysis_correction_number'],
    );
  }
}
