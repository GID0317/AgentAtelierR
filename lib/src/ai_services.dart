import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_controller.dart';
import 'device_agent_tools.dart';
import 'runtime_log.dart';

class SecretStore {
  const SecretStore();

  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());

  Future<String> readOpenAiKey() async =>
      await _storage.read(key: 'openai_api_key') ?? '';

  Future<String> readGeminiKey() async =>
      await _storage.read(key: 'gemini_api_key') ?? '';

  Future<String> readFishAudioKey() async =>
      await _storage.read(key: 'fish_audio_api_key') ?? '';

  Future<String> readDashScopeKey() async =>
      await _storage.read(key: 'dashscope_api_key') ?? '';

  Future<String> readGenericTtsKey() async =>
      await _storage.read(key: 'generic_tts_api_key') ?? '';

  Future<void> writeOpenAiKey(String value) =>
      _writeOrDelete('openai_api_key', value);

  Future<void> writeGeminiKey(String value) =>
      _writeOrDelete('gemini_api_key', value);

  Future<String> readLlmKey(LlmProvider provider) => switch (provider) {
    LlmProvider.openAiCompatible => readOpenAiKey(),
    LlmProvider.gemini => readGeminiKey(),
  };

  Future<void> writeFishAudioKey(String value) =>
      _writeOrDelete('fish_audio_api_key', value);

  Future<void> writeDashScopeKey(String value) =>
      _writeOrDelete('dashscope_api_key', value);

  Future<void> writeGenericTtsKey(String value) =>
      _writeOrDelete('generic_tts_api_key', value);

  Future<String> readTtsKey(TtsProvider provider) => switch (provider) {
    TtsProvider.fishAudio => readFishAudioKey(),
    TtsProvider.dashScope => readDashScopeKey(),
    TtsProvider.generic => readGenericTtsKey(),
  };

  Future<void> writeTtsKey(TtsProvider provider, String value) =>
      switch (provider) {
        TtsProvider.fishAudio => writeFishAudioKey(value),
        TtsProvider.dashScope => writeDashScopeKey(value),
        TtsProvider.generic => writeGenericTtsKey(value),
      };

  Future<void> _writeOrDelete(String key, String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty
        ? _storage.delete(key: key)
        : _storage.write(key: key, value: trimmed);
  }
}

class OpenAiCompatibleClient {
  OpenAiCompatibleClient({
    http.Client? client,
    WebSearchClient? webSearchClient,
    this._agentToolExecutor,
  }) : _client = client ?? http.Client(),
       _webSearchClient = webSearchClient ?? WebSearchClient(client: client);

  final http.Client _client;
  final WebSearchClient _webSearchClient;
  final AgentToolExecutor? _agentToolExecutor;

  List<Map<String, dynamic>> get _agentTools => [
    _webSearchTool,
    if (_agentToolExecutor != null) ...[
      _currentLocationTool,
      _nearbyServicesTool,
      _launchableAppsTool,
      _localDateTimeTool,
    ],
  ];

