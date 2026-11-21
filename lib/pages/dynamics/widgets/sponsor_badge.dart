import 'dart:convert';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

// 全局缓存，防止列表滑动时重复请求
final Map<String, String?> _sponsorCache = {};

class SponsorBadge extends StatefulWidget {
  final String? bvid;
  final bool isStack;
  final double? top;
  final double? right;

  const SponsorBadge({
    super.key,
    required this.bvid,
    this.isStack = true,
    this.top = 8,
    this.right = 8,
  });

  @override
  State<SponsorBadge> createState() => _SponsorBadgeState();
}

class _SponsorBadgeState extends State<SponsorBadge> {
  String? _tagText;

  @override
  void initState() {
    super.initState();
    _loadTag();
  }

  Future<void> _loadTag() async {
    final bvid = widget.bvid;
    if (bvid == null || bvid.isEmpty) return;

    // 1. 检查缓存
    if (_sponsorCache.containsKey(bvid)) {
      if (mounted) setState(() => _tagText = _sponsorCache[bvid]);
      return;
    }

    try {
      // 2. 请求空降助手 API
      final res = await Request().get(
        '${Pref.blockServer}/api/skipSegments',
        queryParameters: {
          'videoID': bvid,
          'categories': '["sponsor","exclusive_access","selfpromo"]',
        },
      );

      String? tag;
      if (res.data is List && (res.data as List).isNotEmpty) {
        final segments = res.data as List;
        final category = segments.first['category'];
        
        // 3. 翻译标签
        switch (category) {
          case 'sponsor':
            tag = '恰饭';
            break;
          case 'exclusive_access':
            tag = '独家/抢先';
            break;
          case 'selfpromo':
            tag = '自我推广';
            break;
        }
      }

      // 4. 写入缓存
      _sponsorCache[bvid] = tag;
      
      if (mounted) {
        setState(() => _tagText = tag);
      }
    } catch (e) {
      // 失败时也缓存 null，避免频繁请求死链
      _sponsorCache[bvid] = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_tagText == null) {
      return const SizedBox.shrink(); // 没有标签就不显示
    }

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _tagText!,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (!widget.isStack) {
      return content;
    }

    return Positioned(
      top: widget.top,
      right: widget.right,
      child: content,
    );
  }
}
