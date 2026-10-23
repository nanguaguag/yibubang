import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/repositories/question_search_repository.dart';

void main() {
  group('QuestionSearchResult and UserQuestionsType Tests', () {
    test('QuestionSearchResult should retain user properties and format optionText', () {
      final result = QuestionSearchResult(
        questionId: 'test_123',
        bankId: 'dental_final',
        bankName: '口腔综合',
        title: '牙齿组织中硬度最高的是？',
        type: '1',
        typeStr: '单选题',
        option: '[{"key":"A","title":"牙本质"},{"key":"B","title":"釉质"}]',
        subjectName: '口腔解剖生理学',
        year: '2023',
        collection: true,
        isCut: false,
        status: 2,
        updatedAt: 1700000000,
      );

      expect(result.questionId, 'test_123');
      expect(result.typeLabel, '单选题');
      expect(result.stem, '牙齿组织中硬度最高的是？');
      expect(result.optionText, 'A. 牙本质\nB. 釉质');
      expect(result.collection, true);
      expect(result.isCut, false);
      expect(result.status, 2);
    });

    test('UserQuestionsType enum values are complete', () {
      expect(UserQuestionsType.values, contains(UserQuestionsType.collection));
      expect(UserQuestionsType.values, contains(UserQuestionsType.mistake));
      expect(UserQuestionsType.values, contains(UserQuestionsType.cut));
    });
  });
}