  Stream<String> streamChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    String? reasoningEffort,
    double? outputMultiplier,
    bool agentEnabled = false,
  }) async* {
    final conversation = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': agentEnabled
            ? '$systemPrompt\n\n你可以按需使用工具。需要实时或不确定的网络信息时调用 web_search，并在相关事实后保留来源 URL。只有用户的问题确实依赖当前位置、周边服务或设备应用选择时，才能调用相应设备工具；调用定位可能触发系统权限弹窗，用户拒绝后不得猜测位置或反复申请。应用列表仅用于推荐，不得声称已经打开、操作或检查了其他应用。优先并行调用互不依赖的工具，避免重复调用。'
            : systemPrompt,
      },
      for (final message in messages)
        {
          'role': message.isUser ? 'user' : 'assistant',
          'content': _messageContent(message),
        },
    ];
    if (agentEnabled) {
      yield* _streamAgentChat(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        conversation: conversation,
        reasoningEffort: reasoningEffort,
        outputMultiplier: outputMultiplier,
      );
      return;
    }

    yield* _streamRequest(
      baseUrl: baseUrl,
      apiKey: apiKey,
      body: _chatBody(
        model: model,
        stream: true,
        conversation: conversation,
        reasoningEffort: reasoningEffort,
        outputMultiplier: outputMultiplier,
      ),
    );
  }

  Stream<String> _streamAgentChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> conversation,
    required String? reasoningEffort,
    required double? outputMultiplier,
  }) async* {
    const maxToolRounds = 4;
    for (var round = 0; round < maxToolRounds; round += 1) {
      final assistant = await _completeMessage(
        baseUrl: baseUrl,
        apiKey: apiKey,
        body: _chatBody(
          model: model,
          stream: false,
          conversation: conversation,
          reasoningEffort: reasoningEffort,
          outputMultiplier: outputMultiplier,
          tools: _agentTools,
        ),
      );
      final toolCalls = (assistant['tool_calls'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      if (toolCalls.isEmpty) {
        final content = _messageText(assistant);
        if (content.isNotEmpty) yield content;
        return;
      }

      conversation.add({
        'role': 'assistant',
        'content': _messageText(assistant),
        'tool_calls': toolCalls,
      });
      for (var index = 0; index < toolCalls.length; index += 1) {
        final toolCall = toolCalls[index];
        conversation.add({
          'role': 'tool',
          'tool_call_id': toolCall['id'] as String? ?? 'web_search',
          'content': index < 3
              ? await _executeToolCall(toolCall)
              : '工具调用失败：单轮最多执行 3 个工具调用。',
        });
      }
    }

    yield* _streamRequest(
      baseUrl: baseUrl,
      apiKey: apiKey,
      body: _chatBody(
        model: model,
        stream: true,
        conversation: conversation,
        reasoningEffort: reasoningEffort,
        outputMultiplier: outputMultiplier,
        tools: _agentTools,
        toolChoice: 'none',
      ),
    );
  }

  Map<String, dynamic> _chatBody({
    required String model,
    required bool stream,
    required List<Map<String, dynamic>> conversation,
    required String? reasoningEffort,
    required double? outputMultiplier,
    List<Map<String, dynamic>>? tools,
    String? toolChoice,
  }) {
    final body = <String, dynamic>{
      'model': model,
      'stream': stream,
      'messages': conversation,
    };
    if (reasoningEffort != null) body['reasoning_effort'] = reasoningEffort;
    if (outputMultiplier != null) {
      body['max_completion_tokens'] = (4096 * outputMultiplier).round();
    }
    if (tools != null) body['tools'] = tools;
    if (toolChoice != null) body['tool_choice'] = toolChoice;
    return body;
  }

  Stream<String> _streamRequest({
    required String baseUrl,
    required String apiKey,
    required Map<String, dynamic> body,
  }) async* {
    final started = DateTime.now();
    final request = http.Request('POST', _endpoint(baseUrl, 'chat/completions'))
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(body);

    final response = await _client.send(request);
    RuntimeLog.instance.communication(
      source: 'LLM',
      direction: 'request',
      method: 'POST',
      url: request.url.toString(),
      payload: body,
    );
    RuntimeLog.instance.communication(
      source: 'LLM',
      direction: 'response',
      method: 'POST',
      url: request.url.toString(),
      statusCode: response.statusCode,
      duration: DateTime.now().difference(started),
      payload: {
        'stream': true,
        'content_type': response.headers['content-type'],
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw AiServiceException(
        'AI 请求失败 (${response.statusCode})${_serverMessage(body)}',
      );
    }

    final deltas = StringBuffer();
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        throw AiServiceException(error['message'] as String? ?? 'AI 流式响应返回错误');
      }
      final delta = _readDelta(decoded);
      if (delta.isNotEmpty) {
        deltas.write(delta);
        yield delta;
      }
    }
    RuntimeLog.instance.communication(
      source: 'LLM',
      direction: 'stream',
      method: 'POST',
      url: request.url.toString(),
      duration: DateTime.now().difference(started),
      payload: {'text': deltas.toString(), 'length': deltas.length},
    );
  }

  Future<Map<String, dynamic>> _completeMessage({
    required String baseUrl,
    required String apiKey,
    required Map<String, dynamic> body,
  }) async {
    final started = DateTime.now();
    final url = _endpoint(baseUrl, 'chat/completions');
    final response = await _client.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    RuntimeLog.instance.communication(
      source: 'LLM',
      direction: 'request',
      method: 'POST',
      url: url.toString(),
      payload: body,
    );
    RuntimeLog.instance.communication(
      source: 'LLM',
      direction: 'response',
      method: 'POST',
      url: url.toString(),
      statusCode: response.statusCode,
      duration: DateTime.now().difference(started),
      payload: response.body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException(
        'AI 请求失败 (${response.statusCode})${_serverMessage(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return <String, dynamic>{};
    final message = (choices.first as Map<String, dynamic>)['message'];
    return message is Map<String, dynamic> ? message : <String, dynamic>{};
  }

  Future<String> _executeToolCall(Map<String, dynamic> toolCall) async {
    final function = toolCall['function'];
    if (function is! Map<String, dynamic>) {
      return '工具调用失败：不支持该工具。';
    }
    final name = function['name'] as String? ?? '';
    try {
      final rawArguments = function['arguments'] as String? ?? '{}';
      final arguments = jsonDecode(rawArguments) as Map<String, dynamic>;
      final started = DateTime.now();
      final output = switch (name) {
        'web_search' => await _executeWebSearch(arguments),
        'search_nearby_services' => await _executeNearbySearch(arguments),
        'get_current_location' ||
        'list_launchable_apps' ||
        'get_local_datetime' =>
          _agentToolExecutor == null
              ? '工具调用失败：当前设备未启用该工具。'
              : await _agentToolExecutor(name, arguments),
        _ => '工具调用失败：不支持工具 $name。',
      };
      RuntimeLog.instance.info(
        'Agent',
        '工具调用完成 name=$name, durationMs=${DateTime.now().difference(started).inMilliseconds}, resultChars=${output.length}',
      );
      return output;
    } on Object catch (error) {
      return '工具调用失败：$error';
    }
  }

  Future<String> _executeWebSearch(Map<String, dynamic> arguments) async {
    final query = (arguments['query'] as String? ?? '').trim();
    if (query.isEmpty) return '搜索失败：query 不能为空。';
    final results = await _webSearchClient.search(query);
    return _formatSearchResults(query, results);
  }

  Future<String> _executeNearbySearch(Map<String, dynamic> arguments) async {
    if (_agentToolExecutor == null) return '周边搜索失败：当前设备不支持定位工具。';
    final query = (arguments['query'] as String? ?? '').trim();
    if (query.isEmpty) return '周边搜索失败：query 不能为空。';
    final locationText = await _agentToolExecutor(
      'get_current_location',
      const {},
    );
    Map<String, dynamic> location;
    try {
      location = jsonDecode(locationText) as Map<String, dynamic>;
    } on Object {
      return '周边搜索无法继续：$locationText';
    }
    final latitude = location['latitude'];
    final longitude = location['longitude'];
    if (latitude is! num || longitude is! num) {
      return '周边搜索无法继续：没有取得有效坐标。';
    }
    final searchQuery = '$query 附近 $latitude,$longitude';
    final results = await _webSearchClient.search(searchQuery);
    return [
      '当前位置坐标：$latitude,$longitude（仅用于本次查询）',
      _formatSearchResults(searchQuery, results),
    ].join('\n\n');
  }

  String _formatSearchResults(String query, List<WebSearchResult> results) => [
    '搜索词：$query',
    for (var index = 0; index < results.length; index += 1)
      '${index + 1}. ${results[index].title}\n${results[index].snippet}\n${results[index].url}',
  ].join('\n\n');

  String _messageText(Map<String, dynamic> message) {
    final content = message['content'];
    if (content is String) return content;
    if (content is List<dynamic>) {
      return content
          .whereType<Map<String, dynamic>>()
          .map((part) => part['text'] as String? ?? '')
          .join();
    }
    return '';
  }

  static const Map<String, dynamic> _webSearchTool = {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description': '搜索公开网页，返回标题、摘要和来源 URL。用于需要当前信息或外部事实的问题。',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '简洁、具体的搜索关键词'},
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    },
  };

  static const Map<String, dynamic> _currentLocationTool = {
    'type': 'function',
    'function': {
      'name': 'get_current_location',
      'description': '取得设备当前经纬度。仅在天气、路线、周边生活服务等明确依赖用户位置的问题中使用；可能按需请求定位权限。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
  };

  static const Map<String, dynamic> _nearbyServicesTool = {
    'type': 'function',
    'function': {
      'name': 'search_nearby_services',
      'description': '取得当前位置并搜索附近的商店、餐饮、医院、交通或其他生活服务。仅在用户明确询问周边信息时使用。',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '要查找的具体服务，例如附近仍营业的药店'},
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    },
  };

  static const Map<String, dynamic> _launchableAppsTool = {
    'type': 'function',
    'function': {
      'name': 'list_launchable_apps',
      'description': '列出设备上具有桌面启动入口的应用，供应用选择和使用建议参考。不读取应用内容、使用记录，也不会启动应用。',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '可选的应用名称或包名筛选词'},
          'limit': {'type': 'integer', 'minimum': 1, 'maximum': 80},
        },
        'additionalProperties': false,
      },
    },
  };

  static const Map<String, dynamic> _localDateTimeTool = {
    'type': 'function',
    'function': {
      'name': 'get_local_datetime',
      'description': '取得设备当前本地日期、时间和时区。用于时间敏感的问题，无需系统权限。',
      'parameters': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
  };

  Object _messageContent(ChatMessage message) {
    if (message.attachments.isEmpty) return message.text;
    final parts = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': message.text.trim().isEmpty ? '请分析这些附件。' : message.text,
      },
    ];
    for (final attachment in message.attachments) {
      final bytes = attachment.bytes;
      if (bytes == null) {
        parts.add({'type': 'text', 'text': '[之前发送的附件：${attachment.name}]'});
        continue;
      }
      final dataUrl =
          'data:${attachment.mimeType};base64,${base64Encode(bytes)}';
      if (attachment.isImage) {
        parts.add({
          'type': 'image_url',
          'image_url': {'url': dataUrl},
        });
      } else {
        parts.add({
          'type': 'file',
          'file': {'filename': attachment.name, 'file_data': dataUrl},
        });
      }
    }
    return parts;
  }

  Future<String> complete({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
  }) async {
    final started = DateTime.now();
    final url = _endpoint(baseUrl, 'chat/completions');
    final requestBody = {'model': model, 'stream': false, 'messages': messages};
    final response = await _client.post(
      url,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );
    RuntimeLog.instance.communication(
      source: 'LLM',
      direction: 'request',
      method: 'POST',
      url: url.toString(),
      payload: requestBody,
    );
    RuntimeLog.instance.communication(
      source: 'LLM',
      direction: 'response',
      method: 'POST',
      url: url.toString(),
      statusCode: response.statusCode,
      duration: DateTime.now().difference(started),
      payload: response.body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException(
        '记忆整理失败 (${response.statusCode})${_serverMessage(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return '';
    final message = (choices.first as Map<String, dynamic>)['message'];
    if (message is! Map<String, dynamic>) return '';
    return message['content'] as String? ?? '';
  }

  Uri _endpoint(String baseUrl, String path) {
    var normalized = baseUrl.trim();
    if (normalized.isEmpty) normalized = 'https://api.openai.com/v1';
    normalized = normalized.replaceAll(RegExp(r'/+$'), '');
    if (normalized.endsWith('/chat/completions')) return Uri.parse(normalized);
    return Uri.parse('$normalized/$path');
  }

  String _readDelta(Map<String, dynamic> event) {
    if (event['type'] == 'response.output_text.delta') {
      return event['delta'] as String? ?? '';
    }
    final choices = event['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return '';
    final choice = choices.first as Map<String, dynamic>;
    final delta = choice['delta'];
    if (delta is Map<String, dynamic>) {
      final content = delta['content'];
      if (content is String) return content;
      if (content is List<dynamic>) {
        return content
            .whereType<Map<String, dynamic>>()
            .map((part) => part['text'] as String? ?? '')
            .join();
      }
    }
    return '';
  }

  String _serverMessage(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'] as String?;
        if (message != null && message.isNotEmpty) return '：$message';
      }
    } on FormatException {
      // Preserve a concise client-facing error when the server returns HTML.
    }
    return '';
  }
}

