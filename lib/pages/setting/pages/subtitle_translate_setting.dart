import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/setting/widgets/switch_item.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/subtitle_translator.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

class SubtitleTranslateSetting extends StatefulWidget {
  const SubtitleTranslateSetting({super.key});

  @override
  State<SubtitleTranslateSetting> createState() =>
      _SubtitleTranslateSettingState();
}

class _SubtitleTranslateSettingState extends State<SubtitleTranslateSetting> {
  late final _baseUrl = TextEditingController(
    text: Pref.subtitleTranslateBaseUrl,
  );
  late final _model = TextEditingController(text: Pref.subtitleTranslateModel);
  late final _apiKey = TextEditingController(text: Pref.subtitleTranslateApiKey);
  late final _fbBaseUrl = TextEditingController(
    text: Pref.subtitleTranslateFallbackBaseUrl,
  );
  late final _fbModel = TextEditingController(
    text: Pref.subtitleTranslateFallbackModel,
  );
  late final _fbApiKey = TextEditingController(
    text: Pref.subtitleTranslateFallbackApiKey,
  );

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _fbBaseUrl.dispose();
    _fbModel.dispose();
    _fbApiKey.dispose();
    super.dispose();
  }

  void _save(String key, String value) {
    GStorage.setting.put(key, value.trim());
  }

  Future<void> _test() async {
    if (Pref.subtitleTranslateApiKey.trim().isEmpty &&
        Pref.subtitleTranslateFallbackApiKey.trim().isEmpty) {
      SmartDialog.showToast('请先填写至少一个通道的 API Key');
      return;
    }
    SmartDialog.showLoading(msg: '正在测试');
    final res = await SubtitleTranslator.test();
    SmartDialog.dismiss();
    final msg = res.ok
        ? (res.viaFallback
              ? '主通道失败，备用通道成功：${res.text}'
              : '主通道成功：${res.text}')
        : '两个通道都失败，请检查地址、模型与密钥';
    SmartDialog.showToast(msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );

    return SimpleScaffold(
      appBar: AppBar(title: const Text('字幕翻译')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SetSwitchItem(
            title: '启用字幕翻译',
            subtitle: '播放外语字幕时自动翻译成简体中文，翻译过的字幕会保存到本地复用',
            setKey: SettingBoxKey.subtitleTranslateEnabled,
            leading: Icon(Icons.translate),
          ),
          ListTile(
            title: const Text('保留原文（双语显示）'),
            subtitle: Text('关闭后只显示中文译文', style: hintStyle),
            trailing: Switch(
              value: Pref.subtitleTranslateMode == 0,
              onChanged: (val) {
                GStorage.setting.put(
                  SettingBoxKey.subtitleTranslateMode,
                  val ? 0 : 1,
                );
                setState(() {});
              },
            ),
          ),
          const Divider(height: 1),
          _buildField(
            label: '接口地址',
            controller: _baseUrl,
            hint: 'https://api.hunyuan.cloud.tencent.com/v1',
            onChanged: (v) => _save(SettingBoxKey.subtitleTranslateBaseUrl, v),
          ),
          _buildField(
            label: '模型',
            controller: _model,
            hint: 'hunyuan-translation',
            onChanged: (v) => _save(SettingBoxKey.subtitleTranslateModel, v),
          ),
          _buildField(
            label: 'API Key',
            controller: _apiKey,
            hint: '在腾讯云 TokenHub 创建，模型权限勾选 hunyuan-translation',
            onChanged: (v) => _save(SettingBoxKey.subtitleTranslateApiKey, v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Text(
              '默认使用腾讯混元翻译专用模型 hunyuan-translation（33 种语言互译）：免费、国内直连、不需要代理。'
              '在腾讯云控制台「TokenHub」创建 API Key，模型权限勾选 hunyuan-translation。'
              '字幕按 20 句一批串行翻译，成功一批缓存一批，失败的批次会自动拆半重试；'
              '整段译完会把字幕全文存进本地，同一个视频再次打开直接读缓存、不再联网重译。'
              '换模型、换地址或切换「双语/仅译文」会重新翻译。B 站本身已有中文（含 AI）字幕的视频不会走翻译。',
              style: hintStyle,
            ),
          ),
          const Divider(height: 1),
          const SetSwitchItem(
            title: '启用备用通道',
            subtitle: '主通道失败时自动切到智谱 GLM-4.7-Flash，需填写备用密钥',
            setKey: SettingBoxKey.subtitleTranslateFallbackEnabled,
            leading: Icon(Icons.swap_horiz),
          ),
          _buildField(
            label: '备用接口地址',
            controller: _fbBaseUrl,
            hint: 'https://open.bigmodel.cn/api/paas/v4',
            onChanged: (v) =>
                _save(SettingBoxKey.subtitleTranslateFallbackBaseUrl, v),
          ),
          _buildField(
            label: '备用模型',
            controller: _fbModel,
            hint: 'glm-4.7-flash',
            onChanged: (v) =>
                _save(SettingBoxKey.subtitleTranslateFallbackModel, v),
          ),
          _buildField(
            label: '备用 API Key',
            controller: _fbApiKey,
            hint: '智谱开放平台（bigmodel.cn）创建的 API Key',
            onChanged: (v) =>
                _save(SettingBoxKey.subtitleTranslateFallbackApiKey, v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '备用通道用 glm-4.7-flash：免费、200K 上下文，但免费档并发很低，'
              '同一时间只会有一个请求；主通道靠不住时才会被叫起来。',
              style: hintStyle,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.wifi_tethering),
            title: const Text('测试接口'),
            subtitle: Text('依次试主通道和备用通道', style: hintStyle),
            onTap: _test,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('清除翻译缓存'),
            subtitle: Text(
              '删掉已保存的翻译结果，再次播放该视频会重新翻译',
              style: hintStyle,
            ),
            onTap: () async {
              await SubtitleTranslator.clearAllVttCache();
              SmartDialog.showToast('字幕翻译缓存已清除');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
