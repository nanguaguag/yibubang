import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_search.dart';
import '../models/ai_search_options.dart';

class AiSearchException implements Exception {
  final String message;
  final int? status;
  const AiSearchException(this.message, [this.status]);
  @override
  String toString() => message;
}

abstract class AiSearchGateway {
  Future<AiQuota> quota();
  Stream<AiStreamEvent> search(
    String question,
    List<AiTurn> history,
    String requestId,
  );
  void cancel();
  void dispose();
}

abstract class AiModelGateway {
  String get selectedModel;
  Future<AiModelCatalog> models({bool refresh = false});
  Future<void> selectModel(String model);
}

/// SSE frames may span arbitrary UTF-8/network boundaries.
Stream<AiStreamEvent> decodeAiEvents(Stream<List<int>> bytes) async* {
  var event = 'message';
  final data = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        final decoded = jsonDecode(data.join('\n'));
        yield AiStreamEvent(event, Map<String, dynamic>.from(decoded));
      }
      event = 'message';
      data.clear();
    } else if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
    }
  }
  // Our protocol always terminates complete frames with a blank line.
  if (data.isNotEmpty) throw const AiSearchException('连接提前结束，请重试');
}

class AiSearchClient implements AiSearchGateway, AiModelGateway {
  static const endpoint = String.fromEnvironment(
    'AI_SEARCH_ENDPOINT',
    defaultValue: 'https://yibubang-ai-search-2eg4oq4jcq-an.a.run.app',
  );
  final String baseUrl;
  final http.Client Function() clientFactory;
  http.Client? _active;
  int _cancellation = 0;
  bool _disposed = false;
  Future<void>? _registration;
  String? _deviceId;
  String? _secret;
  @override
  String selectedModel = 'stable';
  AiSearchClient({
    this.baseUrl = endpoint,
    http.Client Function()? clientFactory,
  }) : clientFactory = clientFactory ?? http.Client.new;

  Future<void> _identity() async {
    if (_deviceId != null) return;
    final prefs = await SharedPreferences.getInstance();
    selectedModel = prefs.getString('ai_answer_model') ?? 'stable';
    _deviceId = prefs.getString('ai_installation_id');
    _secret = prefs.getString('ai_installation_secret');
    if (_deviceId == null || _secret == null) {
      final random = Random.secure();
      _deviceId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _secret = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await prefs.setString('ai_installation_id', _deviceId!);
      await prefs.setString('ai_installation_secret', _secret!);
      await prefs.remove('ai_device_registered');
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'X-Device-ID': _deviceId!,
    'Authorization': 'Bearer $_secret',
  };
  Future<void> _register() async {
    await _identity();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('ai_device_registered') == baseUrl) return;
    if (baseUrl.contains('PENDING')) {
      throw const AiSearchException('AI 搜索服务尚未配置');
    }
    final client = clientFactory();
    try {
      final r = await client
          .post(
            Uri.parse('$baseUrl/v1/devices'),
            headers: _headers,
            body: jsonEncode({'installation_id': _deviceId, 'secret': _secret}),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw _error(r.statusCode, r.body);
      await prefs.setString('ai_device_registered', baseUrl);
    } finally {
      client.close();
    }
  }

  Future<void> _ready() => _registration ??= _register().catchError((Object e) {
    _registration = null;
    throw e;
  });

  @override
  Future<AiModelCatalog> models({bool refresh = false}) async {
    try {
      final json = await requestJson(
        '/v1/models?refresh=$refresh',
        timeout: const Duration(seconds: 6),
      );
      final catalog = AiModelCatalog.fromJson(json);
      if (!catalog.models.any((m) => m.id == 'stable')) {
        throw const FormatException('Invalid Answer model directory');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_answer_model_catalog', jsonEncode(json));
      return catalog;
    } catch (_) {
      return localModels();
    }
  }

  /// Shown immediately, even when the backend and Google are unreachable.
  static Future<AiModelCatalog> localModels() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('ai_answer_model_catalog');
    if (cached != null) {
      try {
        final json = Map<String, dynamic>.from(jsonDecode(cached));
        final catalog = AiModelCatalog.fromJson({
          ...json,
          'stale': true,
          'catalog_type': 'local_cache',
        });
        if (catalog.models.any((m) => m.id == 'stable')) return catalog;
      } catch (_) {
        /* Replace corrupt cache with the bundled directory. */
      }
    }
    return AiModelCatalog.fromJson(
      jsonDecode(
        await rootBundle.loadString('ai_backend/answer_model_catalog.json'),
      ),
    );
  }

  @override
  Future<void> selectModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_answer_model', model);
    selectedModel = model;
  }

