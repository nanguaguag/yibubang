class Chapter {
  String id;
  String name;
  String? subjectId; // This is a foreign key reference to Subject table

  Chapter({required this.id, required this.name, this.subjectId});

  // Convert a Chapter to a map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'subject_id': subjectId,
    };
  }

  // Convert a map to a Chapter
  factory Chapter.fromMap(Map<String, dynamic> map) {
    return Chapter(
      id: map['id'],
      name: map['name'],
      subjectId: map['subject_id'],
    );
  }
}
