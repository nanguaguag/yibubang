import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/db/durable_sync_queue.dart';
import 'package:yibubang/models/note.dart';
import 'package:yibubang/models/question.dart';
import 'package:yibubang/services/note_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory dir;
  late String previous;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    previous = await getDatabasesPath();
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('note_race_');
    await databaseFactory.setDatabasesPath(dir.path);
    SharedPreferences.setMockInitialValues({
      'loggedin': true,
      'user_id': 'u',
      'identityId': 'i',
    });
    db = await UserDBHelper().database;
  });
  tearDown(() async {
    DurableSyncQueue.cancelWakeups();
    await UserDBHelper().close();
    await dir.delete(recursive: true);
    await databaseFactory.setDatabasesPath(previous);
  });
  QuestionNote note({List<NoteImage> images = const []}) => QuestionNote(
    id: 'local_note',
    questionId: 'q',
    content: 'old',
    images: images,
    timestamp: 100,
    updatedAt: 100,
    syncStatus: 1,
  );
  Future<void> prepare(QuestionNote n) async {
    await db.insert('Question', {'id': 'q', 'chapter_parent_id': 's'});
    await db.insert('Notes', n.toMap());
    await DurableSyncQueue.enqueue('NoteSyncQueue', {
      'id': 'upload',
      'action': 'upload',
      'note_id': n.id,
      'question_id': 'q',
      'payload': '{}',
      'created_at': 1,
    });
  }

  test('图片上传期间编辑不会被旧正文覆盖，新版继续上传', () async {
    final file = File(p.join(dir.path, 'image.png'));
    await file.writeAsBytes([1, 2, 3]);
    final n = note(
      images: [NoteImage(bImg: '', sImg: '', localPath: file.path)],
    );
    await prepare(n);
    final bodies = <String>[];
    await http.runWithClient(
      () => NoteService.instance.processQueue(),
      () => MockClient((req) async {
        if (req.url.path.endsWith('/uploads')) {
          await NoteService.instance.saveNote(
            n.copyWith(content: 'new', images: []),
          );
          return http.Response(
            '{"code":200,"data":{"b_img":"https://image"}}',
            200,
          );
        }
        bodies.add(Uri.splitQueryString(req.body)['content']!);
        return http.Response('{"code":200,"data":{"id":"remote"}}', 200);
      }),
    );
    final saved = (await db.query('Notes')).single;
    expect(saved['content'], 'new');
    expect(saved['imgs'], '[]');
    expect(saved['sync_status'], 0);
    expect(bodies, ['new']);
  });
  test('发包期间删除笔记，晚到真实ID触发远端删除且不复活', () async {
    final n = note();
    await prepare(n);
    final paths = <String>[];
    await http.runWithClient(
      () => NoteService.instance.processQueue(),
      () => MockClient((req) async {
        paths.add(req.url.path);
        if (req.url.path.endsWith('/pushNote')) {
          await NoteService.instance.deleteNote(n);
          expect(
            (await db.query('NoteSyncQueue')).single['queue_state'],
            'sending',
          );
          return http.Response('{"code":200,"data":{"id":"created"}}', 200);
        }
        return http.Response('{"code":200}', 200);
      }),
    );
    expect(paths.map((s) => s.split('/').last), ['pushNote', 'cleanNote']);
    expect(await db.query('Notes'), isEmpty);
    expect(await db.query('NoteSyncQueue'), isEmpty);
    expect((await db.query('NoteTombstones')).single['remote_id'], 'created');
  });
  test('创建响应不含真实ID时不会猜测关联第一条笔记或自动重传', () async {
    await prepare(note());
    var calls = 0;
    await http.runWithClient(
      () => NoteService.instance.processQueue(),
      () => MockClient((req) async {
        calls++;
        return http.Response('{"code":200}', 200);
      }),
    );
    expect(calls, 1);
    expect((await db.query('Notes')).single['remote_id'], isNull);
    expect((await db.query('NoteSyncQueue')).single['queue_state'], 'paused');
    expect(
      (await db.query('NoteSyncQueue')).single['last_error'],
      contains('可靠笔记ID'),
    );
  });
  test('入队失败时正文及修订号回滚，删除入队失败时删除标记也回滚', () async {
    final n = note().copyWith(remoteId: 'known');
    await db.insert('Question', {'id': 'q'});
    await db.insert('Notes', n.toMap());
    await db.execute(
      "CREATE TRIGGER fail_queue BEFORE INSERT ON NoteSyncQueue BEGIN SELECT RAISE(ABORT,'fail'); END",
    );
    await expectLater(
      NoteService.instance.saveNote(n.copyWith(content: 'new')),
      throwsA(isA<DatabaseException>()),
    );
    expect((await db.query('Notes')).single['content'], 'old');
    expect((await db.query('Notes')).single['revision'], 0);
    await expectLater(
      NoteService.instance.deleteNote(n),
      throwsA(isA<DatabaseException>()),
    );
    expect((await db.query('Notes')).single['content'], 'old');
    expect(await db.query('NoteTombstones'), isEmpty);
  });
  test('拉取已删除远端笔记不会恢复本地数据', () async {
    final n = note().copyWith(remoteId: 'deleted');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_notes_to_ykb', false);
    await db.insert('Question', {'id': 'q'});
    await db.insert('Notes', n.toMap());
    await NoteService.instance.deleteNote(n);
    await prefs.setBool('sync_notes_to_ykb', true);
    await http.runWithClient(
      () => NoteService.instance.syncNotesForQuestion(
        Question(
          id: 'q',
          identityId: 'i',
          chapterParentId: 's',
          userAnswer: '',
        ),
      ),
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 200,
            'data': [
              {'id': 'deleted', 'content': 'old', 'ctime': '1'},
            ],
          }),
          200,
        ),
      ),
    );
    expect(await db.query('Notes'), isEmpty);
    await expectLater(
      NoteService.instance.saveNote(n.copyWith(content: 'stale editor')),
      throwsStateError,
    );
  });
  test('上传正文期间编辑，旧ACK只关联ID而不能标记新编辑已同步', () async {
    final n = note();
    await prepare(n);
    var calls = 0;
    await http.runWithClient(
      () => NoteService.instance.processQueue(),
      () => MockClient((req) async {
        calls++;
        if (calls == 1) {
          await NoteService.instance.saveNote(n.copyWith(content: 'new'));
          return http.Response('{"code":200,"data":{"id":"remote"}}', 200);
        }
        expect(Uri.splitQueryString(req.body)['id'], 'remote');
        expect((await db.query('Notes')).single['sync_status'], 1);
        return http.Response('{"code":200}', 200);
      }),
    );
    expect(calls, 2);
    expect((await db.query('Notes')).single['content'], 'new');
    expect((await db.query('Notes')).single['sync_status'], 0);
  });
  test('连续编辑修订号单调增长，不依赖同毫秒时间戳', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_notes_to_ykb', false);
    final n = note();
    await NoteService.instance.saveNote(n);
    await NoteService.instance.saveNote(n.copyWith(content: 'new'));
    expect((await db.query('Notes')).single['revision'], 2);
  });
}