  AiSearchException _error(int code, String body) {
    try {
      return AiSearchException(
        (jsonDecode(body) as Map)['message'] as String? ?? '服务暂时不可用',
        code,
      );
    } catch (_) {
      return AiSearchException('服务暂时不可用（$code）', code);
    }
  }

  /// Reuses the same installation identity for retrieval and private page links.
  Future<Map<String, dynamic>> requestJson(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_disposed) throw const AiSearchException('页面已关闭');
    await _ready().timeout(timeout);
    final client = clientFactory();
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response =
          await (body == null
                  ? client.get(uri, headers: _headers)
                  : client.post(uri, headers: _headers, body: jsonEncode(body)))
              .timeout(timeout);
      if (response.statusCode != 200) {
        throw _error(response.statusCode, response.body);
      }
      return Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    } on TimeoutException {
      throw const AiSearchException('连接超时，请稍后重试');
    } on http.ClientException {
      throw const AiSearchException('连接失败，请检查网络后重试');
    } on FormatException {
      throw const AiSearchException('服务返回异常，请稍后重试');
    } finally {
      client.close();
    }
  }

  @override
  Future<AiQuota> quota() async {
    await _ready();
    final client = clientFactory();
    try {
      final response = await client
          .get(Uri.parse('$baseUrl/v1/quota'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw _error(response.statusCode, response.body);
      }
      return AiQuota.fromJson(jsonDecode(response.body));
    } finally {
      client.close();
    }
  }

  @override
  Stream<AiStreamEvent> search(
    String question,
    List<AiTurn> history,
    String requestId,
  ) async* {
    final cancellation = _cancellation;
    await _ready();
    if (_disposed || cancellation != _cancellation) return;
    final prefs = await SharedPreferences.getInstance();
    final options = AiSearchOptions.fromPreferences(prefs);
    selectedModel = prefs.getString('ai_answer_model') ?? 'stable';
    final client = clientFactory();
    _active = client;
    try {
      final context = history
          .where((t) => t.status == 'complete')
          .toList()
          .reversed
          .take(3)
          .toList()
          .reversed
          .map((t) => {'question': t.question, 'answer': t.answer})
          .toList();
      final payload = {
        'question': question,
        'request_id': requestId,
        'history': context,
        'model': selectedModel,
        'rephrase': options.rephrase,
        'streaming': options.streaming,
        'textbook_count': options.textbookCount,
        'result_count': options.resultCount,
      };
      var encoded = jsonEncode(payload);
      // Bound the actual UTF-8 bytes, including long Chinese follow-up history.
      while (utf8.encode(encoded).length > 60000 && context.isNotEmpty) {
        context.removeAt(0);
        encoded = jsonEncode(payload);
      }
      final request = http.Request('POST', Uri.parse('$baseUrl/v1/search'))
        ..headers.addAll({..._headers, 'Accept': 'text/event-stream'})
        ..body = encoded;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw _error(response.statusCode, body);
      }
      var complete = false;
      await for (final event in decodeAiEvents(
        response.stream.timeout(const Duration(seconds: 90)),
      )) {
        if (event.type == 'done' || event.type == 'error') complete = true;
        yield event;
      }
      if (!complete) throw const AiSearchException('连接中断，已保留当前回答');
    } finally {
      client.close();
      if (identical(_active, client)) _active = null;
    }
  }

  @override
  void cancel() {
    ++_cancellation;
    _active?.close();
    _active = null;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
  }
}