class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  final String title;
  final String url;
  final String snippet;
}

class WebSearchClient {
  WebSearchClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<WebSearchResult>> search(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || normalizedQuery.length > 300) {
      throw AiServiceException('搜索词长度必须在 1 到 300 个字符之间');
    }
    final response = await _client
        .get(
          Uri.https('html.duckduckgo.com', '/html/', {'q': normalizedQuery}),
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Mobile Safari/537.36',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException('联网搜索失败 (${response.statusCode})');
    }

    final document = html_parser.parse(response.body);
    final results = <WebSearchResult>[];
    for (final element in document.querySelectorAll('.result')) {
      final anchor = element.querySelector('.result__a');
      if (anchor == null) continue;
      final title = anchor.text.trim();
      final url = _resultUrl(anchor.attributes['href'] ?? '');
      final snippet = element.querySelector('.result__snippet')?.text.trim();
      if (title.isEmpty || url.isEmpty) continue;
      results.add(
        WebSearchResult(title: title, url: url, snippet: snippet ?? ''),
      );
      if (results.length == 5) break;
    }
    if (results.isEmpty) throw AiServiceException('没有找到可用的搜索结果');
    return results;
  }

  String _resultUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return '';
    final redirected = uri.queryParameters['uddg'];
    if (redirected != null && redirected.isNotEmpty) return redirected;
    if (uri.hasScheme) return uri.toString();
    return '';
  }
}

