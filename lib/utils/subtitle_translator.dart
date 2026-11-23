import 'dart:convert';
import 'dart:math' as math;

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// 字幕翻译
///
/// 默认走腾讯混元翻译专用模型（OpenAI 兼容接口，国内直连）。
/// 只翻译文本，`from`/`to` 时间轴原样保留，因此不会出现时间错位。
abstract final class SubtitleTranslator {
  /// 单次请求携带的字幕条数，太长容易碰到模型输入上限或触发限流
  static const int _batchSize = 20;
  static const int _maxRetry = 2;

  /// 分隔符模式使用的分隔标记
  static const String _split = '<<<SPLIT>>>';

  static const String _promptJson = '''
你是专业的影视字幕译者。输入是一个 JSON 字符串数组，每项是一句字幕。
请逐条翻译成简体中文：保持口语化、简洁自然，不要合并或拆分句子，不要补充解释，保留原有语气。
只输出一个与输入等长的 JSON 字符串数组（纯 JSON，不要 markdown 代码块，不要任何说明文字），元素顺序与输入完全一致。''';

  static const String _promptSplit = '''
你是专业的影视字幕译者。输入是用 $_split 分隔的多句字幕。
请逐句翻译成简体中文：保持口语化、简洁自然，不要合并或拆分句子，不要补充解释，保留原有语气。
输出时用同样的 $_split 分隔每一句译文，句数必须与输入完全一致，不要输出任何多余内容。''';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 90),
      headers: const {'Content-Type': 'application/json'},
    ),
  );

  /// 是否具备翻译条件（开关已开且至少有可用通道）
  static bool get enabled =>
      Pref.subtitleTranslateEnabled &&
      (Pref.subtitleTranslateApiKey.isNotEmpty || _fallbackProvider != null);

  /// 翻译 B 站字幕 body（`[{from,to,content}]`），返回同样结构的列表
  static Future<List<Map<String, dynamic>>?> translate(List body) async {
    final sources = <String>[];
    for (final item in body) {
      sources.add(item is Map ? '${item['content'] ?? ''}'.trim() : '');
    }
    if (sources.isEmpty) return null;

    final results = await _translateLines(sources);
    if (results == null || results.length != sources.length) return null;

    final keepOriginal = Pref.subtitleTranslateMode == 0;
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < body.length; i++) {
      final item = body[i];
      if (item is! Map) return null;
      final src = sources[i];
      final dst = results[i].trim();
      out.add({
        'from': item['from'],
        'to': item['to'],
        'content': dst.isEmpty ? src : (keepOriginal ? '$src\n$dst' : dst),
      });
    }
    return out;
  }

  /// 测试接口：先试主通道，失败再试备用通道
  static Future<({bool ok, String text, bool viaFallback})> test() async {
    const lines = ['Hello, world.'];
    final primaryApiKey = Pref.subtitleTranslateApiKey.trim();
    if (primaryApiKey.isNotEmpty) {
      final res = await _requestProvider(
        (
          baseUrl: Pref.subtitleTranslateBaseUrl,
          model: Pref.subtitleTranslateModel,
          apiKey: primaryApiKey,
        ),
        lines,
      );
      if (res != null && res.isNotEmpty) {
        return (ok: true, text: res.first, viaFallback: false);
      }
    }

    final fallback = _fallbackProvider;
    if (fallback == null) {
      return (ok: false, text: '', viaFallback: false);
    }
    final res = await _requestProvider(fallback, lines);
    if (res != null && res.isNotEmpty) {
      return (ok: true, text: res.first, viaFallback: true);
    }
    return (ok: false, text: '', viaFallback: true);
  }

  static Future<List<String>?> _translateLines(List<String> lines) async {
    final out = <String>[];
    for (var start = 0; start < lines.length; start += _batchSize) {
      final end = math.min(start + _batchSize, lines.length);
      final res = await _translateBatch(lines.sublist(start, end));
      if (res == null) return null;
      out.addAll(res);
    }
    return out;
  }

  /// 带缓存与二分降级：整批失败就拆半重试，避免个别超长句子拖死整集
  static Future<List<String>?> _translateBatch(List<String> batch) async {
    final key = _cacheKey(batch);
    final cached = _readCache(key, batch.length);
    if (cached != null) return cached;

    final res = await _request(batch);
    if (res != null) {
      await _writeCache(key, res);
      return res;
    }
    if (batch.length == 1) return null;

    final mid = batch.length ~/ 2;
    final left = await _translateBatch(batch.sublist(0, mid));
    if (left == null) return null;
    final right = await _translateBatch(batch.sublist(mid));
    if (right == null) return null;
    return [...left, ...right];
  }

  static Future<List<String>?> _request(List<String> batch) async {
    // 主通道：腾讯混元
    final primaryApiKey = Pref.subtitleTranslateApiKey.trim();
    if (primaryApiKey.isNotEmpty) {
      final res = await _requestProvider(
        (
          baseUrl: Pref.subtitleTranslateBaseUrl,
          model: Pref.subtitleTranslateModel,
          apiKey: primaryApiKey,
        ),
        batch,
      );
      if (res != null) return res;
    }

    // 备用通道：智谱 GLM-4.7-Flash
    final fallback = _fallbackProvider;
    if (fallback == null) return null;
    return _requestProvider(fallback, batch);
  }

  /// 备用通道配置，未启用或没填密钥时不参与
  static ({String baseUrl, String model, String apiKey})?
  get _fallbackProvider {
    final apiKey = Pref.subtitleTranslateFallbackApiKey.trim();
    if (!Pref.subtitleTranslateFallbackEnabled || apiKey.isEmpty) return null;
    return (
      baseUrl: Pref.subtitleTranslateFallbackBaseUrl,
      model: Pref.subtitleTranslateFallbackModel,
      apiKey: apiKey,
    );
  }

  static Future<List<String>?> _requestProvider(
    ({String baseUrl, String model, String apiKey}) provider,
    List<String> batch,
  ) async {
    // 优先让模型返回 JSON 数组，按行数对齐最稳
    final res = await _requestWith(
      provider: provider,
      prompt: _promptJson,
      content: jsonEncode(batch),
      expect: batch.length,
      parse: _parseArray,
    );
    if (res != null) return res;

    // 有些翻译专用模型不按 JSON 输出，退回分隔符格式再试一次
    return _requestWith(
      provider: provider,
      prompt: _promptSplit,
      content: batch.join('\n$_split\n'),
      expect: batch.length,
      parse: _parseSplit,
    );
  }

  static Future<List<String>?> _requestWith({
    required ({String baseUrl, String model, String apiKey}) provider,
    required String prompt,
    required String content,
    required int expect,
    required List<String>? Function(String) parse,
  }) async {
    final base = provider.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final data = {
      'model': provider.model.trim(),
      'temperature': 0,
      'stream': false,
      'messages': [
        {'role': 'system', 'content': prompt},
        {'role': 'user', 'content': content},
      ],
    };

    for (var attempt = 0; attempt <= _maxRetry; attempt++) {
      try {
        final res = await _dio.post(
          '$base/chat/completions',
          data: data,
          options: Options(
            headers: {
              'Authorization': 'Bearer ${provider.apiKey.trim()}',
            },
          ),
        );
        final text = _contentOf(res.data);
        if (text != null) {
          final list = parse(text);
          if (list != null && list.length == expect) {
            return list.map((e) => e.trim()).toList();
          }
        }
      } catch (_) {}
      if (attempt < _maxRetry) {
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
    return null;
  }

  static String? _contentOf(dynamic data) {
    if (data is! Map) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final choice = choices.first;
    if (choice is! Map) return null;
    final message = choice['message'];
    if (message is! Map) return null;
    final content = message['content'];
    return content is String ? content : null;
  }

  static List<String>? _parseArray(String text) {
    var s = _stripFence(text);
    final start = s.indexOf('[');
    final end = s.lastIndexOf(']');
    if (start == -1 || end <= start) return null;
    try {
      final list = jsonDecode(s.substring(start, end + 1));
      if (list is! List) return null;
      return list.map((e) => e is String ? e : '$e').toList();
    } catch (_) {
      return null;
    }
  }

  static List<String>? _parseSplit(String text) {
    final s = _stripFence(text).trim();
    if (s.isEmpty) return null;
    final parts = s.split(RegExp(r'\s*' + _split + r'\s*'));
    if (parts.length < 2) return null;
    return parts;
  }

  static String _stripFence(String text) {
    var s = text.trim();
    if (s.startsWith('```')) {
      final first = s.indexOf('\n');
      if (first != -1) s = s.substring(first + 1);
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    }
    return s;
  }

  static String _cacheKey(List<String> batch) {
    final raw =
        '${Pref.subtitleTranslateBaseUrl.trim()}'
        '|${Pref.subtitleTranslateModel.trim()}'
        '|${batch.join('\u0001')}';
    return 'sub_trans_${sha1.convert(utf8.encode(raw))}';
  }

  static List<String>? _readCache(String key, int length) {
    final cached = GStorage.localCache.get(key);
    if (cached is! String || cached.isEmpty) return null;
    try {
      final list = (jsonDecode(cached) as List).cast<String>();
      return list.length == length ? list : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String key, List<String> value) async {
    try {
      await GStorage.localCache.put(key, jsonEncode(value));
    } catch (_) {}
  }

  // ===== 整段字幕缓存 =====
  // 同一字幕地址（同一视频同一语言）译一次就落盘，重进视频/重开 App 直接复用，
  // 不再逐批重译。键里带通道配置与显示模式，换模型或切换「双语/仅译文」会自动失效。
  static const String _vttIndexKey = 'sub_vtt_index';
  static const int _vttCacheLimit = 20;

  static String _vttKey(String url) {
    final raw =
        '${Pref.subtitleTranslateBaseUrl.trim()}'
        '|${Pref.subtitleTranslateModel.trim()}'
        '|${Pref.subtitleTranslateMode}'
        '|$url';
    return 'sub_vtt_${sha1.convert(utf8.encode(raw))}';
  }

  /// 读取已缓存的翻译后 vtt；没有命中返回 null
  static String? readVttCache(String url) {
    try {
      final cached = GStorage.localCache.get(_vttKey(url));
      return cached is String && cached.isNotEmpty ? cached : null;
    } catch (_) {
      return null;
    }
  }

  /// 保存翻译后 vtt，并按 LRU 限制缓存条数
  static Future<void> writeVttCache(String url, String vtt) async {
    if (vtt.isEmpty) return;
    final key = _vttKey(url);
    try {
      await GStorage.localCache.put(key, vtt);
      final index =
          (GStorage.localCache.get(_vttIndexKey) as List?)
              ?.map((e) => '$e')
              .toList() ??
          <String>[];
      index.remove(key);
      index.add(key);
      while (index.length > _vttCacheLimit) {
        await GStorage.localCache.delete(index.removeAt(0));
      }
      await GStorage.localCache.put(_vttIndexKey, index);
    } catch (_) {}
  }

  /// 清掉某个字幕地址的缓存（用户手动要求重新翻译时用）
  static Future<void> clearVttCache(String url) async {
    final key = _vttKey(url);
    try {
      await GStorage.localCache.delete(key);
      final index =
          (GStorage.localCache.get(_vttIndexKey) as List?)
              ?.map((e) => '$e')
              .toList();
      if (index != null && index.remove(key)) {
        await GStorage.localCache.put(_vttIndexKey, index);
      }
    } catch (_) {}
  }

  /// 清空全部字幕翻译缓存（整段 vtt 与分批文本）
  static Future<void> clearAllVttCache() async {
    try {
      final keys = GStorage.localCache.keys
          .where((k) =>
              '$k'.startsWith('sub_vtt_') || '$k'.startsWith('sub_trans_'))
          .toList();
      for (final k in keys) {
        await GStorage.localCache.delete(k);
      }
    } catch (_) {}
  }
}
