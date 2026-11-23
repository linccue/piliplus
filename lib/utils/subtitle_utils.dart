import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:dio/dio.dart' show Options;

enum SubtitleFormat implements EnumWithLabel {
  json('JSON'),
  vtt('WEBVTT'),
  srt('SRT');

  @override
  final String label;
  const SubtitleFormat(this.label);
}

abstract final class SubtitleUtils {
  static const String _json = '.json';
  static const String _bcc = '.bcc';
  static bool isJson(String fileName) =>
      fileName.endsWith(_json) ||
      fileName.endsWith(_bcc) ||
      fileName.endsWith(PathUtils.subtitleExt);

  static const exts = [_json, 'vtt', 'srt', 'ass', _bcc, PathUtils.subtitleExt];

  static String _vttTimecode(num seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    seconds %= 3600;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    seconds %= 60;
    final sms = seconds.toStringAsFixed(3).padLeft(6, '0');
    return "$h:$m:$sms";
  }

  static String json2Vtt(List list) {
    final sb = StringBuffer('WEBVTT\n\n')
      ..writeAll(
        list.map(
          (item) =>
              '${_vttTimecode(item['from'])} --> ${_vttTimecode(item['to'])}\n${item['content'].trim()}',
        ),
        '\n\n',
      );
    return sb.toString();
  }

  static String _srtTimecode(num seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    seconds %= 3600;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    seconds %= 60;
    final s = seconds.toInt();
    final ms = ((seconds - s) * 1000).round().toString().padLeft(3, '0');
    return '$h:$m:${s.toString().padLeft(2, '0')},$ms';
  }

  static String json2Srt(List list) {
    final sb = StringBuffer()
      ..writeAll(
        list.mapIndexed(
          (i, e) =>
              '${i + 1}\n${_srtTimecode(e['from'])} --> ${_srtTimecode(e['to'])}\n${e['content'].trim()}',
        ),
        '\n\n',
      );
    return sb.toString();
  }

  /// 解析本地字幕文本（srt / vtt / ass）为 `[{from, to, content}]`，时间单位：秒
  static List<Map<String, dynamic>>? parseText(String content, String ext) {
    final text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final e = ext.toLowerCase();
    if (e == '.ass' || e == '.ssa') return _parseAss(text);
    if (isJson(e)) return null;
    return _parseCues(text);
  }

  static final RegExp _cueTime = RegExp(
    r'(?:(\d{1,3}):)?(\d{1,2}):(\d{2})[.,](\d{1,3})',
  );

  static double? _cueSeconds(String text) {
    final m = _cueTime.firstMatch(text);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '0') ?? 0;
    final mi = int.tryParse(m.group(2) ?? '');
    final s = int.tryParse(m.group(3) ?? '');
    if (mi == null || s == null) return null;
    final frac = double.tryParse('0.${m.group(4)}') ?? 0;
    return h * 3600 + mi * 60 + s + frac;
  }

  static String _plain(String text) => text
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\{[^}]*\}'), '')
      .replaceAll(r'\N', '\n')
      .trim();

  /// srt / vtt：按 `-->` 时间轴切块
  static List<Map<String, dynamic>>? _parseCues(String text) {
    final lines = text.split('\n');
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.contains('-->')) continue;
      final parts = line.split('-->');
      final from = _cueSeconds(parts[0]);
      final to = parts.length > 1 ? _cueSeconds(parts[1]) : null;
      if (from == null || to == null) continue;
      final buf = <String>[];
      for (var j = i + 1; j < lines.length; j++) {
        final l = lines[j];
        if (l.trim().isEmpty || l.contains('-->')) break;
        buf.add(l);
        i = j;
      }
      final content = _plain(buf.join('\n'));
      if (content.isNotEmpty) {
        out.add({'from': from, 'to': to, 'content': content});
      }
    }
    return out.isEmpty ? null : out;
  }

  /// ass / ssa：只取 [Events] 里的 Dialogue 行
  static List<Map<String, dynamic>>? _parseAss(String text) {
    final out = <Map<String, dynamic>>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimLeft();
      if (!line.toLowerCase().startsWith('dialogue:')) continue;
      final fields = line.substring(9).split(',');
      if (fields.length < 10) continue;
      final from = _assSeconds(fields[1]);
      final to = _assSeconds(fields[2]);
      if (from == null || to == null) continue;
      final content = _plain(fields.sublist(9).join(','));
      if (content.isEmpty) continue;
      out.add({'from': from, 'to': to, 'content': content});
    }
    return out.isEmpty ? null : out;
  }

  static double? _assSeconds(String text) {
    final parts = text.trim().split(':');
    if (parts.length != 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = double.tryParse(parts[2]);
    if (h == null || m == null || s == null) return null;
    return h * 3600 + m * 60 + s;
  }

  static Future<Uint8List?> getSubtitle(String url) async {
    final res = await Request.dio.get<Uint8List>(
      url.http2https,
      options: Options(
        responseType: .bytes,
        headers: Constants.baseHeaders,
        extra: {'account': const NoAccount()},
      ),
    );
    if (res.statusCode != 200) return null;
    return Uint8List.fromList(
      Request.responseBytesDecoder(res.data!, res.headers.map),
    );
  }
}