class FishAudioClient {
  FishAudioClient({http.Client? client}) : _client = client ?? http.Client();

  static const endpoint = 'https://api.fish.audio/v1/tts';
  final http.Client _client;

  Future<String> synthesize({
    required String apiKey,
    required String referenceId,
    required String text,
    String model = 's2-pro',
    String format = 'mp3',
    String latency = 'normal',
    double speed = 1.0,
    double temperature = 0.7,
    String baseUrl = endpoint,
  }) async {
    final bytes = await synthesizeBytes(
      apiKey: apiKey,
      referenceId: referenceId,
      text: text,
      model: model,
      format: format,
      latency: latency,
      speed: speed,
      temperature: temperature,
      baseUrl: baseUrl,
    );
    return _writeTemporaryAudio(bytes, 'fish_tts', format);
  }

  Future<Uint8List> synthesizeBytes({
    required String apiKey,
    required String referenceId,
    required String text,
    String model = 's2-pro',
    String format = 'mp3',
    String latency = 'normal',
    double speed = 1.0,
    double temperature = 0.7,
    String baseUrl = endpoint,
  }) async {
    final started = DateTime.now();
    final uri = Uri.parse(baseUrl.trim().isEmpty ? endpoint : baseUrl.trim());
    final requestBody = {
      'text': text,
      'reference_id': referenceId,
      'temperature': temperature.clamp(0.0, 1.0),
      'normalize': true,
      'format': format,
      'latency': latency,
      'prosody': {
        'speed': speed.clamp(0.5, 2.0),
        'volume': 0.0,
        'normalize_loudness': true,
      },
    };
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'model': model,
      },
      body: jsonEncode(requestBody),
    );
    RuntimeLog.instance.communication(
      source: 'TTS',
      direction: 'request',
      method: 'POST',
      url: uri.toString(),
      payload: requestBody,
    );
    RuntimeLog.instance.communication(
      source: 'TTS',
      direction: 'response',
      method: 'POST',
      url: uri.toString(),
      statusCode: response.statusCode,
      duration: DateTime.now().difference(started),
      payload: {
        'bytes': response.bodyBytes.length,
        'content_type': response.headers['content-type'],
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var details = '';
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final message = decoded['message'] as String?;
        if (message != null && message.isNotEmpty) details = '：$message';
      } on Object {
        // Fish Audio can return a non-JSON proxy error.
      }
      throw AiServiceException(
        'Fish Audio 请求失败 (${response.statusCode})$details',
      );
    }
    return response.bodyBytes;
  }
}

