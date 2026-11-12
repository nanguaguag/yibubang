import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yibubang/db/ai_search_store.dart';
import 'package:yibubang/db/database_helper.dart';
import 'package:yibubang/models/ai_search.dart';
import 'package:yibubang/services/ai_search_client.dart';
import 'package:yibubang/services/ai_search_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAiGateway implements AiSearchGateway {
  final requests = <List<AiTurn>>[];
  StreamController<AiStreamEvent>? stream;
  Completer<void> started = Completer<void>();
  @override
  Future<AiQuota> quota() async =>
      const AiQuota(remaining: 99, day: '2026-11-12');
  @override
  Stream<AiStreamEvent> search(
    String question,
    List<AiTurn> history,
    String id,
  ) async* {
    requests.add(List.from(history));
    stream = StreamController<AiStreamEvent>();
    started.complete();
    yield* stream!.stream;
  }

  Future<void> finish({String answer = '基于题库的回答 [1]'}) async {
    stream!.add(AiStreamEvent('delta', {'text': answer}));
    stream!.add(const AiStreamEvent('done', {}));
    await stream!.close();
    started = Completer<void>();
  }

  @override
  void cancel() {
    unawaited(stream?.close());
  }

  @override
  void dispose() {
    cancel();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  group('SSE and HTTP', () {
    test(
      'one-byte UTF8 chunks and CRLF retain Chinese, emoji and citations',
      () async {
        final bytes = utf8.encode(
          ': ping\r\nevent: delta\r\ndata: {"text":"医学😀"}\r\n\r\nevent: done\ndata: {}\n\n',
        );
        final events = await decodeAiEvents(
          Stream.fromIterable(bytes.map((b) => [b])),
        ).toList();
        expect(events.map((e) => e.type), ['delta', 'done']);
        expect(events.first.data['text'], '医学😀');
      },
    );
    test('unterminated SSE frame is an error', () async {
      expect(
        decodeAiEvents(
          Stream.value(utf8.encode('event: delta\ndata: {"text":"partial"}')),
        ).toList(),
        throwsA(isA<AiSearchException>()),
      );
    });
    test(
      'cancel while registration is pending prevents later model request',
      () async {
        SharedPreferences.setMockInitialValues({});
        final registering = Completer<void>();
        final release = Completer<void>();
        var searches = 0;
        final client = AiSearchClient(
          baseUrl: 'https://example.test',
          clientFactory: () => MockClient((request) async {
            if (request.url.path == '/v1/devices') {
              registering.complete();
              await release.future;
              return http.Response('{}', 200);
            }
            searches++;
            return http.Response('event: done\ndata: {}\n\n', 200);
          }),
        );
        final result = client.search('CD8', [], 'request_001').toList();
        await registering.future;
        client.cancel();
        release.complete();
        expect(await result, isEmpty);
        expect(searches, 0);
        client.dispose();
      },
    );
    test('EOF without terminal done preserves an explicit failure', () async {
      SharedPreferences.setMockInitialValues({});
      final client = AiSearchClient(
        baseUrl: 'https://example.test',
        clientFactory: () => MockClient(
          (request) async => request.url.path == '/v1/devices'
              ? http.Response('{}', 200)
              : http.Response.bytes(
                  utf8.encode('event: delta\ndata: {"text":"半个回答"}\n\n'),
                  200,
                ),
        ),
      );
      expect(
        client.search('CD8', [], 'request_001').toList(),
        throwsA(isA<AiSearchException>()),
      );
    });
  });
  group('Local conversations and controller', () {
    late Database db;
    late AiSearchStore store;
    late FakeAiGateway gateway;
    late AiSearchController ai;
    setUp(() async {
      db = await openDatabase(inMemoryDatabasePath);
      await db.execute('PRAGMA foreign_keys=ON');
      await AiSearchStore.install(db);
      store = AiSearchStore(database: () async => db);
      gateway = FakeAiGateway();
      ai = AiSearchController(store: store, gateway: gateway);
      await ai.initialize();
    });
    tearDown(() async {
      ai.dispose();
      await db.close();
    });
    Future<void> ask(String question, {int? replaceFrom}) async {
      final task = ai.send(question, replaceFrom: replaceFrom);
      await gateway.started.future;
      await gateway.finish();
      await task;
    }

    test(
      'follow-up, edit truncation, restart and delete form a persistent chain',
      () async {
        await ask('HLA I是什么');
        final sid = ai.session!.id;
        await ask('与II的区别');
        expect(gateway.requests.last.single.question, 'HLA I是什么');
        await ask('修改后的第一问', replaceFrom: 0);
        expect(gateway.requests.last, isEmpty);
        expect(ai.turns.single.question, '修改后的第一问');
        final restored = AiSearchController(
          store: store,
          gateway: FakeAiGateway(),
        );
        await restored.initialize();
        expect(restored.session!.id, sid);
        expect(restored.turns.single.answer, '基于题库的回答 [1]');
        expect(restored.turns.single.status, 'complete');
        await restored.newSession();
        expect(restored.turns, isEmpty);
        expect(restored.sessions, hasLength(1));
        await restored.delete(restored.sessions.single);
        expect(await db.query('AiSearchTurns'), isEmpty);
        expect(await store.sessions(), isEmpty);
        restored.dispose();
      },
    );
    test('stream stop keeps received text and settles busy state', () async {
      final task = ai.send('问题');
      await gateway.started.future;
      gateway.stream!.add(const AiStreamEvent('delta', {'text': '已收到的😀中文内容'}));
      await Future<void>.delayed(const Duration(milliseconds: 35));
      ai.stop();
      await task;
      expect(ai.busy, isFalse);
      expect(ai.turns.single.answer, '已收到的😀中文内容');
      expect((await store.turns(ai.session!.id)).single.status, 'stopped');
    });
    test(
      'rapid second send and session switch cannot race active persistence',
      () async {
        final task = ai.send('第一问');
        await gateway.started.future;
        await ai.send('第二问');
        await ai.newSession();
        await ai.delete(ai.session!);
        expect(ai.turns, hasLength(1));
        await gateway.finish();
        await task;
        expect(gateway.requests, hasLength(1));
        expect(await store.sessions(), hasLength(1));
      },
    );
    test(
      'quota cached yesterday at zero cannot block server-clock refresh',
      () async {
        ai.quota = const AiQuota(remaining: 0, day: '2026-11-11');
        await ask('今天的问题');
        expect(gateway.requests, hasLength(1));
      },
    );
    test(
      'loading an unfinished session marks interrupted and retains citations',
      () async {
        final now = DateTime.now();
        final session = AiSession(
          id: 'session',
          title: 'q',
          createdAt: now,
          updatedAt: now,
        );
        await store.create(session);
        final turn = AiTurn(
          id: 'turn',
          question: 'q',
          answer: 'partial',
          status: 'streaming',
          createdAt: now,
          citations: [
            const AiCitation(number: 1, questionId: '1637906', title: '原题'),
          ],
        );
        await store.save(session.id, turn, 0, 'q');
        final loaded = (await store.turns(session.id)).single;
        expect(loaded.status, 'interrupted');
        expect(loaded.answer, 'partial');
        expect(loaded.citations.single.questionId, '1637906');
      },
    );
    test('gateway EOF without done is not shown as completed', () async {
      final task = ai.send('q');
      await gateway.started.future;
      gateway.stream!.add(const AiStreamEvent('delta', {'text': 'partial'}));
      await gateway.stream!.close();
      await task;
      expect(ai.turns.single.status, 'error');
      expect(ai.turns.single.answer, 'partial');
    });
  });
  test(
    'user database v24 to v25 preserves answers and installs only AI tables',
    () async {
      SharedPreferences.setMockInitialValues({});
      final previous = await getDatabasesPath();
      final dir = await Directory.systemTemp.createTemp('ybb_ai_migration_');
      await databaseFactory.setDatabasesPath(dir.path);
      try {
        var db = await UserDBHelper().database;
        await db.insert('Question', {
          'id': 'sentinel',
          'user_answer': 'C',
          'status': 1,
        });
        await UserDBHelper().close();
        final old = await openDatabase(p.join(dir.path, 'user_data.sqlite'));
        await old.execute('DROP TABLE AiSearchTurns');
        await old.execute('DROP TABLE AiSearchSessions');
        await old.setVersion(24);
        await old.close();
        db = await UserDBHelper().database;
        expect(await db.getVersion(), 25);
        expect(
          (await db.query(
            'Question',
            where: 'id=?',
            whereArgs: ['sentinel'],
          )).single['user_answer'],
          'C',
        );
        expect(await db.query('AiSearchSessions'), isEmpty);
        expect(await db.query('AiSearchTurns'), isEmpty);
        expect((await db.rawQuery('PRAGMA foreign_key_check')), isEmpty);
      } finally {
        await UserDBHelper().close();
        await databaseFactory.setDatabasesPath(previous);
        await dir.delete(recursive: true);
      }
    },
  );
}
