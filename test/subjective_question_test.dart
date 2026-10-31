import 'package:flutter_test/flutter_test.dart';
import 'package:yibubang/common/app_strings.dart';
import 'package:yibubang/models/question.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Subjective Question Support Tests [BUG-05]', () {
    test('AppStrings.questionTypes contains all extended question types', () {
      expect(AppStrings.questionTypes, containsAll([
        '全部',
        '单选题',
        '多选题',
        '填空题',
        '名词解释',
        '简答题',
        '论述题',
        '病例分析',
      ]));
    });

    test('Question.typeLabel correctly resolves Chinese labels for types 1-7, 19', () {
      final q1 = Question(id: '1', type: '1', userAnswer: '');
      expect(q1.typeLabel, '单选题');

      final q2 = Question(id: '2', type: '2', userAnswer: '');
      expect(q2.typeLabel, '多选题');

      final q3 = Question(id: '3', type: '3', userAnswer: '');
      expect(q3.typeLabel, '填空题');

      final q4 = Question(id: '4', type: '4', userAnswer: '');
      expect(q4.typeLabel, '名词解释');

      final q5 = Question(id: '5', type: '5', userAnswer: '');
      expect(q5.typeLabel, '简答题');

      final q6 = Question(id: '6', type: '6', userAnswer: '');
      expect(q6.typeLabel, '论述题');

      final q7 = Question(id: '7', type: '7', userAnswer: '');
      expect(q7.typeLabel, '病例分析');

      final q19 = Question(id: '19', type: '19', userAnswer: '');
      expect(q19.typeLabel, '案例分析题');

      final custom = Question(id: '99', typeStr: '前沿病例讨论', userAnswer: '');
      expect(custom.typeLabel, '前沿病例讨论');
    });

    test('Question.isSubjective accurately distinguishes subjective questions', () {
      // 1. 标准单选题 / 多选题
      final singleChoice = Question(
        id: '101',
        type: '1',
        option: '[{"key":"A","title":"选项A"},{"key":"B","title":"选项B"}]',
        userAnswer: '',
      );
      expect(singleChoice.isSubjective, false);

      final multiChoice = Question(
        id: '102',
        type: '2',
        option: '[{"key":"A","title":"选项A"},{"key":"B","title":"选项B"}]',
        userAnswer: '',
      );
      expect(multiChoice.isSubjective, false);

      // 2. 主观题（无选项）
      final fillBlank = Question(
        id: '201',
        type: '3',
        title: '抗休克治疗中使用血管扩张剂须有#@血容量补足@#的前提',
        option: '[]',
        userAnswer: '',
      );
      expect(fillBlank.isSubjective, true);

      final term = Question(
        id: '202',
        type: '4',
        title: '肠梗阻',
        option: '',
        userAnswer: '',
      );
      expect(term.isSubjective, true);

      final essay = Question(
        id: '203',
        type: '5',
        title: '试述肝动脉插管化疗病人的护理要点',
        option: null,
        userAnswer: '',
      );
      expect(essay.isSubjective, true);

      // 3. 官方题库录入错误（标简答题但实际有选项）
      final dirtySingle = Question(
        id: '301',
        type: '5',
        title: '采用洗肠法清除毒物，适用于毒物食入后',
        option: '[{"key":"A","title":"1小时"},{"key":"B","title":"2小时"}]',
        userAnswer: '',
      );
      expect(dirtySingle.isSubjective, false);
    });
  });
}