class DashScopeTtsClient {
  DashScopeTtsClient({http.Client? client}) : _client = client ?? http.Client();

  static const endpoint =
      'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation';
  final http.Client _client;

  Future<String> createQwenVoice({
    required String apiKey,
    required Uint8List audioBytes,
    required String mimeType,
    required String preferredName,
    required String targetModel,
    String language = 'Chinese',
    String audioText = '',
    String baseUrl = endpoint,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const AiServiceException('请填写 DashScope API Key');
    }
    if (targetModel.trim().isEmpty) {
      throw const AiServiceException('请填写目标 TTS 模型');
    }
    if (!RegExp(r'^[A-Za-z0-9_]{1,16}$').hasMatch(preferredName.trim())) {
      throw const AiServiceException('音色名称只能包含数字、英文字母和下划线，最多 16 个字符');
    }
    if (!const {'audio/wav', 'audio/mpeg', 'audio/mp4'}.contains(mimeType)) {
      throw const AiServiceException('参考音频仅支持 WAV、MP3 或 M4A');
    }
    if (audioBytes.isEmpty) throw const AiServiceException('参考音频为空');
    if (audioBytes.length >= 10 * 1024 * 1024) {
      throw const AiServiceException('参考音频必须小于 10MB');
    }
    final dataUrl = 'data:$mimeType;base64,${base64Encode(audioBytes)}';
    final uri = Uri.parse(_customizationEndpoint(baseUrl));
    final requestBody = {
      'model': 'qwen-voice-enrollment',
      'input': {
        'action': 'create',
        'target_model': targetModel,
        'audio': {'data': dataUrl},
        'preferred_name': preferredName,
        if (language.trim().isNotEmpty) 'language_hints': [language],
        if (audioText.trim().isNotEmpty) 'text': audioText.trim(),
      },
    };
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );
    RuntimeLog.instance.communication(
      source: 'TTS',
      direction: 'request',
      method: 'POST',
      url: uri.toString(),
      payload: {
        'model': 'qwen-voice-enrollment',
        'input': {
          'action': 'create',
          'target_model': targetModel,
          'preferred_name': preferredName,
          'audio_bytes': audioBytes.length,
        },
      },
    );
    RuntimeLog.instance.communication(
      source: 'TTS',
      direction: 'response',
      method: 'POST',
      url: uri.toString(),
      statusCode: response.statusCode,
      payload: response.body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException(
        '百炼声音复刻失败 (${response.statusCode})${_responseMessage(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final output = decoded['output'] as Map<String, dynamic>?;
    if (decoded['fallback_mode'] == true) {
      final reason = decoded['fallback_reason'];
      throw AiServiceException(
        '百炼返回了降级结果${reason is String && reason.isNotEmpty ? '：$reason' : ''}',
      );
    }
    final voice = output?['voice'] as String? ?? output?['voice_id'] as String?;
    if (voice == null || voice.isEmpty) {
      throw const AiServiceException('百炼声音复刻响应中没有 Voice ID');
    }
    return voice;
  }

  String _customizationEndpoint(String configured) {
    final raw = configured.trim().isEmpty ? endpoint : configured.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return raw;
    final host = uri.host.replaceFirst(
      'dashscope.aliyuncs.com',
      'dashscope.aliyuncs.com',
    );
    return Uri(
      scheme: uri.scheme,
      host: host,
      port: uri.hasPort ? uri.port : null,
      path: '/api/v1/services/audio/tts/customization',
    ).toString();
  }

  Future<String> synthesize({
    required String apiKey,
    required String text,
    required String model,
    required String voice,
    String baseUrl = endpoint,
    String language = 'Chinese',
    String instructions = '',
  }) async {
    final bytes = await synthesizeBytes(
      apiKey: apiKey,
      text: text,
      model: model,
      voice: voice,
      baseUrl: baseUrl,
      language: language,
      instructions: instructions,
    );
    return _writeTemporaryAudio(bytes, 'dashscope_tts', 'wav');
  }

  Future<Uint8List> synthesizeBytes({
    required String apiKey,
    required String text,
    required String model,
    required String voice,
    String baseUrl = endpoint,
    String language = 'Chinese',
    String instructions = '',
  }) async {
    final started = DateTime.now();
    final uri = Uri.parse(baseUrl.trim().isEmpty ? endpoint : baseUrl.trim());
    final requestBody = {
      'model': model,
      'input': {
        'text': text,
        'voice': voice,
        'language_type': language,
        if (instructions.trim().isNotEmpty) ...{
          'instructions': instructions.trim(),
          'optimize_instructions': true,
        },
      },
    };
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(requestBody),
    );
    RuntimeLog.instance.communication(
      source: 'TTS',
      direction: 'request',
      method: 'POST',
      url: uri.toString(),
      payload: requestBody,
    );
    RuntimeLog.instance.communication(
      source: 'TTS',
      direction: 'response',
      method: 'POST',
      url: uri.toString(),
      statusCode: response.statusCode,
      duration: DateTime.now().difference(started),
      payload: response.body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException(
        '百炼 Qwen-TTS 请求失败 (${response.statusCode})${_responseMessage(response.body)}',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final output = decoded['output'] as Map<String, dynamic>?;
    final audio = output?['audio'] as Map<String, dynamic>?;
    final url = audio?['url'] as String? ?? output?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw const AiServiceException('百炼 Qwen-TTS 响应中没有音频 URL');
    }
    final audioResponse = await _client.get(Uri.parse(url));
    if (audioResponse.statusCode < 200 || audioResponse.statusCode >= 300) {
      throw AiServiceException('百炼音频下载失败 (${audioResponse.statusCode})');
    }
    return audioResponse.bodyBytes;
  }
}

class GenericTtsClient {
  GenericTtsClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> synthesize({
    required String baseUrl,
    required String apiKey,
    required String text,
    required String model,
    required String voice,
    String format = 'wav',
    double speed = 1.0,
    String instructions = '',
  }) async {
    final bytes = await synthesizeBytes(
      baseUrl: baseUrl,
      apiKey: apiKey,
      text: text,
      model: model,
      voice: voice,
      format: format,
      speed: speed,
      instructions: instructions,
    );
    return _writeTemporaryAudio(bytes, 'generic_tts', format);
  }

  Future<Uint8List> synthesizeBytes({
    required String baseUrl,
    required String apiKey,
    required String text,
    required String model,
    required String voice,
    String format = 'wav',
    double speed = 1.0,
    String instructions = '',
  }) async {
    final started = DateTime.now();
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final endpoint = normalized.endsWith('/audio/speech')
        ? normalized
        : '$normalized/audio/speech';
    final response = await _client.post(
      Uri.parse(endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'input': text,
        'voice': voice,
        'response_format': format,
        'speed': speed.clamp(0.5, 2.0),
        if (instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
      }),
    );
    RuntimeLog.instance.communication(
      source: 'TTS',
      direction: 'request',
      method: 'POST',
      url: endpoint,
      payload: {
        'model': model,
        'input': text,
        'voice': voice,
        'response_format': format,
        'speed': speed.clamp(0.5, 2.0),
        if (instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
      },
    );
    RuntimeLog.instance.communication(
      source: 'TTS',
      direction: 'response',
      method: 'POST',
      url: endpoint,
      statusCode: response.statusCode,
      duration: DateTime.now().difference(started),
      payload: {
        'bytes': response.bodyBytes.length,
        'content_type': response.headers['content-type'],
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiServiceException(
        '通用 TTS 请求失败 (${response.statusCode})${_responseMessage(response.body)}',
      );
    }
    return response.bodyBytes;
  }
}

String _responseMessage(String body) {
  try {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final error = decoded['error'];
    final message =
        decoded['message'] ??
        (error is Map<String, dynamic> ? error['message'] : error);
    return message is String && message.isNotEmpty ? '：$message' : '';
  } on Object {
    return '';
  }
}

Future<String> _writeTemporaryAudio(
  Uint8List bytes,
  String prefix,
  String requestedExtension,
) async {
  final extension = detectAudioContainerExtension(bytes);
  if (extension == null) {
    final preview = utf8
        .decode(bytes.take(160).toList(growable: false), allowMalformed: true)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    throw AiServiceException(
      'TTS 返回的内容不是可识别的音频文件'
      '${preview.isEmpty ? '' : '：${preview.length > 120 ? preview.substring(0, 120) : preview}'}',
    );
  }
  final normalizedRequested = requestedExtension.trim().toLowerCase();
  if (normalizedRequested.isNotEmpty && normalizedRequested != extension) {
    RuntimeLog.instance.info(
      'TTS',
      '响应音频格式与请求不同，requested=$normalizedRequested, detected=$extension, bytes=${bytes.length}',
    );
  }
  final directory = await getTemporaryDirectory();
  final file = File(
    '${directory.path}${Platform.pathSeparator}${prefix}_${DateTime.now().millisecondsSinceEpoch}.$extension',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

String? detectAudioContainerExtension(Uint8List bytes) {
  bool startsWith(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[offset + index] != signature[index]) return false;
    }
    return true;
  }

  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
      startsWith(const [0x57, 0x41, 0x56, 0x45], 8)) {
    return 'wav';
  }
  if (startsWith(const [0x49, 0x44, 0x33]) ||
      (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)) {
    return 'mp3';
  }
  if (startsWith(const [0x4f, 0x67, 0x67, 0x53])) return 'ogg';
  if (startsWith(const [0x66, 0x4c, 0x61, 0x43])) return 'flac';
  if (startsWith(const [0x66, 0x74, 0x79, 0x70], 4)) return 'm4a';
  return null;
}

class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
